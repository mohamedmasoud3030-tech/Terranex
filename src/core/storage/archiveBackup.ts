import {
  clearTerranexData,
  createTerranexBackup,
  parseTerranexBackup,
  restoreTerranexBackup,
  summarizeTerranexRecords,
  type BackupSummary,
  type TerranexBackup,
} from './backup';
import {
  clearDocumentFiles,
  listDocumentFiles,
  makeLocalDocumentFileUrl,
  replaceDocumentFiles,
  type StoredDocumentFile,
} from './indexedDbFileStore';
import { createZipArchive, readZipArchive, type ZipArchiveEntry } from './zipArchive';

const MANIFEST_PATH = 'manifest.json';
const RECORDS_PATH = 'records.json';
const FILES_DIRECTORY = 'files/';
export const TERRANEX_ARCHIVE_SCHEMA_VERSION = 1;

export interface ArchiveDocumentFile extends Omit<StoredDocumentFile, 'blob'> {
  archive_path: string;
}

export interface TerranexArchiveManifest {
  schema_version: number;
  exported_at: string;
  files: ArchiveDocumentFile[];
}

export interface TerranexArchiveSummary extends BackupSummary {
  files: number;
  total_file_bytes: number;
}

export interface ParsedTerranexArchive {
  manifest: TerranexArchiveManifest;
  backup: TerranexBackup;
  files: StoredDocumentFile[];
  summary: TerranexArchiveSummary;
}

export interface DocumentFileRepository {
  list(): Promise<StoredDocumentFile[]>;
  replace(records: StoredDocumentFile[]): Promise<void>;
  clear(): Promise<void>;
}

export const browserDocumentFileRepository: DocumentFileRepository = {
  list: listDocumentFiles,
  replace: replaceDocumentFiles,
  clear: clearDocumentFiles,
};

function archiveError(message: string) {
  return new Error(`نسخة Terranex الاحتياطية غير صالحة: ${message}`);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function requireString(record: Record<string, unknown>, field: string) {
  const value = record[field];
  if (typeof value !== 'string' || !value.trim()) throw archiveError(`الحقل ${field} غير صالح.`);
  return value;
}

function requireBoolean(record: Record<string, unknown>, field: string) {
  const value = record[field];
  if (typeof value !== 'boolean') throw archiveError(`الحقل ${field} غير صالح.`);
  return value;
}

function requirePositiveInteger(record: Record<string, unknown>, field: string) {
  const value = record[field];
  if (!Number.isInteger(value) || Number(value) < 1) throw archiveError(`الحقل ${field} غير صالح.`);
  return Number(value);
}

function optionalString(record: Record<string, unknown>, field: string) {
  const value = record[field];
  if (value === undefined) return undefined;
  if (typeof value !== 'string' || !value.trim()) throw archiveError(`الحقل ${field} غير صالح.`);
  return value;
}

function encodeJson(value: unknown) {
  return new TextEncoder().encode(JSON.stringify(value, null, 2));
}

function decodeJson(bytes: Uint8Array, label: string) {
  try {
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) as unknown;
  } catch {
    throw archiveError(`تعذر قراءة ${label}.`);
  }
}

function requireArchiveFile(files: Map<string, Uint8Array>, path: string) {
  const bytes = files.get(path);
  if (!bytes) throw archiveError(`الملف ${path} مفقود.`);
  return bytes;
}

function makeArchivePath(record: Pick<StoredDocumentFile, 'id' | 'file_name'>) {
  return `${FILES_DIRECTORY}${encodeURIComponent(record.id)}/${encodeURIComponent(record.file_name)}`;
}

function toManifestFile(record: StoredDocumentFile): ArchiveDocumentFile {
  const { blob: _blob, ...metadata } = record;
  return { ...metadata, archive_path: makeArchivePath(record) };
}

function parseManifestFile(value: unknown): ArchiveDocumentFile {
  if (!isRecord(value)) throw archiveError('بيانات أحد الملفات ناقصة.');
  if (requireString(value, 'storage_mode') !== 'indexeddb') throw archiveError('نوع تخزين أحد الملفات غير مدعوم.');

  const file: ArchiveDocumentFile = {
    id: requireString(value, 'id'),
    document_id: requireString(value, 'document_id'),
    file_name: requireString(value, 'file_name'),
    original_file_name: requireString(value, 'original_file_name'),
    mime_type: requireString(value, 'mime_type'),
    size_bytes: requirePositiveInteger(value, 'size_bytes'),
    created_at: requireString(value, 'created_at'),
    updated_at: requireString(value, 'updated_at'),
    sha256: optionalString(value, 'sha256'),
    storage_mode: 'indexeddb',
    version: requirePositiveInteger(value, 'version'),
    archived: requireBoolean(value, 'archived'),
    archive_path: requireString(value, 'archive_path'),
  };

  if (file.id !== file.document_id) throw archiveError('معركف ملف المستند لا يطابق المستند المرتبط.');
  if (file.archive_path !== makeArchivePath(file)) throw archiveError('مسار ملف داخل الأرشيف لا يطابق بياناته.');
  return file;
}

function parseManifest(bytes: Uint8Array): TerranexArchiveManifest {
  const raw = decodeJson(bytes, MANIFEST_PATH);
  if (!isRecord(raw)) throw archiveError('صيغة manifest.json غير صالحة.');
  if (raw.schema_version !== TERRANEX_ARCHIVE_SCHEMA_VERSION) throw archiveError('إصدار الأرشيف غير متوافق مع هذا الإصدار من Terranex.');
  if (typeof raw.exported_at !== 'string' || !Array.isArray(raw.files)) throw archiveError('بيانات manifest.json ناقصة.');

  const files = raw.files.map(parseManifestFile);
  const ids = new Set<string>();
  const paths = new Set<string>();
  for (const file of files) {
    if (ids.has(file.id) || paths.has(file.archive_path)) throw archiveError('توجد ملفات مكررة داخل الأرشيف.');
    ids.add(file.id);
    paths.add(file.archive_path);
  }
  return { schema_version: TERRANEX_ARCHIVE_SCHEMA_VERSION, exported_at: raw.exported_at, files };
}

function parseDocumentRecords(backup: TerranexBackup) {
  let parsed: unknown;
  try {
    parsed = JSON.parse(backup.records['terranex.documents.v1'] ?? '[]') as unknown;
  } catch {
    throw archiveError('سجل المستندات داخل records.json غير صالح.');
  }
  if (!Array.isArray(parsed) || parsed.some((document) => !isRecord(document))) {
    throw archiveError('سجل المستندات داخل records.json غير صالح.');
  }
  return parsed as Record<string, unknown>[];
}

function validateDocumentLinks(backup: TerranexBackup, files: ArchiveDocumentFile[]) {
  const documents = parseDocumentRecords(backup);
  const documentById = new Map(documents.map((document) => [document.id, document]));
  const fileById = new Map(files.map((file) => [file.id, file]));

  for (const file of files) {
    const document = documentById.get(file.document_id);
    if (!document) throw archiveError('يوجد ملف محلي دون سجل مستند مرتبط.');
    if (document.file_url !== makeLocalDocumentFileUrl(file.document_id)
      || document.file_name !== file.file_name
      || document.file_mime_type !== file.mime_type
      || document.file_size_bytes !== file.size_bytes
      || (document.file_sha256 !== undefined && document.file_sha256 !== file.sha256)) {
      throw archiveError('بيانات ملف محلي لا تطابق سجل المستند المرتبط.');
    }
  }

  for (const document of documents) {
    if (typeof document.file_url !== 'string' || !document.file_url.startsWith('indexeddb://document-files/')) continue;
    if (typeof document.id !== 'string' || !fileById.has(document.id)) throw archiveError('يوجد مستند يشير إلى ملف محلي مفقود.');
  }
}

function validateArchiveEntries(entries: Map<string, Uint8Array>, manifest: TerranexArchiveManifest) {
  const allowed = new Set([MANIFEST_PATH, RECORDS_PATH, ...manifest.files.map((file) => file.archive_path)]);
  for (const path of entries.keys()) {
    if (!allowed.has(path)) throw archiveError(`يحتوي الأرشيف على ملف غير متوقع: ${path}`);
  }
}

function summarizeArchive(backup: TerranexBackup, files: ArchiveDocumentFile[]): TerranexArchiveSummary {
  return {
    ...summarizeTerranexRecords(backup.records),
    files: files.length,
    total_file_bytes: files.reduce((sum, file) => sum + file.size_bytes, 0),
  };
}

export async function createTerranexArchive(storage: Storage = localStorage, repository: DocumentFileRepository = browserDocumentFileRepository) {
  const backup = createTerranexBackup(storage);
  const storedFiles = await repository.list();
  const manifest: TerranexArchiveManifest = {
    schema_version: TERRANEX_ARCHIVE_SCHEMA_VERSION,
    exported_at: backup.exported_at,
    files: storedFiles.map(toManifestFile),
  };
  validateDocumentLinks(backup, manifest.files);

  const entries: ZipArchiveEntry[] = [
    { path: MANIFEST_PATH, bytes: encodeJson(manifest) },
    { path: RECORDS_PATH, bytes: encodeJson(backup) },
  ];
  for (const file of storedFiles) {
    entries.push({ path: makeArchivePath(file), bytes: new Uint8Array(await file.blob.arrayBuffer()) });
  }
  return { bytes: createZipArchive(entries), manifest, summary: summarizeArchive(backup, manifest.files) };
}

export function parseTerranexArchive(bytes: Uint8Array): ParsedTerranexArchive {
  const entries = readZipArchive(bytes);
  const manifest = parseManifest(requireArchiveFile(entries, MANIFEST_PATH));
  const recordsText = new TextDecoder('utf-8', { fatal: true }).decode(requireArchiveFile(entries, RECORDS_PATH));
  const backup = parseTerranexBackup(recordsText);
  validateArchiveEntries(entries, manifest);
  validateDocumentLinks(backup, manifest.files);

  const files = manifest.files.map((file): StoredDocumentFile => {
    const payload = requireArchiveFile(entries, file.archive_path);
    if (payload.length !== file.size_bytes) throw archiveError('حجم ملف داخل الأرشيف لا يطابق manifest.json.');
    const { archive_path: _archivePath, ...metadata } = file;
    return { ...metadata, blob: new Blob([payload], { type: file.mime_type }) };
  });
  return { manifest, backup, files, summary: summarizeArchive(backup, manifest.files) };
}

async function rollbackWorkspace(previousBackup: TerranexBackup, previousFiles: StoredDocumentFile[], storage: Storage, repository: DocumentFileRepository) {
  try {
    restoreTerranexBackup(previousBackup, storage);
    await repository.replace(previousFiles);
  } catch {
    throw new Error('تعذر التراجع الكامل عن تعديل البيانات المحلية. لا تغلق الصفحة وراجع النسخة الاحتياطية فورًا.');
  }
}

export async function restoreTerranexArchive(archive: ParsedTerranexArchive, storage: Storage = localStorage, repository: DocumentFileRepository = browserDocumentFileRepository) {
  const previousBackup = createTerranexBackup(storage);
  const previousFiles = await repository.list();
  try {
    restoreTerranexBackup(archive.backup, storage);
    await repository.replace(archive.files);
  } catch (error) {
    await rollbackWorkspace(previousBackup, previousFiles, storage, repository);
    throw error;
  }
  return { previousBackup, previousFiles };
}

export async function clearTerranexArchiveData(storage: Storage = localStorage, repository: DocumentFileRepository = browserDocumentFileRepository) {
  const previousBackup = createTerranexBackup(storage);
  const previousFiles = await repository.list();
  try {
    clearTerranexData(storage);
    await repository.clear();
  } catch (error) {
    await rollbackWorkspace(previousBackup, previousFiles, storage, repository);
    throw error;
  }
  return { previousBackup, previousFiles };
}

import { validateDocumentUpload } from '../lib/documentFileValidation';

const DATABASE_NAME = 'terranex.local-files';
const DATABASE_VERSION = 1;
const DOCUMENT_FILES_STORE = 'document-files';
const LOCAL_FILE_URL_PREFIX = 'indexeddb://document-files/';

export interface StoredDocumentFile {
  id: string;
  document_id: string;
  file_name: string;
  original_file_name: string;
  mime_type: string;
  size_bytes: number;
  created_at: string;
  updated_at: string;
  sha256?: string;
  storage_mode: 'indexeddb';
  version: number;
  archived: boolean;
  blob: Blob;
}

function makeStorageError(message: string, cause?: unknown) {
  return new Error(message, cause === undefined ? undefined : { cause });
}

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      reject(makeStorageError('متصفحك لا يدعم حفظ الملفات المحلية عبر IndexedDB.'));
      return;
    }

    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(DOCUMENT_FILES_STORE)) {
        database.createObjectStore(DOCUMENT_FILES_STORE, { keyPath: 'id' });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(makeStorageError('تعذر فتح مخزن الملفات المحلي.', request.error));
    request.onblocked = () => reject(makeStorageError('تعذر تحديث مخزن الملفات لأن نافذة أخرى تستخدم إصدارًا قديمًا من التطبيق.'));
  });
}

function waitForTransaction(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(makeStorageError('فشلت عملية حفظ الملف المحلي.', transaction.error));
    transaction.onabort = () => reject(makeStorageError('تم إلغاء عملية حفظ الملف المحلي.', transaction.error));
  });
}

function readRequest<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(makeStorageError('تعذر قراءة الملف المحلي.', request.error));
  });
}

async function withStore<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore, transaction: IDBTransaction) => Promise<T> | T) {
  const database = await openDatabase();
  try {
    const transaction = database.transaction(DOCUMENT_FILES_STORE, mode);
    const completed = waitForTransaction(transaction);
    const result = await run(transaction.objectStore(DOCUMENT_FILES_STORE), transaction);
    await completed;
    return result;
  } finally {
    database.close();
  }
}

function getExtension(fileName: string) {
  const dotIndex = fileName.lastIndexOf('.');
  return dotIndex >= 0 ? fileName.slice(dotIndex).toLowerCase() : '';
}

async function computeSha256(blob: Blob): Promise<string | undefined> {
  if (!globalThis.crypto?.subtle) return undefined;
  try {
    const digest = await globalThis.crypto.subtle.digest('SHA-256', await blob.arrayBuffer());
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  } catch {
    return undefined;
  }
}

function validateStoredDocumentFile(record: StoredDocumentFile) {
  if (!record.id.trim() || record.document_id !== record.id) throw new Error('معرّف ملف المستند المحلي غير صالح.');
  if (!record.file_name.trim() || !record.original_file_name.trim() || !record.mime_type.trim()) {
    throw new Error('بيانات ملف المستند المحلي ناقصة.');
  }
  if (!Number.isFinite(record.size_bytes) || record.size_bytes <= 0 || record.blob.size !== record.size_bytes) {
    throw new Error('حجم ملف المستند المحلي غير صالح.');
  }
  if (record.storage_mode !== 'indexeddb' || !Number.isInteger(record.version) || record.version < 1) {
    throw new Error('إصدار تخزين ملف المستند المحلي غير صالح.');
  }
}

async function putDocumentFile(record: StoredDocumentFile): Promise<void> {
  validateStoredDocumentFile(record);
  await withStore('readwrite', (store) => {
    store.put(record);
  });
}

export function makeLocalDocumentFileUrl(documentId: string) {
  return `${LOCAL_FILE_URL_PREFIX}${encodeURIComponent(documentId)}`;
}

export function readLocalDocumentFileId(fileUrl?: string) {
  if (!fileUrl?.startsWith(LOCAL_FILE_URL_PREFIX)) return null;
  const encodedId = fileUrl.slice(LOCAL_FILE_URL_PREFIX.length);
  if (!encodedId) return null;
  try {
    return decodeURIComponent(encodedId);
  } catch {
    return null;
  }
}

export async function saveDocumentFile(documentId: string, file: File): Promise<StoredDocumentFile> {
  const id = documentId.trim();
  if (!id) throw new Error('معرّف المستند مطلوب لحفظ الملف.');
  validateDocumentUpload(file);

  const now = new Date().toISOString();
  const record: StoredDocumentFile = {
    id,
    document_id: id,
    file_name: `${id}${getExtension(file.name)}`,
    original_file_name: file.name,
    mime_type: file.type,
    size_bytes: file.size,
    created_at: now,
    updated_at: now,
    sha256: await computeSha256(file),
    storage_mode: 'indexeddb',
    version: 1,
    archived: false,
    blob: file,
  };

  await putDocumentFile(record);
  return record;
}

export async function restoreDocumentFile(record: StoredDocumentFile): Promise<void> {
  await putDocumentFile(record);
}

export async function getDocumentFile(fileUrl: string): Promise<StoredDocumentFile | undefined> {
  const id = readLocalDocumentFileId(fileUrl);
  if (!id) return undefined;
  return withStore('readonly', (store) => readRequest(store.get(id) as IDBRequest<StoredDocumentFile | undefined>));
}

export async function listDocumentFiles(): Promise<StoredDocumentFile[]> {
  return withStore('readonly', (store) => readRequest(store.getAll() as IDBRequest<StoredDocumentFile[]>));
}

export async function replaceDocumentFiles(records: StoredDocumentFile[]): Promise<void> {
  const seen = new Set<string>();
  for (const record of records) {
    validateStoredDocumentFile(record);
    if (seen.has(record.id)) throw new Error('توجد ملفات مستندات محلية مكررة.');
    seen.add(record.id);
  }

  await withStore('readwrite', (store) => {
    store.clear();
    for (const record of records) store.put(record);
  });
}

export async function clearDocumentFiles(): Promise<void> {
  await withStore('readwrite', (store) => {
    store.clear();
  });
}

export async function deleteDocumentFile(fileUrl: string): Promise<void> {
  const id = readLocalDocumentFileId(fileUrl);
  if (!id) return;
  await withStore('readwrite', (store) => {
    store.delete(id);
  });
}

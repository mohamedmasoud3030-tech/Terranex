const LOCAL_FILE_HEADER_SIGNATURE = 0x04034b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const END_OF_CENTRAL_DIRECTORY_SIGNATURE = 0x06054b50;
const UTF8_FLAG = 0x0800;
const STORED_METHOD = 0;
const FIXED_DOS_DATE = 0x0021; // 1980-01-01 for deterministic archives.
const MAX_UINT16 = 0xffff;
const MAX_UINT32 = 0xffffffff;
const LOCAL_HEADER_SIZE = 30;
const CENTRAL_HEADER_SIZE = 46;
const MIN_END_RECORD_SIZE = 22;

export interface ZipArchiveEntry {
  path: string;
  bytes: Uint8Array;
}

interface EncodedEntry extends ZipArchiveEntry {
  nameBytes: Uint8Array;
  checksum: number;
}

interface CentralEntry {
  path: string;
  nameBytes: Uint8Array;
  checksum: number;
  compressedSize: number;
  uncompressedSize: number;
  flags: number;
  method: number;
  localOffset: number;
  nextCursor: number;
}

interface CentralDirectoryInfo {
  entryCount: number;
  centralOffset: number;
  centralSize: number;
}

function makeArchiveError(message: string) {
  return new Error(`أرشيف النسخة الاحتياطية غير صالح: ${message}`);
}

function writeUint16(target: Uint8Array, offset: number, value: number) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >>> 8) & 0xff;
}

function writeUint32(target: Uint8Array, offset: number, value: number) {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >>> 8) & 0xff;
  target[offset + 2] = (value >>> 16) & 0xff;
  target[offset + 3] = (value >>> 24) & 0xff;
}

function readUint16(source: Uint8Array, offset: number) {
  requireRange(source, offset, 2);
  return source[offset] | (source[offset + 1] << 8);
}

function readUint32(source: Uint8Array, offset: number) {
  requireRange(source, offset, 4);
  return (source[offset]
    | (source[offset + 1] << 8)
    | (source[offset + 2] << 16)
    | (source[offset + 3] << 24)) >>> 0;
}

function requireRange(source: Uint8Array, offset: number, length: number) {
  if (!Number.isInteger(offset) || !Number.isInteger(length) || offset < 0 || length < 0 || offset + length > source.length) {
    throw makeArchiveError('الملف مبتور أو يحتوي على حدود غير صالحة.');
  }
}

function concatenate(parts: Uint8Array[]) {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const output = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function validatePath(path: string) {
  if (!path || path.startsWith('/') || path.includes('\\')) {
    throw makeArchiveError('يحتوي الأرشيف على مسار ملف غير مسموح.');
  }
  const segments = path.split('/');
  if (segments.some((segment) => !segment || segment === '.' || segment === '..')) {
    throw makeArchiveError('يحتوي الأرشيف على مسار ملف غير آمن.');
  }
}

function equalBytes(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
}

const CRC32_TABLE = Array.from({ length: 256 }, (_, tableIndex) => {
  let value = tableIndex;
  for (let bit = 0; bit < 8; bit += 1) {
    value = (value & 1) !== 0 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }
  return value >>> 0;
});

export function computeCrc32(bytes: Uint8Array) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = CRC32_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function encodeEntries(entries: ZipArchiveEntry[]) {
  if (entries.length > MAX_UINT16) throw makeArchiveError('عدد الملفات يتجاوز الحد المدعوم.');

  const encoder = new TextEncoder();
  const paths = new Set<string>();
  return entries.map((entry): EncodedEntry => {
    validatePath(entry.path);
    if (paths.has(entry.path)) throw makeArchiveError('يحتوي الأرشيف على مسارات ملفات مكررة.');
    paths.add(entry.path);

    const nameBytes = encoder.encode(entry.path);
    if (nameBytes.length > MAX_UINT16) throw makeArchiveError('اسم ملف داخل الأرشيف أطول من الحد المدعوم.');
    if (entry.bytes.length > MAX_UINT32) throw makeArchiveError('حجم ملف داخل الأرشيف يتجاوز الحد المدعوم.');
    return { ...entry, nameBytes, checksum: computeCrc32(entry.bytes) };
  });
}

function createLocalHeader(entry: EncodedEntry) {
  const header = new Uint8Array(LOCAL_HEADER_SIZE + entry.nameBytes.length);
  writeUint32(header, 0, LOCAL_FILE_HEADER_SIGNATURE);
  writeUint16(header, 4, 20);
  writeUint16(header, 6, UTF8_FLAG);
  writeUint16(header, 8, STORED_METHOD);
  writeUint16(header, 10, 0);
  writeUint16(header, 12, FIXED_DOS_DATE);
  writeUint32(header, 14, entry.checksum);
  writeUint32(header, 18, entry.bytes.length);
  writeUint32(header, 22, entry.bytes.length);
  writeUint16(header, 26, entry.nameBytes.length);
  writeUint16(header, 28, 0);
  header.set(entry.nameBytes, LOCAL_HEADER_SIZE);
  return header;
}

function createCentralHeader(entry: EncodedEntry, localOffset: number) {
  const header = new Uint8Array(CENTRAL_HEADER_SIZE + entry.nameBytes.length);
  writeUint32(header, 0, CENTRAL_DIRECTORY_SIGNATURE);
  writeUint16(header, 4, 20);
  writeUint16(header, 6, 20);
  writeUint16(header, 8, UTF8_FLAG);
  writeUint16(header, 10, STORED_METHOD);
  writeUint16(header, 12, 0);
  writeUint16(header, 14, FIXED_DOS_DATE);
  writeUint32(header, 16, entry.checksum);
  writeUint32(header, 20, entry.bytes.length);
  writeUint32(header, 24, entry.bytes.length);
  writeUint16(header, 28, entry.nameBytes.length);
  writeUint16(header, 30, 0);
  writeUint16(header, 32, 0);
  writeUint16(header, 34, 0);
  writeUint16(header, 36, 0);
  writeUint32(header, 38, 0);
  writeUint32(header, 42, localOffset);
  header.set(entry.nameBytes, CENTRAL_HEADER_SIZE);
  return header;
}

function createEndRecord(entryCount: number, centralSize: number, centralOffset: number) {
  const record = new Uint8Array(MIN_END_RECORD_SIZE);
  writeUint32(record, 0, END_OF_CENTRAL_DIRECTORY_SIGNATURE);
  writeUint16(record, 4, 0);
  writeUint16(record, 6, 0);
  writeUint16(record, 8, entryCount);
  writeUint16(record, 10, entryCount);
  writeUint32(record, 12, centralSize);
  writeUint32(record, 16, centralOffset);
  writeUint16(record, 20, 0);
  return record;
}

export function createZipArchive(entries: ZipArchiveEntry[]) {
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let localOffset = 0;

  for (const entry of encodeEntries(entries)) {
    const localHeader = createLocalHeader(entry);
    localParts.push(localHeader, entry.bytes);
    centralParts.push(createCentralHeader(entry, localOffset));
    localOffset += localHeader.length + entry.bytes.length;
  }

  const centralDirectory = concatenate(centralParts);
  return concatenate([...localParts, centralDirectory, createEndRecord(entries.length, centralDirectory.length, localOffset)]);
}

function findEndRecord(source: Uint8Array) {
  const minOffset = Math.max(0, source.length - MIN_END_RECORD_SIZE - MAX_UINT16);
  for (let offset = source.length - MIN_END_RECORD_SIZE; offset >= minOffset; offset -= 1) {
    if (readUint32(source, offset) !== END_OF_CENTRAL_DIRECTORY_SIGNATURE) continue;
    const commentLength = readUint16(source, offset + 20);
    if (offset + MIN_END_RECORD_SIZE + commentLength === source.length) return offset;
  }
  throw makeArchiveError('تعذر العثور على نهاية الأرشيف.');
}

function readCentralDirectoryInfo(source: Uint8Array): CentralDirectoryInfo {
  if (source.length < MIN_END_RECORD_SIZE) throw makeArchiveError('الملف أقصر من الحد الأدنى لأرشيف ZIP.');

  const endOffset = findEndRecord(source);
  const diskNumber = readUint16(source, endOffset + 4);
  const centralDiskNumber = readUint16(source, endOffset + 6);
  const entriesOnDisk = readUint16(source, endOffset + 8);
  const entryCount = readUint16(source, endOffset + 10);
  const centralSize = readUint32(source, endOffset + 12);
  const centralOffset = readUint32(source, endOffset + 16);

  if (diskNumber !== 0 || centralDiskNumber !== 0 || entriesOnDisk !== entryCount) {
    throw makeArchiveError('الأرشيف متعدد الأجزاء غير مدعوم.');
  }
  requireRange(source, centralOffset, centralSize);
  if (centralOffset + centralSize > endOffset) throw makeArchiveError('فهرس الملفات يتجاوز حدود الأرشيف.');
  return { entryCount, centralOffset, centralSize };
}

function decodePath(decoder: TextDecoder, nameBytes: Uint8Array) {
  try {
    return decoder.decode(nameBytes);
  } catch {
    throw makeArchiveError('اسم ملف داخل الأرشيف ليس UTF-8 صالحًا.');
  }
}

function readCentralEntry(source: Uint8Array, cursor: number, decoder: TextDecoder): CentralEntry {
  requireRange(source, cursor, CENTRAL_HEADER_SIZE);
  if (readUint32(source, cursor) !== CENTRAL_DIRECTORY_SIGNATURE) {
    throw makeArchiveError('فهرس الملفات يحتوي على توقيع غير صالح.');
  }

  const flags = readUint16(source, cursor + 8);
  const method = readUint16(source, cursor + 10);
  const checksum = readUint32(source, cursor + 16);
  const compressedSize = readUint32(source, cursor + 20);
  const uncompressedSize = readUint32(source, cursor + 24);
  const nameLength = readUint16(source, cursor + 28);
  const extraLength = readUint16(source, cursor + 30);
  const commentLength = readUint16(source, cursor + 32);
  const diskStart = readUint16(source, cursor + 34);
  const localOffset = readUint32(source, cursor + 42);

  if ((flags & UTF8_FLAG) === 0 || (flags & 0x0009) !== 0) throw makeArchiveError('خصائص ملف داخل الأرشيف غير مدعومة.');
  if (method !== STORED_METHOD || compressedSize !== uncompressedSize) throw makeArchiveError('ضغط ملفات ZIP غير مدعوم في هذا الإصدار.');
  if (diskStart !== 0) throw makeArchiveError('الأرشيف متعدد الأجزاء غير مدعوم.');

  requireRange(source, cursor + CENTRAL_HEADER_SIZE, nameLength + extraLength + commentLength);
  const nameBytes = source.slice(cursor + CENTRAL_HEADER_SIZE, cursor + CENTRAL_HEADER_SIZE + nameLength);
  const path = decodePath(decoder, nameBytes);
  validatePath(path);
  return {
    path,
    nameBytes,
    checksum,
    compressedSize,
    uncompressedSize,
    flags,
    method,
    localOffset,
    nextCursor: cursor + CENTRAL_HEADER_SIZE + nameLength + extraLength + commentLength,
  };
}

function readStoredPayload(source: Uint8Array, entry: CentralEntry) {
  requireRange(source, entry.localOffset, LOCAL_HEADER_SIZE);
  if (readUint32(source, entry.localOffset) !== LOCAL_FILE_HEADER_SIGNATURE) {
    throw makeArchiveError('ترويسة ملف داخل الأرشيف غير صالحة.');
  }
  if (readUint16(source, entry.localOffset + 6) !== entry.flags || readUint16(source, entry.localOffset + 8) !== entry.method) {
    throw makeArchiveError('ترويسة الملف لا تطابق فهرس الأرشيف.');
  }
  if (readUint32(source, entry.localOffset + 14) !== entry.checksum
    || readUint32(source, entry.localOffset + 18) !== entry.compressedSize
    || readUint32(source, entry.localOffset + 22) !== entry.uncompressedSize) {
    throw makeArchiveError('بيانات حجم الملف أو بصمته لا تطابق فهرس الأرشيف.');
  }

  const localNameLength = readUint16(source, entry.localOffset + 26);
  const localExtraLength = readUint16(source, entry.localOffset + 28);
  requireRange(source, entry.localOffset + LOCAL_HEADER_SIZE, localNameLength + localExtraLength + entry.compressedSize);
  const localNameBytes = source.slice(entry.localOffset + LOCAL_HEADER_SIZE, entry.localOffset + LOCAL_HEADER_SIZE + localNameLength);
  if (!equalBytes(localNameBytes, entry.nameBytes)) throw makeArchiveError('اسم الملف لا يطابق فهرس الأرشيف.');

  const payloadOffset = entry.localOffset + LOCAL_HEADER_SIZE + localNameLength + localExtraLength;
  const payload = source.slice(payloadOffset, payloadOffset + entry.compressedSize);
  if (computeCrc32(payload) !== entry.checksum) throw makeArchiveError('فشل التحقق من سلامة ملف داخل الأرشيف.');
  return payload;
}

export function readZipArchive(source: Uint8Array) {
  const { entryCount, centralOffset, centralSize } = readCentralDirectoryInfo(source);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const files = new Map<string, Uint8Array>();
  let cursor = centralOffset;

  for (let index = 0; index < entryCount; index += 1) {
    const entry = readCentralEntry(source, cursor, decoder);
    if (files.has(entry.path)) throw makeArchiveError('يحتوي الأرشيف على مسارات ملفات مكررة.');
    files.set(entry.path, readStoredPayload(source, entry));
    cursor = entry.nextCursor;
  }

  if (cursor !== centralOffset + centralSize) throw makeArchiveError('حجم فهرس الملفات غير متطابق.');
  return files;
}

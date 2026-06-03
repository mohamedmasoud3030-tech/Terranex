const LOCAL_FILE_HEADER_SIGNATURE = 0x04034b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const END_OF_CENTRAL_DIRECTORY_SIGNATURE = 0x06054b50;
const UTF8_FLAG = 0x0800;
const STORED_METHOD = 0;
const FIXED_DOS_DATE = 0x0021; // 1980-01-01 for deterministic archives.
const MAX_UINT16 = 0xffff;
const MAX_UINT32 = 0xffffffff;
const MIN_END_RECORD_SIZE = 22;

export interface ZipArchiveEntry {
  path: string;
  bytes: Uint8Array;
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

export function createZipArchive(entries: ZipArchiveEntry[]) {
  if (entries.length > MAX_UINT16) throw makeArchiveError('عدد الملفات يتجاوز الحد المدعوم.');

  const encoder = new TextEncoder();
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  const paths = new Set<string>();
  let localOffset = 0;

  for (const entry of entries) {
    validatePath(entry.path);
    if (paths.has(entry.path)) throw makeArchiveError('يحتوي الأرشيف على مسارات ملفات مكررة.');
    paths.add(entry.path);

    const nameBytes = encoder.encode(entry.path);
    if (nameBytes.length > MAX_UINT16) throw makeArchiveError('اسم ملف داخل الأرشيف أطول من الحد المدعوم.');
    if (entry.bytes.length > MAX_UINT32) throw makeArchiveError('حجم ملف داخل الأرشيف يتجاوز الحد المدعوم.');

    const checksum = computeCrc32(entry.bytes);
    const localHeader = new Uint8Array(30 + nameBytes.length);
    writeUint32(localHeader, 0, LOCAL_FILE_HEADER_SIGNATURE);
    writeUint16(localHeader, 4, 20);
    writeUint16(localHeader, 6, UTF8_FLAG);
    writeUint16(localHeader, 8, STORED_METHOD);
    writeUint16(localHeader, 10, 0);
    writeUint16(localHeader, 12, FIXED_DOS_DATE);
    writeUint32(localHeader, 14, checksum);
    writeUint32(localHeader, 18, entry.bytes.length);
    writeUint32(localHeader, 22, entry.bytes.length);
    writeUint16(localHeader, 26, nameBytes.length);
    writeUint16(localHeader, 28, 0);
    localHeader.set(nameBytes, 30);

    const centralHeader = new Uint8Array(46 + nameBytes.length);
    writeUint32(centralHeader, 0, CENTRAL_DIRECTORY_SIGNATURE);
    writeUint16(centralHeader, 4, 20);
    writeUint16(centralHeader, 6, 20);
    writeUint16(centralHeader, 8, UTF8_FLAG);
    writeUint16(centralHeader, 10, STORED_METHOD);
    writeUint16(centralHeader, 12, 0);
    writeUint16(centralHeader, 14, FIXED_DOS_DATE);
    writeUint32(centralHeader, 16, checksum);
    writeUint32(centralHeader, 20, entry.bytes.length);
    writeUint32(centralHeader, 24, entry.bytes.length);
    writeUint16(centralHeader, 28, nameBytes.length);
    writeUint16(centralHeader, 30, 0);
    writeUint16(centralHeader, 32, 0);
    writeUint16(centralHeader, 34, 0);
    writeUint16(centralHeader, 36, 0);
    writeUint32(centralHeader, 38, 0);
    writeUint32(centralHeader, 42, localOffset);
    centralHeader.set(nameBytes, 46);

    localParts.push(localHeader, entry.bytes);
    centralParts.push(centralHeader);
    localOffset += localHeader.length + entry.bytes.length;
  }

  const centralDirectory = concatenate(centralParts);
  const endRecord = new Uint8Array(MIN_END_RECORD_SIZE);
  writeUint32(endRecord, 0, END_OF_CENTRAL_DIRECTORY_SIGNATURE);
  writeUint16(endRecord, 4, 0);
  writeUint16(endRecord, 6, 0);
  writeUint16(endRecord, 8, entries.length);
  writeUint16(endRecord, 10, entries.length);
  writeUint32(endRecord, 12, centralDirectory.length);
  writeUint32(endRecord, 16, localOffset);
  writeUint16(endRecord, 20, 0);

  return concatenate([...localParts, centralDirectory, endRecord]);
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

export function readZipArchive(source: Uint8Array) {
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

  const decoder = new TextDecoder('utf-8', { fatal: true });
  const files = new Map<string, Uint8Array>();
  let centralCursor = centralOffset;

  for (let index = 0; index < entryCount; index += 1) {
    requireRange(source, centralCursor, 46);
    if (readUint32(source, centralCursor) !== CENTRAL_DIRECTORY_SIGNATURE) {
      throw makeArchiveError('فهرس الملفات يحتوي على توقيع غير صالح.');
    }

    const flags = readUint16(source, centralCursor + 8);
    const method = readUint16(source, centralCursor + 10);
    const checksum = readUint32(source, centralCursor + 16);
    const compressedSize = readUint32(source, centralCursor + 20);
    const uncompressedSize = readUint32(source, centralCursor + 24);
    const nameLength = readUint16(source, centralCursor + 28);
    const extraLength = readUint16(source, centralCursor + 30);
    const commentLength = readUint16(source, centralCursor + 32);
    const diskStart = readUint16(source, centralCursor + 34);
    const localOffset = readUint32(source, centralCursor + 42);

    if ((flags & UTF8_FLAG) === 0 || (flags & 0x0009) !== 0) throw makeArchiveError('خصائص ملف داخل الأرشيف غير مدعومة.');
    if (method !== STORED_METHOD || compressedSize !== uncompressedSize) throw makeArchiveError('ضغط ملفات ZIP غير مدعوم في هذا الإصدار.');
    if (diskStart !== 0) throw makeArchiveError('الأرشيف متعدد الأجزاء غير مدعوم.');

    requireRange(source, centralCursor + 46, nameLength + extraLength + commentLength);
    const centralNameBytes = source.slice(centralCursor + 46, centralCursor + 46 + nameLength);
    let path: string;
    try {
      path = decoder.decode(centralNameBytes);
    } catch {
      throw makeArchiveError('اسم ملف داخل الأرشيف ليس UTF-8 صالحًا.');
    }
    validatePath(path);
    if (files.has(path)) throw makeArchiveError('يحتوي الأرشيف على مسارات ملفات مكررة.');

    requireRange(source, localOffset, 30);
    if (readUint32(source, localOffset) !== LOCAL_FILE_HEADER_SIGNATURE) throw makeArchiveError('ترويسة ملف داخل الأرشيف غير صالحة.');
    if (readUint16(source, localOffset + 6) !== flags || readUint16(source, localOffset + 8) !== method) {
      throw makeArchiveError('ترويسة الملف لا تطابق فهرس الأرشيف.');
    }
    if (readUint32(source, localOffset + 14) !== checksum
      || readUint32(source, localOffset + 18) !== compressedSize
      || readUint32(source, localOffset + 22) !== uncompressedSize) {
      throw makeArchiveError('بيانات حجم الملف أو بصمته لا تطابق فهرس الأرشيف.');
    }

    const localNameLength = readUint16(source, localOffset + 26);
    const localExtraLength = readUint16(source, localOffset + 28);
    requireRange(source, localOffset + 30, localNameLength + localExtraLength + compressedSize);
    const localNameBytes = source.slice(localOffset + 30, localOffset + 30 + localNameLength);
    if (!equalBytes(localNameBytes, centralNameBytes)) throw makeArchiveError('اسم الملف لا يطابق فهرس الأرشيف.');

    const payloadOffset = localOffset + 30 + localNameLength + localExtraLength;
    const payload = source.slice(payloadOffset, payloadOffset + compressedSize);
    if (computeCrc32(payload) !== checksum) throw makeArchiveError('فشل التحقق من سلامة ملف داخل الأرشيف.');
    files.set(path, payload);

    centralCursor += 46 + nameLength + extraLength + commentLength;
  }

  if (centralCursor !== centralOffset + centralSize) throw makeArchiveError('حجم فهرس الملفات غير متطابق.');
  return files;
}

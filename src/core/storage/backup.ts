const TERRANEX_PREFIX = 'terranex.';
export const TERRANEX_BACKUP_SCHEMA_VERSION = 1;

export interface TerranexBackup {
  schema_version: number;
  exported_at: string;
  records: Record<string, string>;
}

export interface BackupSummary {
  keys: number;
  records: number;
  collections: Record<string, number>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

export function readTerranexRecords(storage: Storage = localStorage): Record<string, string> {
  const records: Record<string, string> = {};
  for (let index = 0; index < storage.length; index += 1) {
    const key = storage.key(index);
    if (!key || !key.startsWith(TERRANEX_PREFIX)) continue;
    const value = storage.getItem(key);
    if (value !== null) records[key] = value;
  }
  return records;
}

export function summarizeTerranexRecords(records: Record<string, string>): BackupSummary {
  const collections: Record<string, number> = {};
  let recordCount = 0;

  for (const [key, raw] of Object.entries(records)) {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (Array.isArray(parsed)) {
        collections[key] = parsed.length;
        recordCount += parsed.length;
      }
    } catch {
      // Preferences such as locale may intentionally be stored as plain strings.
    }
  }

  return { keys: Object.keys(records).length, records: recordCount, collections };
}

export function createTerranexBackup(storage: Storage = localStorage): TerranexBackup {
  return {
    schema_version: TERRANEX_BACKUP_SCHEMA_VERSION,
    exported_at: new Date().toISOString(),
    records: readTerranexRecords(storage),
  };
}

export function parseTerranexBackup(text: string): TerranexBackup {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text) as unknown;
  } catch {
    throw new Error('ملف النسخة الاحتياطية ليس JSON صالحًا.');
  }

  if (!isRecord(parsed)) throw new Error('صيغة النسخة الاحتياطية غير صالحة.');
  if (parsed.schema_version !== TERRANEX_BACKUP_SCHEMA_VERSION) {
    throw new Error('إصدار النسخة الاحتياطية غير متوافق مع هذا الإصدار من Terranex.');
  }
  if (typeof parsed.exported_at !== 'string' || !isRecord(parsed.records)) {
    throw new Error('بيانات النسخة الاحتياطية ناقصة أو غير صالحة.');
  }

  const records: Record<string, string> = {};
  for (const [key, value] of Object.entries(parsed.records)) {
    if (!key.startsWith(TERRANEX_PREFIX) || typeof value !== 'string') {
      throw new Error('تحتوي النسخة الاحتياطية على بيانات غير مسموح باستعادتها.');
    }
    records[key] = value;
  }

  return { schema_version: TERRANEX_BACKUP_SCHEMA_VERSION, exported_at: parsed.exported_at, records };
}

function replaceTerranexRecords(records: Record<string, string>, storage: Storage) {
  for (const key of Object.keys(readTerranexRecords(storage))) storage.removeItem(key);
  for (const [key, value] of Object.entries(records)) storage.setItem(key, value);
}

export function restoreTerranexBackup(backup: TerranexBackup, storage: Storage = localStorage) {
  const validated = parseTerranexBackup(JSON.stringify(backup));
  const previous = readTerranexRecords(storage);
  try {
    replaceTerranexRecords(validated.records, storage);
  } catch (error) {
    try {
      replaceTerranexRecords(previous, storage);
    } catch {
      // Preserve the original restore error when rollback is also unavailable.
    }
    throw error;
  }
  return previous;
}

export function clearTerranexData(storage: Storage = localStorage) {
  const previous = readTerranexRecords(storage);
  for (const key of Object.keys(previous)) storage.removeItem(key);
  return previous;
}

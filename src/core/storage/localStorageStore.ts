/**
 * Generic localStorage store factory.
 * Provides a typed get/set/subscribe interface over localStorage.
 */

export type Listener<T> = (value: T) => void;

export interface LocalStorageStore<T> {
  get(): T;
  set(value: T): void;
  update(fn: (current: T) => T): void;
  subscribe(listener: Listener<T>): () => void;
  reset(): void;
}

export class LocalStorageError extends Error {
  constructor(message: string, public readonly key: string, public readonly operation: 'read' | 'write' | 'remove') {
    super(message);
    this.name = 'LocalStorageError';
  }
}

export interface VersionedMigration<T> {
  version: number;
  migrate(value: unknown): T;
}

export function safeJsonParse(raw: string | null, key: string): unknown {
  if (raw === null) return null;
  try {
    return JSON.parse(raw);
  } catch {
    throw new LocalStorageError(`تعذر قراءة البيانات المحلية للمفتاح ${key}.`, key, 'read');
  }
}

export function runVersionedMigrations<T>(
  raw: unknown,
  migrations: VersionedMigration<T>[],
  fallback: T,
): T {
  if (migrations.length === 0) return fallback;

  const sorted = [...migrations].sort((a, b) => a.version - b.version);
  const currentVersion = raw && typeof raw === 'object' && !Array.isArray(raw) && typeof (raw as { version?: unknown }).version === 'number'
    ? (raw as { version: number }).version
    : 0;

  let next: unknown = raw;
  for (const migration of sorted) {
    if (migration.version > currentVersion) {
      next = migration.migrate(next);
    }
  }
  return next as T;
}

export function createLocalStorageStore<T>(
  key: string,
  defaultValue: T,
  parse: (raw: unknown) => T = (v) => v as T,
): LocalStorageStore<T> {
  const listeners = new Set<Listener<T>>();

  function read(): T {
    if (typeof localStorage === 'undefined') return defaultValue;
    try {
      const raw = localStorage.getItem(key);
      if (raw === null) return defaultValue;
      return parse(safeJsonParse(raw, key));
    } catch (error) {
      if (error instanceof LocalStorageError) {
        console.error(error.message);
      } else {
        console.error(`تعذر تحليل البيانات المحلية للمفتاح ${key}.`);
      }
      return defaultValue;
    }
  }

  function write(value: T) {
    if (typeof localStorage === 'undefined') return;
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
      console.error(`تعذر حفظ البيانات المحلية للمفتاح ${key}. تأكد من مساحة التخزين وإعدادات المتصفح.`);
      throw new LocalStorageError(`تعذر حفظ البيانات المحلية للمفتاح ${key}.`, key, 'write');
    }
    listeners.forEach((l) => l(value));
  }

  function notifyCurrentValue() {
    const value = read();
    listeners.forEach((listener) => listener(value));
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('storage', (event) => {
      if (event.storageArea === localStorage && event.key === key) {
        notifyCurrentValue();
      }
    });
  }

  return {
    get: read,
    set: write,
    update(fn) {
      write(fn(read()));
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    reset() {
      if (typeof localStorage === 'undefined') return;
      try {
        localStorage.removeItem(key);
      } catch {
        console.error(`تعذر حذف البيانات المحلية للمفتاح ${key}.`);
        throw new LocalStorageError(`تعذر حذف البيانات المحلية للمفتاح ${key}.`, key, 'remove');
      }
      listeners.forEach((l) => l(defaultValue));
    },
  };
}

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

export function createLocalStorageStore<T>(
  key: string,
  defaultValue: T,
  parse: (raw: unknown) => T = (v) => v as T,
): LocalStorageStore<T> {
  const listeners = new Set<Listener<T>>();

  function read(): T {
    try {
      const raw = localStorage.getItem(key);
      if (raw === null) return defaultValue;
      return parse(JSON.parse(raw));
    } catch {
      return defaultValue;
    }
  }

  function write(value: T) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // storage quota exceeded — silent fail
    }
    listeners.forEach((l) => l(value));
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
      localStorage.removeItem(key);
      listeners.forEach((l) => l(defaultValue));
    },
  };
}

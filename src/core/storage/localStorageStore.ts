import { LocalStorageError } from './storageErrors';

export type Listener<T> = (value: T) => void;

export interface LocalStorageStore<T> {
  get(): T;
  set(value: T): void;
  update(fn: (current: T) => T): void;
  subscribe(listener: Listener<T>): () => void;
  reset(): void;
}

function canUseLocalStorage() {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
}

export function readJsonValue(key: string): unknown {
  if (!canUseLocalStorage()) return null;
  try {
    const raw = window.localStorage.getItem(key);
    if (raw === null) return null;
    return JSON.parse(raw);
  } catch (error) {
    throw new LocalStorageError('read', key, error);
  }
}

export function writeJsonValue(key: string, value: unknown) {
  if (!canUseLocalStorage()) return;
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch (error) {
    throw new LocalStorageError('write', key, error);
  }
}

export function removeJsonValue(key: string) {
  if (!canUseLocalStorage()) return;
  try {
    window.localStorage.removeItem(key);
  } catch (error) {
    throw new LocalStorageError('remove', key, error);
  }
}

export function createLocalStorageStore<T>(
  key: string,
  defaultValue: T,
  parse: (raw: unknown) => T = (v) => v as T,
): LocalStorageStore<T> {
  const listeners = new Set<Listener<T>>();

  function notify(value: T) {
    listeners.forEach((listener) => listener(value));
  }

  function read(): T {
    const raw = readJsonValue(key);
    if (raw === null) return defaultValue;
    return parse(raw);
  }

  function write(value: T) {
    writeJsonValue(key, value);
    notify(value);
  }

  if (canUseLocalStorage()) {
    window.addEventListener('storage', (event) => {
      if (event.key !== key) return;
      notify(read());
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
      listener(read());
      return () => listeners.delete(listener);
    },
    reset() {
      removeJsonValue(key);
      notify(defaultValue);
    },
  };
}

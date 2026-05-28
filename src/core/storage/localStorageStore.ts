type Listener = () => void;

export interface LocalStorageStore<T> {
  getSnapshot: () => T;
  setSnapshot: (value: T) => void;
  clear: () => void;
  subscribe: (listener: Listener) => () => void;
}

function canUseLocalStorage() {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
}

export function createLocalStorageStore<T>(
  key: string,
  fallbackValue: T,
  parseValue: (value: unknown) => T = (value) => value as T,
): LocalStorageStore<T> {
  const listeners = new Set<Listener>();
  let cachedRaw: string | null = null;
  let cachedValue = fallbackValue;

  function notify() {
    listeners.forEach((listener) => listener());
  }

  function read(): T {
    if (!canUseLocalStorage()) return fallbackValue;

    const raw = window.localStorage.getItem(key);
    if (raw === cachedRaw) return cachedValue;

    cachedRaw = raw;
    if (!raw) {
      cachedValue = fallbackValue;
      return cachedValue;
    }

    try {
      cachedValue = parseValue(JSON.parse(raw));
      return cachedValue;
    } catch {
      cachedValue = fallbackValue;
      return fallbackValue;
    }
  }

  return {
    getSnapshot: read,
    setSnapshot(value) {
      if (!canUseLocalStorage()) return;
      cachedValue = value;
      cachedRaw = JSON.stringify(value);
      window.localStorage.setItem(key, cachedRaw);
      notify();
    },
    clear() {
      if (!canUseLocalStorage()) return;
      cachedRaw = null;
      cachedValue = fallbackValue;
      window.localStorage.removeItem(key);
      notify();
    },
    subscribe(listener) {
      listeners.add(listener);

      function handleStorage(event: StorageEvent) {
        if (event.key === key) listener();
      }

      if (typeof window !== 'undefined') {
        window.addEventListener('storage', handleStorage);
      }

      return () => {
        listeners.delete(listener);
        if (typeof window !== 'undefined') {
          window.removeEventListener('storage', handleStorage);
        }
      };
    },
  };
}

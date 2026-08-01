/**
 * Minimal in-memory IndexedDB double for `core/storage/indexedDbFileStore`.
 *
 * Only the surface that module touches is implemented: `indexedDB.open` with an
 * upgrade hook, a single-store transaction with `oncomplete`/`onerror`, and the
 * `put`/`get`/`getAll`/`clear`/`delete` requests. Requests settle on the
 * microtask queue and the transaction completes once no request is pending, so
 * the store's `await run(...)` then `await completed` ordering is exercised the
 * same way a browser would.
 */

class FakeRequest {
  constructor() {
    this.onsuccess = null;
    this.onerror = null;
    this.result = undefined;
    this.error = null;
  }
}

class FakeObjectStore {
  constructor(records, transaction) {
    this.records = records;
    this.transaction = transaction;
  }

  #run(compute) {
    const request = new FakeRequest();
    this.transaction.track();
    queueMicrotask(() => {
      try {
        request.result = compute();
        request.onsuccess?.();
      } catch (error) {
        request.error = error;
        this.transaction.fail(error);
        request.onerror?.();
      } finally {
        this.transaction.settle();
      }
    });
    return request;
  }

  put(record) {
    return this.#run(() => {
      if (this.transaction.mode !== 'readwrite') throw new Error('read-only transaction');
      this.records.set(record.id, record);
      return record.id;
    });
  }

  get(id) {
    return this.#run(() => this.records.get(id));
  }

  getAll() {
    return this.#run(() => Array.from(this.records.values()));
  }

  clear() {
    return this.#run(() => { this.records.clear(); });
  }

  delete(id) {
    return this.#run(() => { this.records.delete(id); });
  }
}

class FakeTransaction {
  constructor(records, mode) {
    this.mode = mode;
    this.error = null;
    this.oncomplete = null;
    this.onerror = null;
    this.onabort = null;
    this.pending = 0;
    this.finished = false;
    this.store = new FakeObjectStore(records, this);
    setTimeout(() => this.#maybeFinish(), 0);
  }

  objectStore() {
    return this.store;
  }

  track() {
    this.pending += 1;
  }

  settle() {
    this.pending -= 1;
    setTimeout(() => this.#maybeFinish(), 0);
  }

  fail(error) {
    this.error = error;
  }

  #maybeFinish() {
    if (this.finished || this.pending > 0) return;
    this.finished = true;
    if (this.error) this.onerror?.();
    else this.oncomplete?.();
  }
}

class FakeDatabase {
  constructor(storeNames, records) {
    this.objectStoreNames = {
      contains: (name) => storeNames.has(name),
    };
    this.storeNames = storeNames;
    this.records = records;
    this.closed = false;
  }

  createObjectStore(name) {
    this.storeNames.add(name);
  }

  transaction(_name, mode = 'readonly') {
    return new FakeTransaction(this.records, mode);
  }

  close() {
    this.closed = true;
  }
}

/**
 * Installs a fake `indexedDB` global and returns a handle for inspecting and
 * restoring it. `failMode` forces `open` to emit `onerror` or `onblocked`.
 */
function installFakeIndexedDb({ failMode } = {}) {
  const records = new Map();
  const storeNames = new Set();
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'indexedDB');

  globalThis.indexedDB = {
    open() {
      const request = new FakeRequest();
      queueMicrotask(() => {
        if (failMode === 'error') {
          request.error = new Error('open failed');
          request.onerror?.();
          return;
        }
        if (failMode === 'blocked') {
          request.onblocked?.();
          return;
        }
        request.result = new FakeDatabase(storeNames, records);
        if (storeNames.size === 0) request.onupgradeneeded?.();
        request.onsuccess?.();
      });
      return request;
    },
  };

  return {
    records,
    storeNames,
    restore() {
      if (previous) Object.defineProperty(globalThis, 'indexedDB', previous);
      else delete globalThis.indexedDB;
    },
  };
}

module.exports = { installFakeIndexedDb };

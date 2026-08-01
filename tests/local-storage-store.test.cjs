const test = require('node:test');
const assert = require('node:assert/strict');

const {
  LocalStorageError,
  createLocalStorageStore,
  runVersionedMigrations,
  safeJsonParse,
} = require('./.compiled/core/storage/localStorageStore.js');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  get length() { return this.values.size; }
  key(index) { return Array.from(this.values.keys())[index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

function captureThrow(run) {
  try {
    run();
  } catch (error) {
    return error;
  }
  throw new Error('expected the call to throw');
}

function withStorage(storage, run) {
  const previousStorage = global.localStorage;
  const previousError = console.error;
  global.localStorage = storage;
  console.error = () => {};
  try {
    return run();
  } finally {
    console.error = previousError;
    if (previousStorage === undefined) delete global.localStorage;
    else global.localStorage = previousStorage;
  }
}

test('safeJsonParse returns null for missing keys and raises a read error for corrupt payloads', () => {
  assert.equal(safeJsonParse(null, 'terranex.demo.v1'), null);
  assert.deepEqual(safeJsonParse('{"a":1}', 'terranex.demo.v1'), { a: 1 });

  const error = captureThrow(() => safeJsonParse('{not-json', 'terranex.demo.v1'));
  assert.ok(error instanceof LocalStorageError);
  assert.equal(error.key, 'terranex.demo.v1');
  assert.equal(error.operation, 'read');
  assert.equal(error.name, 'LocalStorageError');
});

test('runVersionedMigrations applies only pending migrations in version order', () => {
  const fallback = { version: 0, items: [] };
  assert.deepEqual(runVersionedMigrations({ version: 3 }, [], fallback), fallback);

  const applied = [];
  const migrations = [
    { version: 3, migrate: (value) => { applied.push(3); return { ...value, version: 3 }; } },
    { version: 1, migrate: (value) => { applied.push(1); return { ...value, version: 1 }; } },
    { version: 2, migrate: (value) => { applied.push(2); return { ...value, version: 2 }; } },
  ];

  assert.deepEqual(runVersionedMigrations({ version: 1, items: ['a'] }, migrations, fallback), {
    version: 3,
    items: ['a'],
  });
  assert.deepEqual(applied, [2, 3]);
});

test('runVersionedMigrations treats unversioned payloads as version zero', () => {
  const migrations = [{ version: 1, migrate: () => ({ version: 1, migrated: true }) }];
  assert.deepEqual(runVersionedMigrations(['legacy'], migrations, { version: 0 }), { version: 1, migrated: true });
  assert.deepEqual(runVersionedMigrations(null, migrations, { version: 0 }), { version: 1, migrated: true });
});

test('store reads the default value until a value is written', () => {
  withStorage(new MemoryStorage(), () => {
    const store = createLocalStorageStore('terranex.demo.v1', { count: 0 });
    assert.deepEqual(store.get(), { count: 0 });
    store.set({ count: 2 });
    assert.deepEqual(store.get(), { count: 2 });
    assert.equal(global.localStorage.getItem('terranex.demo.v1'), '{"count":2}');
  });
});

test('store update derives the next value from the current one', () => {
  withStorage(new MemoryStorage(), () => {
    const store = createLocalStorageStore('terranex.demo.v1', { count: 1 });
    store.update((current) => ({ count: current.count + 4 }));
    assert.deepEqual(store.get(), { count: 5 });
  });
});

test('store notifies subscribers on write and reset, and stops after unsubscribe', () => {
  withStorage(new MemoryStorage(), () => {
    const store = createLocalStorageStore('terranex.demo.v1', 'default');
    const seen = [];
    const unsubscribe = store.subscribe((value) => seen.push(value));

    store.set('first');
    store.update(() => 'second');
    store.reset();
    unsubscribe();
    store.set('after-unsubscribe');

    assert.deepEqual(seen, ['first', 'second', 'default']);
    assert.equal(store.get(), 'after-unsubscribe');
  });
});

test('store applies the parse hook and falls back to the default on corrupt data', () => {
  const storage = new MemoryStorage();
  withStorage(storage, () => {
    const parse = (raw) => (Array.isArray(raw) ? raw.map(String) : []);
    const store = createLocalStorageStore('terranex.demo.v1', ['fallback'], parse);

    storage.setItem('terranex.demo.v1', JSON.stringify([1, 2]));
    assert.deepEqual(store.get(), ['1', '2']);

    storage.setItem('terranex.demo.v1', '{broken');
    assert.deepEqual(store.get(), ['fallback']);
  });
});

test('store surfaces write and remove failures as LocalStorageError', () => {
  const storage = new MemoryStorage();
  storage.setItem = () => { throw new Error('quota exceeded'); };
  storage.removeItem = () => { throw new Error('access denied'); };

  withStorage(storage, () => {
    const store = createLocalStorageStore('terranex.demo.v1', 0);
    const writeError = captureThrow(() => store.set(1));
    assert.ok(writeError instanceof LocalStorageError);
    assert.equal(writeError.operation, 'write');

    const removeError = captureThrow(() => store.reset());
    assert.ok(removeError instanceof LocalStorageError);
    assert.equal(removeError.operation, 'remove');
  });
});

test('store degrades to the default value when localStorage is unavailable', () => {
  const previous = global.localStorage;
  delete global.localStorage;
  try {
    const store = createLocalStorageStore('terranex.demo.v1', 'default');
    assert.equal(store.get(), 'default');
    store.set('ignored');
    store.reset();
    assert.equal(store.get(), 'default');
  } finally {
    if (previous === undefined) delete global.localStorage;
    else global.localStorage = previous;
  }
});

test('store re-reads and notifies subscribers on cross-tab storage events', () => {
  const storage = new MemoryStorage();
  const handlers = [];
  const previousWindow = global.window;
  global.window = { addEventListener: (type, handler) => { if (type === 'storage') handlers.push(handler); } };

  try {
    withStorage(storage, () => {
      const store = createLocalStorageStore('terranex.demo.v1', 'default');
      const seen = [];
      store.subscribe((value) => seen.push(value));

      storage.setItem('terranex.demo.v1', JSON.stringify('from-other-tab'));
      handlers.forEach((handler) => handler({ storageArea: storage, key: 'terranex.demo.v1' }));
      handlers.forEach((handler) => handler({ storageArea: storage, key: 'terranex.other.v1' }));
      handlers.forEach((handler) => handler({ storageArea: new MemoryStorage(), key: 'terranex.demo.v1' }));

      assert.deepEqual(seen, ['from-other-tab']);
    });
  } finally {
    if (previousWindow === undefined) delete global.window;
    else global.window = previousWindow;
  }
});

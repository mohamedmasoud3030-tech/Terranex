const test = require('node:test');
const assert = require('node:assert/strict');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  get length() { return this.values.size; }
  key(index) { return Array.from(this.values.keys())[index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

const {
  clearTerranexData,
  createTerranexBackup,
  parseTerranexBackup,
  readTerranexRecords,
  restoreTerranexBackup,
  summarizeTerranexRecords,
} = require('./.compiled/core/storage/backup.js');

function seed(storage) {
  storage.setItem('terranex.projects.v1', JSON.stringify([{ id: 'project-1' }]));
  storage.setItem('terranex.transactions.v2', JSON.stringify([{ id: 'tx-1' }, { id: 'tx-2' }]));
  storage.setItem('terranex.locale.v1', 'ar');
  storage.setItem('unrelated.key', 'keep-me');
}

test('backup exports only Terranex-owned keys and summarizes collection counts', () => {
  const storage = new MemoryStorage();
  seed(storage);
  const backup = createTerranexBackup(storage);
  assert.equal(backup.schema_version, 1);
  assert.deepEqual(Object.keys(backup.records).sort(), [
    'terranex.locale.v1',
    'terranex.projects.v1',
    'terranex.transactions.v2',
  ]);
  assert.deepEqual(summarizeTerranexRecords(backup.records), {
    keys: 3,
    records: 3,
    collections: {
      'terranex.projects.v1': 1,
      'terranex.transactions.v2': 2,
    },
  });
});

test('backup restores a valid round trip while preserving unrelated keys', () => {
  const storage = new MemoryStorage();
  seed(storage);
  const backup = createTerranexBackup(storage);
  storage.setItem('terranex.projects.v1', JSON.stringify([{ id: 'changed' }]));
  storage.setItem('terranex.extra.v1', JSON.stringify([{ id: 'remove-me' }]));
  restoreTerranexBackup(backup, storage);
  assert.deepEqual(readTerranexRecords(storage), backup.records);
  assert.equal(storage.getItem('unrelated.key'), 'keep-me');
});

test('backup parser rejects malformed JSON and incompatible versions', () => {
  assert.throws(() => parseTerranexBackup('{not-json'), /JSON/);
  assert.throws(() => parseTerranexBackup(JSON.stringify({ schema_version: 2, exported_at: '2026-01-01', records: {} })), /غير متوافق/);
});

test('failed parsing leaves current storage unchanged', () => {
  const storage = new MemoryStorage();
  seed(storage);
  const before = readTerranexRecords(storage);
  assert.throws(() => parseTerranexBackup(JSON.stringify({ schema_version: 1, exported_at: '2026-01-01', records: { 'unsafe.key': 'value' } })));
  assert.deepEqual(readTerranexRecords(storage), before);
});

test('clear removes only Terranex-owned keys', () => {
  const storage = new MemoryStorage();
  seed(storage);
  const previous = clearTerranexData(storage);
  assert.equal(Object.keys(previous).length, 3);
  assert.deepEqual(readTerranexRecords(storage), {});
  assert.equal(storage.getItem('unrelated.key'), 'keep-me');
});

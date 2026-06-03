const test = require('node:test');
const assert = require('node:assert/strict');

const {
  clearTerranexArchiveData,
  createTerranexArchive,
  parseTerranexArchive,
  restoreTerranexArchive,
} = require('./.compiled/core/storage/archiveBackup.js');
const { readTerranexRecords } = require('./.compiled/core/storage/backup.js');
const { createZipArchive, readZipArchive } = require('./.compiled/core/storage/zipArchive.js');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  get length() { return this.values.size; }
  key(index) { return Array.from(this.values.keys())[index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

class MemoryDocumentFileRepository {
  constructor(files = []) {
    this.files = files.slice();
    this.failNextReplace = false;
    this.failNextClear = false;
  }
  async list() { return this.files.slice(); }
  async replace(files) {
    if (this.failNextReplace) {
      this.failNextReplace = false;
      throw new Error('replace failed');
    }
    this.files = files.slice();
  }
  async clear() {
    if (this.failNextClear) {
      this.failNextClear = false;
      throw new Error('clear failed');
    }
    this.files = [];
  }
}

function makeStoredFile(id, contents = 'invoice-pdf') {
  const blob = new Blob([contents], { type: 'application/pdf' });
  return {
    id,
    document_id: id,
    file_name: `${id}.pdf`,
    original_file_name: 'invoice.pdf',
    mime_type: 'application/pdf',
    size_bytes: blob.size,
    created_at: '2026-06-03T00:00:00.000Z',
    updated_at: '2026-06-03T00:00:00.000Z',
    sha256: `sha-${id}`,
    storage_mode: 'indexeddb',
    version: 1,
    archived: false,
    blob,
  };
}

function seedWorkspace(storage, file) {
  storage.setItem('terranex.projects.v1', JSON.stringify([{ id: 'project-1' }]));
  storage.setItem('terranex.documents.v1', JSON.stringify([{
    id: file.document_id,
    project_id: 'project-1',
    type: 'invoice',
    title_ar: 'فاتورة مشتريات',
    file_url: `indexeddb://document-files/${file.document_id}`,
    file_name: file.file_name,
    file_mime_type: file.mime_type,
    file_size_bytes: file.size_bytes,
    file_sha256: file.sha256,
    created_at: '2026-06-03T00:00:00.000Z',
  }]));
  storage.setItem('unrelated.key', 'keep-me');
}

async function readBlobText(file) {
  return new TextDecoder().decode(await file.blob.arrayBuffer());
}

test('complete ZIP archive exports manifest, records, and uploaded files', async () => {
  const storage = new MemoryStorage();
  const file = makeStoredFile('document-1');
  seedWorkspace(storage, file);
  const repository = new MemoryDocumentFileRepository([file]);

  const archive = await createTerranexArchive(storage, repository);
  const entries = readZipArchive(archive.bytes);

  assert.deepEqual([...entries.keys()], [
    'manifest.json',
    'records.json',
    'files/document-1/document-1.pdf',
  ]);
  assert.equal(archive.summary.files, 1);
  assert.equal(archive.summary.total_file_bytes, file.size_bytes);
});

test('complete ZIP archive survives export, clear, restore, and reload-equivalent reads', async () => {
  const storage = new MemoryStorage();
  const file = makeStoredFile('document-1');
  seedWorkspace(storage, file);
  const repository = new MemoryDocumentFileRepository([file]);
  const expectedRecords = readTerranexRecords(storage);

  const parsed = parseTerranexArchive((await createTerranexArchive(storage, repository)).bytes);
  await clearTerranexArchiveData(storage, repository);

  assert.deepEqual(readTerranexRecords(storage), {});
  assert.deepEqual(await repository.list(), []);
  assert.equal(storage.getItem('unrelated.key'), 'keep-me');

  await restoreTerranexArchive(parsed, storage, repository);
  const restoredFiles = await repository.list();
  assert.deepEqual(readTerranexRecords(storage), expectedRecords);
  assert.equal(restoredFiles.length, 1);
  assert.equal(restoredFiles[0].file_name, 'document-1.pdf');
  assert.equal(await readBlobText(restoredFiles[0]), 'invoice-pdf');
  assert.equal(storage.getItem('unrelated.key'), 'keep-me');
});

test('archive parsing rejects a missing uploaded file before replacing current workspace', async () => {
  const storage = new MemoryStorage();
  const file = makeStoredFile('document-1');
  seedWorkspace(storage, file);
  const repository = new MemoryDocumentFileRepository([file]);
  const before = readTerranexRecords(storage);

  const entries = readZipArchive((await createTerranexArchive(storage, repository)).bytes);
  entries.delete('files/document-1/document-1.pdf');
  const damaged = createZipArchive([...entries].map(([path, bytes]) => ({ path, bytes })));

  assert.throws(() => parseTerranexArchive(damaged), /مفقود/);
  assert.deepEqual(readTerranexRecords(storage), before);
  assert.equal((await repository.list()).length, 1);
});

test('failed restore rolls local records and uploaded files back together', async () => {
  const storage = new MemoryStorage();
  const original = makeStoredFile('document-1', 'original');
  seedWorkspace(storage, original);
  const repository = new MemoryDocumentFileRepository([original]);
  const before = readTerranexRecords(storage);

  const replacementStorage = new MemoryStorage();
  const replacement = makeStoredFile('document-2', 'replacement');
  seedWorkspace(replacementStorage, replacement);
  const replacementRepository = new MemoryDocumentFileRepository([replacement]);
  const parsed = parseTerranexArchive((await createTerranexArchive(replacementStorage, replacementRepository)).bytes);

  repository.failNextReplace = true;
  await assert.rejects(() => restoreTerranexArchive(parsed, storage, repository), /replace failed/);
  assert.deepEqual(readTerranexRecords(storage), before);
  assert.equal((await repository.list())[0].id, 'document-1');
});

test('failed clear rolls local records and uploaded files back together', async () => {
  const storage = new MemoryStorage();
  const file = makeStoredFile('document-1');
  seedWorkspace(storage, file);
  const repository = new MemoryDocumentFileRepository([file]);
  const before = readTerranexRecords(storage);

  repository.failNextClear = true;
  await assert.rejects(() => clearTerranexArchiveData(storage, repository), /clear failed/);
  assert.deepEqual(readTerranexRecords(storage), before);
  assert.equal((await repository.list())[0].id, 'document-1');
});

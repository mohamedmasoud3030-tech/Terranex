const test = require('node:test');
const assert = require('node:assert/strict');

const { installFakeIndexedDb } = require('./helpers/fakeIndexedDb.cjs');

const {
  clearDocumentFiles,
  deleteDocumentFile,
  getDocumentFile,
  listDocumentFiles,
  makeLocalDocumentFileUrl,
  readLocalDocumentFileId,
  replaceDocumentFiles,
  restoreDocumentFile,
  saveDocumentFile,
} = require('./.compiled/core/storage/indexedDbFileStore.js');

function pdf(name = 'contract.pdf', bytes = 'contract-bytes') {
  return new File([bytes], name, { type: 'application/pdf' });
}

function storedRecord(id, overrides = {}) {
  const blob = new Blob(['restored-bytes']);
  return {
    id,
    document_id: id,
    file_name: `${id}.pdf`,
    original_file_name: 'contract.pdf',
    mime_type: 'application/pdf',
    size_bytes: blob.size,
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
    storage_mode: 'indexeddb',
    version: 1,
    archived: false,
    blob,
    ...overrides,
  };
}

async function withFakeIndexedDb(run, options) {
  const fake = installFakeIndexedDb(options);
  try {
    return await run(fake);
  } finally {
    fake.restore();
  }
}

test('local document file URLs round trip through encoding', () => {
  assert.equal(makeLocalDocumentFileUrl('doc 1/2'), 'indexeddb://document-files/doc%201%2F2');
  assert.equal(readLocalDocumentFileId(makeLocalDocumentFileUrl('doc 1/2')), 'doc 1/2');
});

test('readLocalDocumentFileId rejects foreign, empty, or malformed URLs', () => {
  assert.equal(readLocalDocumentFileId(undefined), null);
  assert.equal(readLocalDocumentFileId('https://cdn.example.com/doc-1.pdf'), null);
  assert.equal(readLocalDocumentFileId('indexeddb://document-files/'), null);
  assert.equal(readLocalDocumentFileId('indexeddb://document-files/%E0%A4%A'), null);
});

test('saveDocumentFile persists a validated record retrievable by its local URL', async () => {
  await withFakeIndexedDb(async () => {
    const record = await saveDocumentFile(' doc-1 ', pdf());

    assert.equal(record.id, 'doc-1');
    assert.equal(record.document_id, 'doc-1');
    assert.equal(record.file_name, 'doc-1.pdf');
    assert.equal(record.original_file_name, 'contract.pdf');
    assert.equal(record.mime_type, 'application/pdf');
    assert.equal(record.storage_mode, 'indexeddb');
    assert.equal(record.version, 1);
    assert.equal(record.archived, false);
    assert.match(record.sha256, /^[0-9a-f]{64}$/);

    const stored = await getDocumentFile(makeLocalDocumentFileUrl('doc-1'));
    assert.equal(stored.id, 'doc-1');
    assert.equal(await stored.blob.text(), 'contract-bytes');
  });
});

test('saveDocumentFile keeps files without an extension unsuffixed and rejects invalid input', async () => {
  await withFakeIndexedDb(async () => {
    await assert.rejects(() => saveDocumentFile('   ', pdf()), /معرّف المستند مطلوب/);
    await assert.rejects(() => saveDocumentFile('doc-1', new File(['x'], 'archive.zip', { type: 'application/zip' })), /غير مدعوم/);
    await assert.rejects(() => saveDocumentFile('doc-1', new File([], 'empty.pdf', { type: 'application/pdf' })), /فارغ/);
    assert.deepEqual(await listDocumentFiles(), []);
  });
});

test('getDocumentFile returns undefined for unknown ids and non-local URLs', async () => {
  await withFakeIndexedDb(async () => {
    assert.equal(await getDocumentFile('https://cdn.example.com/doc-1.pdf'), undefined);
    assert.equal(await getDocumentFile(makeLocalDocumentFileUrl('missing')), undefined);
  });
});

test('deleteDocumentFile removes the stored file and ignores non-local URLs', async () => {
  await withFakeIndexedDb(async (fake) => {
    await saveDocumentFile('doc-1', pdf());
    await deleteDocumentFile('https://cdn.example.com/doc-1.pdf');
    assert.equal(fake.records.size, 1);

    await deleteDocumentFile(makeLocalDocumentFileUrl('doc-1'));
    assert.equal(await getDocumentFile(makeLocalDocumentFileUrl('doc-1')), undefined);
  });
});

test('replaceDocumentFiles swaps the whole store contents', async () => {
  await withFakeIndexedDb(async () => {
    await saveDocumentFile('doc-old', pdf());
    await replaceDocumentFiles([storedRecord('doc-a'), storedRecord('doc-b')]);

    const ids = (await listDocumentFiles()).map((record) => record.id).sort();
    assert.deepEqual(ids, ['doc-a', 'doc-b']);
  });
});

test('replaceDocumentFiles rejects duplicates and leaves the store untouched', async () => {
  await withFakeIndexedDb(async () => {
    await saveDocumentFile('doc-1', pdf());
    await assert.rejects(() => replaceDocumentFiles([storedRecord('doc-a'), storedRecord('doc-a')]), /مكررة/);

    const ids = (await listDocumentFiles()).map((record) => record.id);
    assert.deepEqual(ids, ['doc-1']);
  });
});

test('restoreDocumentFile validates every field of a restored record', async () => {
  await withFakeIndexedDb(async () => {
    await assert.rejects(() => restoreDocumentFile(storedRecord('doc-1', { document_id: 'other' })), /معرّف ملف المستند المحلي غير صالح/);
    await assert.rejects(() => restoreDocumentFile(storedRecord('doc-1', { file_name: ' ' })), /ناقصة/);
    await assert.rejects(() => restoreDocumentFile(storedRecord('doc-1', { mime_type: '' })), /ناقصة/);
    await assert.rejects(() => restoreDocumentFile(storedRecord('doc-1', { size_bytes: 999 })), /حجم ملف المستند المحلي غير صالح/);
    await assert.rejects(() => restoreDocumentFile(storedRecord('doc-1', { storage_mode: 'supabase' })), /إصدار تخزين/);
    await assert.rejects(() => restoreDocumentFile(storedRecord('doc-1', { version: 0 })), /إصدار تخزين/);

    await restoreDocumentFile(storedRecord('doc-1'));
    assert.equal((await getDocumentFile(makeLocalDocumentFileUrl('doc-1'))).id, 'doc-1');
  });
});

test('clearDocumentFiles empties the store', async () => {
  await withFakeIndexedDb(async () => {
    await saveDocumentFile('doc-1', pdf());
    await saveDocumentFile('doc-2', pdf('invoice.pdf'));
    await clearDocumentFiles();
    assert.deepEqual(await listDocumentFiles(), []);
  });
});

test('storage operations surface a readable error when IndexedDB is unavailable or failing', async () => {
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'indexedDB');
  delete globalThis.indexedDB;
  try {
    await assert.rejects(() => listDocumentFiles(), /لا يدعم حفظ الملفات المحلية/);
  } finally {
    if (previous) Object.defineProperty(globalThis, 'indexedDB', previous);
  }

  await withFakeIndexedDb(async () => {
    await assert.rejects(() => listDocumentFiles(), /تعذر فتح مخزن الملفات المحلي/);
  }, { failMode: 'error' });

  await withFakeIndexedDb(async () => {
    await assert.rejects(() => listDocumentFiles(), /نافذة أخرى تستخدم إصدارًا قديمًا/);
  }, { failMode: 'blocked' });
});

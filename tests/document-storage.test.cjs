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

global.localStorage = new MemoryStorage();
const { documentsStore } = require('./.compiled/features/documents/storage.js');

function input(overrides = {}) {
  return {
    project_id: 'project-1',
    partner_id: 'partner-1',
    type: 'contract',
    title_ar: '  عقد شراكة مشروع المرسى  ',
    notes: '  نسخة معتمدة  ',
    ...overrides,
  };
}

test('document storage requires title and project', () => {
  documentsStore.reset();
  assert.throws(() => documentsStore.create(input({ title_ar: '   ' })), /عنوان المستند/);
  assert.throws(() => documentsStore.create(input({ project_id: undefined })), /ربط المستند بمشروع/);
});

test('document storage trims user-entered metadata and supports partner lookup', () => {
  documentsStore.reset();
  const created = documentsStore.create(input());
  assert.equal(created.title_ar, 'عقد شراكة مشروع المرسى');
  assert.equal(created.notes, 'نسخة معتمدة');
  assert.equal(documentsStore.getByPartner('partner-1')[0].id, created.id);
});

test('document storage rejects partial or invalid local file metadata', () => {
  documentsStore.reset();
  assert.throws(() => documentsStore.create(input({ file_url: 'indexeddb://document-files/doc-1' })), /بيانات الملف المحلي/);
  assert.throws(() => documentsStore.create(input({
    file_url: 'indexeddb://document-files/doc-1',
    file_name: 'contract.pdf',
    file_mime_type: 'application/pdf',
    file_size_bytes: 0,
  })), /حجم الملف المحلي/);
});

test('document storage accepts complete local file metadata and preserves it on updates', () => {
  documentsStore.reset();
  const created = documentsStore.create(input({
    file_url: 'indexeddb://document-files/doc-1',
    file_name: 'contract.pdf',
    file_mime_type: 'application/pdf',
    file_size_bytes: 1024,
    file_sha256: 'abc123',
  }));
  documentsStore.update(created.id, { title_ar: '  عقد محدث  ' });
  const updated = documentsStore.getAll()[0];
  assert.equal(updated.title_ar, 'عقد محدث');
  assert.equal(updated.file_name, 'contract.pdf');
  assert.equal(updated.file_size_bytes, 1024);
  assert.equal(updated.file_sha256, 'abc123');
});

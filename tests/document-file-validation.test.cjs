const test = require('node:test');
const assert = require('node:assert/strict');

const {
  MAX_DOCUMENT_FILE_SIZE_BYTES,
  validateDocumentUpload,
} = require('./.compiled/core/lib/documentFileValidation.js');

function file(overrides = {}) {
  return {
    name: 'partnership-contract.pdf',
    type: 'application/pdf',
    size: 1024,
    ...overrides,
  };
}

test('document upload validation accepts supported contract images and files', () => {
  assert.deepEqual(validateDocumentUpload(file()), {
    extension: '.pdf',
    mime_type: 'application/pdf',
    size_bytes: 1024,
  });
  assert.equal(validateDocumentUpload(file({ name: 'signed-contract.jpg', type: 'image/jpeg' })).extension, '.jpg');
  assert.equal(validateDocumentUpload(file({ name: 'agreement.png', type: 'image/png' })).extension, '.png');
  assert.equal(validateDocumentUpload(file({ name: 'schedule.xlsx', type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })).extension, '.xlsx');
});

test('document upload validation rejects empty, oversized, unsupported, or mismatched files', () => {
  assert.throws(() => validateDocumentUpload(file({ size: 0 })), /فارغ/);
  assert.throws(() => validateDocumentUpload(file({ size: MAX_DOCUMENT_FILE_SIZE_BYTES + 1 })), /10 ميجابايت/);
  assert.throws(() => validateDocumentUpload(file({ name: 'archive.zip', type: 'application/zip' })), /غير مدعوم/);
  assert.throws(() => validateDocumentUpload(file({ name: 'contract.pdf', type: 'image/png' })), /لا يطابق/);
});

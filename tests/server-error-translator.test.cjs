const test = require('node:test');
const assert = require('node:assert/strict');

const { translateServerError } = require('./.compiled/core/lib/serverErrorTranslator.js');

test('translateServerError maps known RPC/PostgREST messages to Arabic', () => {
  assert.equal(
    translateServerError('stock adjustment cannot produce negative quantity or value'),
    'لا يمكن أن ينتج عن التسوية كمية أو قيمة سالبة.',
  );
  assert.equal(translateServerError('transaction not found'), 'المعاملة غير موجودة.');
  assert.equal(translateServerError('only active settlements can be reversed'), 'لا يمكن عكس إلا التسويات النشطة.');
  assert.equal(translateServerError('document not found'), 'المستند غير موجود.');
  assert.equal(translateServerError('obligation not found'), 'الالتزام غير موجود.');
});

test('translateServerError passes Arabic through, handles Error/object shapes, and falls back for unknown input', () => {
  const arabic = 'قيمة المعاملة يجب أن تكون رقماً صالحاً أكبر من صفر.';
  assert.equal(translateServerError(arabic), arabic);
  assert.equal(translateServerError(new Error(arabic)), arabic);

  assert.equal(translateServerError('transaction not found'), 'المعاملة غير موجودة.');
  assert.equal(
    translateServerError({ message: 'only active settlements can be reversed' }),
    'لا يمكن عكس إلا التسويات النشطة.',
  );

  assert.equal(
    translateServerError('some unknown english server message'),
    'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى.',
  );
  assert.equal(
    translateServerError(new Error('some unknown english server message')),
    'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى.',
  );
  assert.equal(translateServerError(''), 'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى.');
  assert.equal(translateServerError(undefined), 'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى.');
});

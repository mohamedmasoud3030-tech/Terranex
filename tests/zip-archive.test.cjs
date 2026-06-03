const test = require('node:test');
const assert = require('node:assert/strict');

const {
  computeCrc32,
  createZipArchive,
  readZipArchive,
} = require('./.compiled/core/storage/zipArchive.js');

const encoder = new TextEncoder();

function bytes(text) {
  return encoder.encode(text);
}

function readText(files, path) {
  return new TextDecoder().decode(files.get(path));
}

test('zip archive round trip preserves utf-8 paths and binary payloads', () => {
  const binary = Uint8Array.from([0, 1, 2, 127, 128, 255]);
  const archive = createZipArchive([
    { path: 'manifest.json', bytes: bytes('{"schema_version":1}') },
    { path: 'files/مستند-1.bin', bytes: binary },
  ]);

  const files = readZipArchive(archive);
  assert.deepEqual([...files.keys()], ['manifest.json', 'files/مستند-1.bin']);
  assert.equal(readText(files, 'manifest.json'), '{"schema_version":1}');
  assert.deepEqual(files.get('files/مستند-1.bin'), binary);
});

test('zip archive output is deterministic and supports empty archives', () => {
  const entries = [{ path: 'records.json', bytes: bytes('{"records":{}}') }];
  assert.deepEqual(createZipArchive(entries), createZipArchive(entries));
  assert.equal(readZipArchive(createZipArchive([])).size, 0);
});

test('crc32 matches the standard reference checksum', () => {
  assert.equal(computeCrc32(bytes('123456789')), 0xcbf43926);
});

test('zip archive rejects unsafe or duplicate paths', () => {
  assert.throws(() => createZipArchive([{ path: '../records.json', bytes: bytes('{}') }]), /غير آمن/);
  assert.throws(() => createZipArchive([{ path: '/records.json', bytes: bytes('{}') }]), /غير مسموح/);
  assert.throws(() => createZipArchive([
    { path: 'records.json', bytes: bytes('{}') },
    { path: 'records.json', bytes: bytes('{}') },
  ]), /مكررة/);
});

test('zip archive rejects corrupted payloads', () => {
  const path = 'records.json';
  const archive = createZipArchive([{ path, bytes: bytes('{"records":{}}') }]);
  const corrupted = archive.slice();
  corrupted[30 + bytes(path).length] ^= 0xff;
  assert.throws(() => readZipArchive(corrupted), /سلامة/);
});

test('zip archive rejects unsupported compression metadata', () => {
  const archive = createZipArchive([{ path: 'records.json', bytes: bytes('{}') }]);
  const centralOffset = archive.length - 22 - (46 + bytes('records.json').length);
  const corrupted = archive.slice();
  corrupted[centralOffset + 10] = 8;
  assert.throws(() => readZipArchive(corrupted), /ضغط/);
});

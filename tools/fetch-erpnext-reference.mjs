#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const REFERENCE_DIR = join(ROOT, 'reference', 'erpnext');
const CACHE_DIR = join(ROOT, '.reference-cache', 'erpnext');
const PATHS_FILE = join(REFERENCE_DIR, 'selected-paths.txt');
const HASHES_FILE = join(REFERENCE_DIR, 'expected-sha256.txt');
const SOURCE_REPOSITORY = 'frappe/erpnext';
const SOURCE_COMMIT = 'e1f6bb70bc2ddffc923ac6430b79d2ecea422a7a';

function sha256(content) {
  return createHash('sha256').update(content).digest('hex');
}

function parseLines(text) {
  return text
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean);
}

function parseExpectedHashes(text) {
  return new Map(parseLines(text).map((line) => {
    const match = line.match(/^([a-f0-9]{64})\s{2}(.+)$/u);
    if (!match) throw new Error(`Invalid SHA-256 contract line: ${line}`);
    return [match[2], match[1]];
  }));
}

async function fetchPinnedFile(path) {
  const url = `https://raw.githubusercontent.com/${SOURCE_REPOSITORY}/${SOURCE_COMMIT}/${path}`;
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok) throw new Error(`Fetch failed (${response.status}) for ${path}`);
  return Buffer.from(await response.arrayBuffer());
}

async function writeAtomic(path, content) {
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.tmp`;
  await writeFile(temporaryPath, content);
  await rename(temporaryPath, path);
}

async function main() {
  const [pathsText, hashesText] = await Promise.all([
    readFile(PATHS_FILE, 'utf8'),
    readFile(HASHES_FILE, 'utf8'),
  ]);
  const paths = parseLines(pathsText);
  const expectedHashes = parseExpectedHashes(hashesText);

  if (paths.length !== expectedHashes.size) {
    throw new Error(`Reference contract mismatch: ${paths.length} paths but ${expectedHashes.size} hashes.`);
  }

  await rm(CACHE_DIR, { recursive: true, force: true });
  await mkdir(CACHE_DIR, { recursive: true });

  for (const path of paths) {
    const expectedHash = expectedHashes.get(path);
    if (!expectedHash) throw new Error(`Missing expected SHA-256 for ${path}`);

    const content = await fetchPinnedFile(path);
    const actualHash = sha256(content);
    if (actualHash !== expectedHash) {
      throw new Error(`SHA-256 mismatch for ${path}: expected ${expectedHash}, received ${actualHash}`);
    }

    await writeAtomic(join(CACHE_DIR, path), content);
    console.log(`Verified: ${path}`);
  }

  const metadata = {
    source_repository: SOURCE_REPOSITORY,
    source_commit: SOURCE_COMMIT,
    fetched_at: new Date().toISOString(),
    file_count: paths.length,
    cache_directory: '.reference-cache/erpnext',
  };
  await writeAtomic(join(CACHE_DIR, 'reference-metadata.json'), `${JSON.stringify(metadata, null, 2)}\n`);
  console.log(`\nReady: ${paths.length} verified ERPNext reference files in .reference-cache/erpnext`);
  console.log('These files are local reading references only. Never import them into src/.');
}

main().catch((error) => {
  console.error(`ERPNext reference fetch failed: ${error.message}`);
  process.exitCode = 1;
});

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const packageJson = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
const workflow = await readFile(new URL('../.github/workflows/quality-gate.yml', import.meta.url), 'utf8');

test('package scripts expose the complete Phase 1 quality gate', () => {
  assert.equal(packageJson.scripts.typecheck, 'tsc -b');
  assert.equal(packageJson.scripts.lint, 'tsc -b --pretty false');
  assert.equal(packageJson.scripts.test, 'node --test tests/*.test.mjs');
  assert.equal(packageJson.scripts.build, 'tsc -b && vite build');
});

test('GitHub Actions runs the same quality-gate commands in order', () => {
  const commands = [...workflow.matchAll(/^\s*run: (npm (?:ci|run \w+))$/gm)].map((match) => match[1]);

  assert.deepEqual(commands, [
    'npm ci',
    'npm run typecheck',
    'npm run lint',
    'npm run test',
    'npm run build',
  ]);
});

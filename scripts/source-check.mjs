import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const roots = ['src'];
const forbidden = [
  ['debugger statement', /\bdebugger\s*;/],
  ['console.log call', /\bconsole\.log\s*\(/],
  ['TypeScript ignore directive', /@ts-ignore/],
  ['merge conflict marker', /^(<{7}|={7}|>{7})/m],
];

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...await walk(path));
    else if (/\.(ts|tsx|js|jsx|mjs|cjs)$/.test(entry.name)) files.push(path);
  }
  return files;
}

const failures = [];
for (const root of roots) {
  for (const file of await walk(root)) {
    const source = await readFile(file, 'utf8');
    for (const [label, pattern] of forbidden) {
      if (pattern.test(source)) failures.push(`${file}: ${label}`);
    }
  }
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log('Source hygiene checks passed.');

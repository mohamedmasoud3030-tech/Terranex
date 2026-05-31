import { readFileSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const root = resolve(import.meta.dirname, '..');
const files = execFileSync('rg', ['--files', 'src', 'tools', '-g', '*.{ts,tsx,js,mjs}'], {
  cwd: root,
  encoding: 'utf8',
}).trim().split('\n').filter(Boolean);

const failures = [];

for (const file of files) {
  const content = readFileSync(resolve(root, file), 'utf8');
  const rel = relative(root, resolve(root, file));
  if (/try\s*\{\s*(?:await\s+)?import\s*\(/s.test(content)) {
    failures.push(`${rel}: imports must not be wrapped in try/catch`);
  }
  if (/\bOMR\b/.test(content)) failures.push(`${rel}: reporting currency must remain EGP`);
  if (rel !== 'tools/lint.mjs' && /seedTerranexDemo|seedDemoData|بيانات تجريبية|demo data/.test(content)) {
    failures.push(`${rel}: production demo seeding reference found`);
  }
  if (rel !== 'tools/lint.mjs' && /financialRecordsStore/.test(content)) failures.push(`${rel}: legacy financial runtime store reference found`);
}

if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log(`lint passed (${files.length} files checked)`);

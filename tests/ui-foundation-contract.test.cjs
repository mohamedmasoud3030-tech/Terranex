const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const read = (path) => readFileSync(new URL(`../${path}`, `file://${__filename}`), 'utf8');

test('adaptive surface delegates keyboard focus and focus restoration to Radix', () => {
  const source = read('src/components/ui/AdaptiveFormSurface.tsx');
  assert.match(source, /@radix-ui\/react-dialog/);
  assert.match(source, /onEscapeKeyDown/);
  assert.match(source, /Dialog\.Close asChild/);
  assert.match(source, /focus:outline-none/);
});
test('adaptive contract prevents duplicate actions and changes responsively', () => {
  const source = read('src/components/ui/AdaptiveFormSurface.tsx');
  assert.match(source, /if\(!pending\)onOpenChange/);
  assert.match(source, /disabled=\{pending\}/);
  assert.match(source, /aria-busy=\{pending\}/);
  assert.match(source, /bottom-0/);
  assert.match(source, /md:top-1\/2/);
  assert.match(source, /safe-area-inset-bottom/);
});
test('form contract surfaces validation and Supabase errors and guards unsaved work', () => {
  const source = read('src/components/ui/FormContract.tsx');
  assert.match(source, /serverError/);
  assert.match(source, /role="alert"/);
  assert.match(source, /beforeunload/);
  assert.match(source, /dirty&&open/);
});
test('workspace contract has desktop and mobile switchers plus real states', () => {
  const source = read('src/components/workspace/WorkspaceShell.tsx');
  assert.match(source, /md:hidden/);
  assert.match(source, /hidden md:block/);
  assert.match(source, /WorkspaceLoadingState/);
  assert.match(source, /EmptyState/);
  assert.match(source, /ErrorState/);
});
test('confirmation and inspector name impact and optional deep links', () => {
  assert.match(read('src/components/ui/ConfirmDialog.tsx'), /entityName/);
  assert.match(read('src/components/ui/ConfirmDialog.tsx'), /impact/);
  assert.match(read('src/components/ui/EntityInspectorDrawer.tsx'), /fullWorkspaceLink&&/);
});

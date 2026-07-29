const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(process.cwd(), 'src/features/intelligence/IntelligenceHub.tsx'),
  'utf8',
);

test('intelligence is one workspace shell with shared filters and no route or tab assembly', () => {
  assert.match(source, /WorkspaceShell/);
  assert.match(source, /ReportFilters/);
  assert.match(source, /useWorkspaceUrlState/);
  assert.doesNotMatch(source, /createRoute|createFileRoute|<Tabs|TabsList|TabsTrigger/);
});

test('report visualization has an accessible table fallback and progressive responsive layout', () => {
  assert.match(source, /Accessible sector performance data/);
  assert.match(source, /<table/);
  assert.match(source, /sm:grid-cols-2/);
  assert.match(source, /xl:grid-cols-/);
});

test('exports and drill-down retain the filtered report and evidence contracts', () => {
  assert.match(source, /buildFilteredReportCsv\(report\)/);
  assert.match(source, /import\('@react-pdf\/renderer'\)/);
  assert.match(source, /transactions=\{report\.filtered\.transactions\}/);
  assert.match(source, /obligations=\{report\.filtered\.obligations\}/);
  assert.match(source, /EntityInspectorDrawer/);
  assert.match(source, /onFinanceDrillDown\?\.\(context\)/);
});

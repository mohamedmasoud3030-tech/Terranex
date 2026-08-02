const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(process.cwd(), relativePath), 'utf8');
}

const navigation = source('src/components/layout/navigation.ts');
const router = source('src/router.tsx');
const dashboard = source('src/features/dashboard/DashboardPage.tsx');
const topBar = source('src/components/layout/TopBar.tsx');

const redirects = [
  ['projects.tsx', '/portfolio', 'projects'],
  ['assets.tsx', '/portfolio', 'assets'],
  ['partners.tsx', '/portfolio', 'partners'],
  ['real-estate.tsx', '/operations', 'real-estate'],
  ['agriculture.tsx', '/operations', 'agriculture'],
  ['livestock.tsx', '/operations', 'livestock'],
  ['events.tsx', '/operations', 'events'],
  ['transactions.tsx', '/finance', 'transactions'],
  ['finance.obligations.tsx', '/finance', 'obligations'],
  ['finance.allocations.tsx', '/finance', 'settlements'],
  ['finance.profitability.tsx', '/intelligence', 'profitability'],
  ['documents.tsx', '/governance', 'documents'],
  ['settings.tsx', '/governance', 'settings'],
];

test('desktop and mobile navigation share exactly eight canonical destinations (banking + invoices added)', () => {
  const destinations = [...navigation.matchAll(/to: '(\/[^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(destinations, [
    '/dashboard',
    '/portfolio',
    '/banking',
    '/operations',
    '/finance',
    '/invoicing',
    '/intelligence',
    '/governance',
  ]);
  assert.match(topBar, /NAV_ITEMS\.map/);
  assert.match(navigation, /pathname\.startsWith\(item\.to\)/);
});

test('router contains all canonical routes and only legacy routes remain as redirect entries', () => {
  for (const routeName of [
    'dashboardRoute',
    'portfolioRoute',
    'portfolioProjectDetailRoute',
    'portfolioPartnerDetailRoute',
    'bankingRoute',
    'operationsRoute',
    'financeTree',
    'invoicingRoute',
    'intelligenceRoute',
    'governanceRoute',
  ]) {
    assert.match(router, new RegExp(routeName));
  }
  assert.doesNotMatch(router, /financeIndexRoute/);
});

test('every legacy entry redirects to its canonical hub while preserving intent', () => {
  for (const [file, destination, intent] of redirects) {
    const routeSource = source(`src/routes/${file}`);
    assert.match(routeSource, /beforeLoad/);
    assert.match(routeSource, new RegExp(destination.replace('/', '\\/')));
    assert.match(routeSource, new RegExp(intent));
  }
  assert.match(source('src/routes/projects.$id.tsx'), /portfolio\/projects\/\$id/);
  assert.match(source('src/routes/partners.$id.tsx'), /portfolio\/partners\/\$id/);
});

test('dashboard is a canonical command center with contextual actions and no old route targets', () => {
  assert.match(dashboard, /create-project/);
  assert.match(dashboard, /workspace: 'obligations'/);
  assert.match(dashboard, /workspace: 'sector'/);
  assert.match(dashboard, /portfolio\/projects\/\$id/);
  assert.doesNotMatch(dashboard, /to: '\/(projects|partners|assets|events|transactions|documents|settings|real-estate|agriculture|livestock)'/);
});

test('hubs use one shared workspace query key and legacy Finance tabs are removed', () => {
  for (const file of [
    'src/features/operations/OperationsHub.tsx',
    'src/features/finance/FinanceHub.tsx',
    'src/features/intelligence/IntelligenceHub.tsx',
    'src/features/governance/GovernanceHub.tsx',
  ]) {
    assert.match(source(file), /parameter: 'workspace'/);
  }
  assert.doesNotMatch(source('src/routes/finance.tsx'), /TABS|Tabs|Outlet/);
});

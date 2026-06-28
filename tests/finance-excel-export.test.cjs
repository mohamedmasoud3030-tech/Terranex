const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildWorkbookXml,
  buildWorkbookBlob,
} = require('./.compiled/core/lib/xlsx.js');
const {
  buildTransactionsSheet,
  buildObligationsSheet,
  buildSummarySheet,
  buildFinanceWorkbookSheets,
} = require('./.compiled/features/reports/financeExport.js');

const lookups = {
  projectName: (id) => (id ? `Project ${id}` : ''),
  partnerName: (id) => (id ? `Partner ${id}` : ''),
  documentTitle: (id) => (id ? `Doc ${id}` : ''),
};

const transactions = [
  {
    id: 't1',
    project_id: 'p1',
    partner_id: 'pa1',
    direction: 'income',
    category: 'sale',
    amount: 1000,
    currency: 'EGP',
    fx_rate: 1,
    amount_egp: 1000,
    transaction_date: '2026-01-15',
    document_id: 'd1',
    description: 'بيع وحدة <عقارية>',
    notes: '',
    created_at: '2026-01-15T00:00:00Z',
    updated_at: '2026-01-15T00:00:00Z',
  },
  {
    id: 't2',
    project_id: 'p1',
    direction: 'expense',
    category: 'maintenance',
    amount: 200,
    currency: 'USD',
    fx_rate: 50,
    amount_egp: 10000,
    transaction_date: '2026-02-01',
    created_at: '2026-02-01T00:00:00Z',
    updated_at: '2026-02-01T00:00:00Z',
  },
];

const obligations = [
  {
    id: 'o1',
    project_id: 'p1',
    partner_id: 'pa2',
    direction: 'receivable',
    amount: 5000,
    currency: 'EGP',
    amount_egp: 5000,
    status: 'partial',
    amount_settled_egp: 2000,
    due_date: '2026-03-01',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  },
  {
    id: 'o2',
    partner_id: 'pa3',
    direction: 'payable',
    amount: 3000,
    currency: 'EGP',
    amount_egp: 3000,
    status: 'open',
    amount_settled_egp: 0,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  },
  {
    id: 'o3',
    partner_id: 'pa3',
    direction: 'payable',
    amount: 999,
    currency: 'EGP',
    amount_egp: 999,
    status: 'settled', // excluded from open totals
    amount_settled_egp: 999,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  },
];

test('transactions sheet maps rows with localized labels', () => {
  const sheet = buildTransactionsSheet(transactions, lookups, 'ar');
  assert.equal(sheet.rows.length, 2);
  assert.equal(sheet.rows[0][0], 't1');
  assert.equal(sheet.rows[0][2], 'إيراد'); // direction localized
  assert.equal(sheet.rows[0][4], 'Project p1');
  assert.equal(sheet.rows[0][9], 1000); // amount_egp numeric
  // EN locale switches direction label
  const en = buildTransactionsSheet(transactions, lookups, 'en');
  assert.equal(en.rows[0][2], 'Income');
});

test('obligations sheet computes remaining = amount_egp - settled', () => {
  const sheet = buildObligationsSheet(obligations, lookups, 'ar');
  assert.equal(sheet.rows.length, 3);
  // o1: 5000 - 2000 = 3000 remaining (col index 8)
  assert.equal(sheet.rows[0][8], 3000);
  assert.equal(sheet.rows[0][1], 'مستحق لنا');
});

test('summary excludes settled/written_off from open totals', () => {
  const sheet = buildSummarySheet(transactions, obligations, 'en');
  const byMetric = Object.fromEntries(sheet.rows.map((r) => [r[0], r[1]]));
  assert.equal(byMetric['Total income'], 1000);
  assert.equal(byMetric['Total expenses'], 10000);
  assert.equal(byMetric['Accounting profit'], -9000);
  assert.equal(byMetric['Open receivables'], 3000); // o1 remaining
  assert.equal(byMetric['Open payables'], 3000); // o2 only (o3 settled excluded)
  assert.equal(byMetric['Cash exposure'], 0); // 3000 - 3000
});

test('workbook has 3 sheets in summary/tx/obligations order', () => {
  const sheets = buildFinanceWorkbookSheets(transactions, obligations, lookups, 'en');
  assert.equal(sheets.length, 3);
  assert.equal(sheets[0].name, 'Summary');
  assert.equal(sheets[1].name, 'Transactions');
  assert.equal(sheets[2].name, 'Obligations');
});

test('workbook XML escapes special chars and is well-formed-ish', () => {
  const sheets = buildFinanceWorkbookSheets(transactions, obligations, lookups, 'ar');
  const xml = buildWorkbookXml(sheets);
  assert.match(xml, /^<\?xml version="1.0" encoding="UTF-8"\?>/);
  assert.match(xml, /<Workbook /);
  // The "<عقارية>" description must be escaped — no raw injected tags.
  assert.ok(xml.includes('&lt;') && xml.includes('&gt;'));
  assert.ok(!xml.includes('<عقارية>'));
  // Three worksheets present.
  assert.equal((xml.match(/<Worksheet /g) || []).length, 3);
});

test('buildWorkbookBlob returns an excel mime blob with BOM', () => {
  const sheets = buildFinanceWorkbookSheets(transactions, obligations, lookups, 'en');
  const blob = buildWorkbookBlob(sheets);
  assert.match(blob.type, /vnd\.ms-excel/);
  assert.ok(blob.size > 0);
});

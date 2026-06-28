/**
 * Finance Excel export — maps Transactions and Obligations into worksheet
 * specs for the dependency-free XLSX builder.
 *
 * Roadmap reference: P2 — R3 (Excel export — transactions + obligations).
 *
 * Output workbook contains three sheets:
 *   1. Transactions  — full ledger with project / partner / document links
 *   2. Obligations   — receivables & payables with settlement + remaining
 *   3. Summary       — totals by direction, currency-normalised to EGP
 */
import type {
  Locale,
  Obligation,
  Transaction,
  TransactionCategory,
  TransactionDirection,
  ObligationDirection,
  ObligationStatus,
} from '../../core/types/domain';
import type { SheetSpec } from '../../core/lib/xlsx';

export interface ExportLookups {
  projectName: (id?: string) => string;
  partnerName: (id?: string) => string;
  documentTitle: (id?: string) => string;
}

type Dict = Record<string, { ar: string; en: string }>;

const CATEGORY_LABELS: Record<TransactionCategory, { ar: string; en: string }> = {
  acquisition: { ar: 'اقتناء', en: 'Acquisition' },
  sale: { ar: 'بيع', en: 'Sale' },
  development_cost: { ar: 'تطوير', en: 'Development cost' },
  maintenance: { ar: 'صيانة', en: 'Maintenance' },
  salary: { ar: 'رواتب', en: 'Salary' },
  tax: { ar: 'ضرائب', en: 'Tax' },
  legal_fee: { ar: 'رسوم قانونية', en: 'Legal fee' },
  transport: { ar: 'نقل', en: 'Transport' },
  utility: { ar: 'مرافق', en: 'Utility' },
  seed_input: { ar: 'بذور', en: 'Seed input' },
  fertilizer: { ar: 'أسمدة', en: 'Fertilizer' },
  harvest_revenue: { ar: 'حصاد', en: 'Harvest revenue' },
  irrigation: { ar: 'ري', en: 'Irrigation' },
  feed: { ar: 'أعلاف', en: 'Feed' },
  veterinary: { ar: 'بيطرة', en: 'Veterinary' },
  vaccination: { ar: 'تحصينات', en: 'Vaccination' },
  livestock_purchase: { ar: 'شراء مواشٍ', en: 'Livestock purchase' },
  livestock_sale: { ar: 'بيع مواشٍ', en: 'Livestock sale' },
  loan_disbursement: { ar: 'قرض', en: 'Loan disbursement' },
  loan_repayment: { ar: 'سداد قرض', en: 'Loan repayment' },
  interest: { ar: 'فوائد', en: 'Interest' },
  dividend: { ar: 'أرباح موزعة', en: 'Dividend' },
  other: { ar: 'أخرى', en: 'Other' },
};

const TX_DIRECTION_LABELS: Record<TransactionDirection, { ar: string; en: string }> = {
  income: { ar: 'إيراد', en: 'Income' },
  expense: { ar: 'مصروف', en: 'Expense' },
};

const OB_DIRECTION_LABELS: Record<ObligationDirection, { ar: string; en: string }> = {
  receivable: { ar: 'مستحق لنا', en: 'Receivable' },
  payable: { ar: 'مستحق علينا', en: 'Payable' },
};

const OB_STATUS_LABELS: Record<ObligationStatus, { ar: string; en: string }> = {
  open: { ar: 'مفتوح', en: 'Open' },
  partial: { ar: 'سداد جزئي', en: 'Partial' },
  settled: { ar: 'مسدد', en: 'Settled' },
  disputed: { ar: 'متنازع عليه', en: 'Disputed' },
  written_off: { ar: 'مشطوب', en: 'Written off' },
};

const HEADERS: Dict = {
  id: { ar: 'المعرف', en: 'ID' },
  date: { ar: 'التاريخ', en: 'Date' },
  direction: { ar: 'الاتجاه', en: 'Direction' },
  category: { ar: 'التصنيف', en: 'Category' },
  project: { ar: 'المشروع', en: 'Project' },
  partner: { ar: 'الطرف', en: 'Partner' },
  amount: { ar: 'المبلغ', en: 'Amount' },
  currency: { ar: 'العملة', en: 'Currency' },
  fx: { ar: 'سعر الصرف', en: 'FX rate' },
  amountEgp: { ar: 'المبلغ (ج.م)', en: 'Amount (EGP)' },
  document: { ar: 'المستند', en: 'Document' },
  description: { ar: 'الوصف', en: 'Description' },
  notes: { ar: 'ملاحظات', en: 'Notes' },
  dueDate: { ar: 'تاريخ الاستحقاق', en: 'Due date' },
  status: { ar: 'الحالة', en: 'Status' },
  settledEgp: { ar: 'المسدد (ج.م)', en: 'Settled (EGP)' },
  remainingEgp: { ar: 'المتبقي (ج.م)', en: 'Remaining (EGP)' },
  metric: { ar: 'البند', en: 'Metric' },
  value: { ar: 'القيمة (ج.م)', en: 'Value (EGP)' },
  count: { ar: 'العدد', en: 'Count' },
};

function L(dict: { ar: string; en: string }, locale: Locale): string {
  return locale === 'ar' ? dict.ar : dict.en;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

export function buildTransactionsSheet(
  transactions: Transaction[],
  lookups: ExportLookups,
  locale: Locale,
): SheetSpec {
  const h = (k: string) => L(HEADERS[k], locale);
  return {
    name: locale === 'ar' ? 'المعاملات' : 'Transactions',
    columns: [
      { header: h('id'), width: 14 },
      { header: h('date'), width: 12 },
      { header: h('direction'), width: 10 },
      { header: h('category'), width: 16 },
      { header: h('project'), width: 22 },
      { header: h('partner'), width: 20 },
      { header: h('amount'), type: 'Number', width: 14 },
      { header: h('currency'), width: 9 },
      { header: h('fx'), type: 'Number', width: 10 },
      { header: h('amountEgp'), type: 'Number', width: 16 },
      { header: h('document'), width: 22 },
      { header: h('description'), width: 28 },
      { header: h('notes'), width: 28 },
    ],
    rows: transactions.map((t) => [
      t.id,
      t.transaction_date,
      L(TX_DIRECTION_LABELS[t.direction], locale),
      L(CATEGORY_LABELS[t.category] ?? { ar: t.category, en: t.category }, locale),
      lookups.projectName(t.project_id),
      lookups.partnerName(t.partner_id),
      round2(t.amount),
      t.currency,
      t.fx_rate,
      round2(t.amount_egp),
      lookups.documentTitle(t.document_id),
      t.description ?? '',
      t.notes ?? '',
    ]),
  };
}

export function buildObligationsSheet(
  obligations: Obligation[],
  lookups: ExportLookups,
  locale: Locale,
): SheetSpec {
  const h = (k: string) => L(HEADERS[k], locale);
  return {
    name: locale === 'ar' ? 'الالتزامات' : 'Obligations',
    columns: [
      { header: h('id'), width: 14 },
      { header: h('direction'), width: 11 },
      { header: h('project'), width: 22 },
      { header: h('partner'), width: 20 },
      { header: h('amount'), type: 'Number', width: 14 },
      { header: h('currency'), width: 9 },
      { header: h('amountEgp'), type: 'Number', width: 16 },
      { header: h('settledEgp'), type: 'Number', width: 16 },
      { header: h('remainingEgp'), type: 'Number', width: 16 },
      { header: h('status'), width: 12 },
      { header: h('dueDate'), width: 14 },
      { header: h('document'), width: 22 },
      { header: h('notes'), width: 28 },
    ],
    rows: obligations.map((o) => [
      o.id,
      L(OB_DIRECTION_LABELS[o.direction], locale),
      lookups.projectName(o.project_id),
      lookups.partnerName(o.partner_id),
      round2(o.amount),
      o.currency,
      round2(o.amount_egp),
      round2(o.amount_settled_egp),
      round2(o.amount_egp - o.amount_settled_egp),
      L(OB_STATUS_LABELS[o.status] ?? { ar: o.status, en: o.status }, locale),
      o.due_date ?? '',
      lookups.documentTitle(o.document_id),
      o.notes ?? '',
    ]),
  };
}

export function buildSummarySheet(
  transactions: Transaction[],
  obligations: Obligation[],
  locale: Locale,
): SheetSpec {
  const h = (k: string) => L(HEADERS[k], locale);

  const incomeEgp = transactions
    .filter((t) => t.direction === 'income')
    .reduce((s, t) => s + t.amount_egp, 0);
  const expenseEgp = transactions
    .filter((t) => t.direction === 'expense')
    .reduce((s, t) => s + t.amount_egp, 0);

  const openObligations = obligations.filter(
    (o) => o.status !== 'settled' && o.status !== 'written_off',
  );
  const openReceivable = openObligations
    .filter((o) => o.direction === 'receivable')
    .reduce((s, o) => s + (o.amount_egp - o.amount_settled_egp), 0);
  const openPayable = openObligations
    .filter((o) => o.direction === 'payable')
    .reduce((s, o) => s + (o.amount_egp - o.amount_settled_egp), 0);

  const lbl = (ar: string, en: string) => (locale === 'ar' ? ar : en);

  const rows: [string, number, number | string][] = [
    [lbl('إجمالي الإيرادات', 'Total income'), round2(incomeEgp), transactions.filter((t) => t.direction === 'income').length],
    [lbl('إجمالي المصروفات', 'Total expenses'), round2(expenseEgp), transactions.filter((t) => t.direction === 'expense').length],
    [lbl('صافي الربح المحاسبي', 'Accounting profit'), round2(incomeEgp - expenseEgp), transactions.length],
    [lbl('مستحقات لنا مفتوحة', 'Open receivables'), round2(openReceivable), openObligations.filter((o) => o.direction === 'receivable').length],
    [lbl('مستحقات علينا مفتوحة', 'Open payables'), round2(openPayable), openObligations.filter((o) => o.direction === 'payable').length],
    [lbl('التعرض النقدي', 'Cash exposure'), round2(openReceivable - openPayable), openObligations.length],
  ];

  return {
    name: locale === 'ar' ? 'الملخص' : 'Summary',
    columns: [
      { header: h('metric'), width: 28 },
      { header: h('value'), type: 'Number', width: 18 },
      { header: h('count'), type: 'Number', width: 10 },
    ],
    rows,
  };
}

export function buildFinanceWorkbookSheets(
  transactions: Transaction[],
  obligations: Obligation[],
  lookups: ExportLookups,
  locale: Locale,
): SheetSpec[] {
  return [
    buildSummarySheet(transactions, obligations, locale),
    buildTransactionsSheet(transactions, lookups, locale),
    buildObligationsSheet(obligations, lookups, locale),
  ];
}

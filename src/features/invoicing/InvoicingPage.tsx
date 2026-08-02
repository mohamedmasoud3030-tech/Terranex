import { FileText, Plus, Receipt, CheckCircle2, Send, CreditCard, ArrowDownLeft, ArrowUpRight, Eye } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { Suspense, lazy, useCallback, useEffect, useMemo, useState } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import { ModalOverlay } from '../../components/ui/ModalOverlay';
import { useI18n } from '../../core/i18n/context';
import { formatMoney } from '../../core/lib/format';
import type { Currency, PurchaseInvoice, SalesInvoice } from '../../core/types/domain';
import { useProjects } from '../projects/hooks';
import { usePartners } from '../partners/hooks';
import { useBankAccounts, useCompanySettings } from '../banking/hooks';
import { listInventoryItems } from '../inventory/storage';
import type { InventoryItem } from '../../core/types/domain';
import { issueInvoice, listInvoices, payInvoice } from './storage';
import { listPurchaseInvoices, payPurchaseInvoice, receivePurchaseInvoice } from './purchaseStorage';
import { InvoiceForm } from './InvoiceForm';
import { PurchaseInvoiceForm } from './PurchaseInvoiceForm';

const PdfViewLazy = lazy(() =>
  import('./InvoicePdfView').then((m) => ({ default: m.InvoicePdfView })),
);
const BillPdfViewLazy = lazy(() =>
  import('./PurchaseInvoicePdfView').then((m) => ({ default: m.PurchaseInvoicePdfView })),
);

type Tab = 'sales' | 'bills';

const SALES_STATUS_TONE: Record<string, 'positive' | 'warning' | 'negative' | 'neutral'> = {
  draft: 'neutral',
  issued: 'neutral',
  partial: 'warning',
  paid: 'positive',
  void: 'negative',
  overdue: 'negative',
};
const BILL_STATUS_TONE: Record<string, 'positive' | 'warning' | 'negative' | 'neutral'> = {
  draft: 'neutral',
  received: 'neutral',
  partial: 'warning',
  paid: 'positive',
  void: 'negative',
  overdue: 'negative',
};

function salesStatusLabel(locale: 'ar' | 'en', s: string) {
  const map: Record<string, string> = {
    draft: locale === 'ar' ? 'مسودة' : 'Draft',
    issued: locale === 'ar' ? 'مُصدرة' : 'Issued',
    partial: locale === 'ar' ? 'مدفوعة جزئياً' : 'Partial',
    paid: locale === 'ar' ? 'مدفوعة' : 'Paid',
    void: locale === 'ar' ? 'ملغاة' : 'Void',
    overdue: locale === 'ar' ? 'متأخرة' : 'Overdue',
  };
  return map[s] ?? s;
}
function billStatusLabel(locale: 'ar' | 'en', s: string) {
  const map: Record<string, string> = {
    draft: locale === 'ar' ? 'مسودة' : 'Draft',
    received: locale === 'ar' ? 'مُستلمة' : 'Received',
    partial: locale === 'ar' ? 'مدفوعة جزئياً' : 'Partial',
    paid: locale === 'ar' ? 'مدفوعة' : 'Paid',
    void: locale === 'ar' ? 'ملغاة' : 'Void',
    overdue: locale === 'ar' ? 'متأخرة' : 'Overdue',
  };
  return map[s] ?? s;
}

export function InvoicingPage() {
  const router = useRouter();
  const { t, locale } = useI18n();
  const { projects } = useProjects();
  const { partners } = usePartners();
  const { accounts } = useBankAccounts();
  const { settings } = useCompanySettings();

  const [tab, setTab] = useState<Tab>('sales');
  const [invoices, setInvoices] = useState<SalesInvoice[]>([]);
  const [bills, setBills] = useState<PurchaseInvoice[]>([]);
  const [inventoryItems, setInventoryItems] = useState<InventoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<null | { kind: 'sales'; id: string } | { kind: 'bill'; id: string }>(null);
  const [dialog, setDialog] = useState<null | 'create' | 'create_bill' | { kind: 'pay'; invoice: SalesInvoice } | { kind: 'pay_bill'; bill: PurchaseInvoice }>(null);
  const [actionPending, setActionPending] = useState(false);
  const [payForm, setPayForm] = useState({ amount: '', bank: '', date: new Date().toISOString().slice(0,10), memo: '' });
  const [payError, setPayError] = useState<string | null>(null);

  const baseCurrency: Currency = (settings?.base_currency as Currency) ?? 'OMR';
  const defaultVat = settings?.vat_enabled ? (settings.vat_rate ?? 0) : 0;
  const activeBanks = useMemo(() => accounts.filter(a => !a.is_archived), [accounts]);

  async function handleIssue(inv: SalesInvoice) {
    if (inv.status !== 'draft') return;
    setActionPending(true);
    try { await issueInvoice(inv.id); await refresh(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
    finally { setActionPending(false); }
  }

  async function handleReceive(bill: PurchaseInvoice) {
    if (bill.status !== 'draft') return;
    setActionPending(true);
    try { await receivePurchaseInvoice(bill.id); await refresh(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
    finally { setActionPending(false); }
  }

  function openPay(inv: SalesInvoice) {
    setPayForm({
      amount: String(Math.max(0, inv.total - inv.amount_paid)),
      bank: inv.bank_account_id ?? activeBanks[0]?.id ?? '',
      date: new Date().toISOString().slice(0, 10),
      memo: '',
    });
    setPayError(null);
    setDialog({ kind: 'pay', invoice: inv });
  }
  function openPayBill(bill: PurchaseInvoice) {
    setPayForm({
      amount: String(Math.max(0, bill.total - bill.amount_paid)),
      bank: bill.bank_account_id ?? activeBanks[0]?.id ?? '',
      date: new Date().toISOString().slice(0, 10),
      memo: '',
    });
    setPayError(null);
    setDialog({ kind: 'pay_bill', bill });
  }

  async function submitPay(e: React.FormEvent) {
    e.preventDefault();
    if (!dialog || typeof dialog === 'string') return;
    setPayError(null);
    const amount = Number(payForm.amount);
    if (!Number.isFinite(amount) || amount <= 0) { setPayError(locale === 'ar' ? 'أدخل مبلغاً صالحاً.' : 'Enter a valid amount.'); return; }
    if (!payForm.bank) { setPayError(locale === 'ar' ? 'اختر الحساب البنكي/الصندوق.' : 'Choose a bank/cash account.'); return; }
    setActionPending(true);
    try {
      if (dialog.kind === 'pay') {
        await payInvoice(dialog.invoice.id, amount, payForm.bank, payForm.date, payForm.memo || undefined);
      } else if (dialog.kind === 'pay_bill') {
        await payPurchaseInvoice(dialog.bill.id, amount, payForm.bank, payForm.date, payForm.memo || undefined);
      }
      await refresh();
      setDialog(null);
    } catch (e) {
      setPayError(e instanceof Error ? e.message : String(e));
    } finally {
      setActionPending(false);
    }
  }

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const [sales, billRows, items] = await Promise.all([
        listInvoices(),
        listPurchaseInvoices(),
        listInventoryItems().catch(() => [] as InventoryItem[]),
      ]);
      setInvoices(sales);
      setBills(billRows);
      setInventoryItems(items);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const receivables = invoices
    .filter(i => i.status !== 'void' && i.status !== 'draft')
    .reduce((s, i) => s + Math.max(0, i.total - i.amount_paid), 0);
  const payables = bills
    .filter(b => b.status !== 'void' && b.status !== 'draft')
    .reduce((s, b) => s + Math.max(0, b.total - b.amount_paid), 0);

  let payingTarget: SalesInvoice | PurchaseInvoice | null = null;
  let paymentDialogTitle = locale === 'ar' ? 'تسجيل دفعة على الفاتورة' : 'Register payment';
  if (dialog && typeof dialog === 'object') {
    if (dialog.kind === 'pay') payingTarget = dialog.invoice;
    if (dialog.kind === 'pay_bill') {
      payingTarget = dialog.bill;
      paymentDialogTitle = locale === 'ar' ? 'تسجيل دفعة على فاتورة مشتريات' : 'Register bill payment';
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={locale === 'ar' ? 'الفواتير والمشتريات' : 'Invoices & Bills'}
        description={locale === 'ar'
          ? 'إدارة فواتير المبيعات وفواتير المشتريات مع تتبع الذمم المدينة والدائنة والضريبة.'
          : 'Manage sales invoices and purchase bills with receivables, payables and VAT tracking.'}
      >
        <Button onClick={() => router.navigate({ to: '/finance' } as any)} variant="secondary">
          <Receipt className="h-4 w-4" /> {locale === 'ar' ? 'الذمم' : 'Obligations'}
        </Button>
        {tab === 'sales' ? (
          <Button onClick={() => setDialog('create')}>
            <Plus className="h-4 w-4" /> {locale === 'ar' ? 'فاتورة مبيعات' : 'New invoice'}
          </Button>
        ) : (
          <Button onClick={() => setDialog('create_bill')}>
            <Plus className="h-4 w-4" /> {locale === 'ar' ? 'فاتورة مشتريات' : 'New bill'}
          </Button>
        )}
      </PageHeader>

      {error && (
        <div className="rounded-2xl border border-danger/30 bg-danger/5 px-4 py-3 text-sm text-danger">{error}</div>
      )}

      {/* Tab switcher */}
      <div className="inline-flex rounded-xl border border-border bg-card p-1">
        <button
          type="button"
          onClick={() => setTab('sales')}
          className={`flex items-center gap-2 rounded-lg px-4 py-1.5 text-sm font-medium transition ${tab === 'sales' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'}`}
        >
          <ArrowUpRight className="h-4 w-4" /> {locale === 'ar' ? 'المبيعات' : 'Sales'}
          <span className="rounded-full bg-background/30 px-1.5 text-xs">{invoices.length}</span>
        </button>
        <button
          type="button"
          onClick={() => setTab('bills')}
          className={`flex items-center gap-2 rounded-lg px-4 py-1.5 text-sm font-medium transition ${tab === 'bills' ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'}`}
        >
          <ArrowDownLeft className="h-4 w-4" /> {locale === 'ar' ? 'المشتريات' : 'Bills'}
          <span className="rounded-full bg-background/30 px-1.5 text-xs">{bills.length}</span>
        </button>
      </div>

      {/* KPI cards */}
      {tab === 'sales' ? (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'إجمالي الفواتير' : 'Total invoices'}</p><p className="text-xl font-bold">{invoices.length}</p></CardContent></Card>
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'الذمم المدينة' : 'Receivables'}</p><p className="text-xl font-bold text-warning">{formatMoney(receivables, baseCurrency, locale)}</p></CardContent></Card>
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مسودات' : 'Drafts'}</p><p className="text-xl font-bold">{invoices.filter(i => i.status === 'draft').length}</p></CardContent></Card>
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مدفوعة' : 'Paid'}</p><p className="text-xl font-bold text-success">{invoices.filter(i => i.status === 'paid').length}</p></CardContent></Card>
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'إجمالي الفواتير' : 'Total bills'}</p><p className="text-xl font-bold">{bills.length}</p></CardContent></Card>
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'الذمم الدائنة' : 'Payables'}</p><p className="text-xl font-bold text-warning">{formatMoney(payables, baseCurrency, locale)}</p></CardContent></Card>
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مسودات' : 'Drafts'}</p><p className="text-xl font-bold">{bills.filter(b => b.status === 'draft').length}</p></CardContent></Card>
          <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مدفوعة' : 'Paid'}</p><p className="text-xl font-bold text-success">{bills.filter(b => b.status === 'paid').length}</p></CardContent></Card>
        </div>
      )}

      {/* Lists */}
      {tab === 'sales' ? (
        <Card>
          <CardHeader><h3 className="font-semibold">{locale === 'ar' ? 'قائمة فواتير المبيعات' : 'Sales invoices'}</h3></CardHeader>
          <CardContent className="p-0">
            {loading ? (
              <p className="px-4 py-8 text-center text-sm text-muted-foreground">{t('state_loading')}</p>
            ) : invoices.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-muted-foreground">{locale === 'ar' ? 'لا توجد فواتير بعد.' : 'No invoices yet.'}</p>
            ) : (
              <div className="divide-y divide-border">
                {invoices.map(inv => {
                  const outstanding = Math.max(0, inv.total - inv.amount_paid);
                  return (
                    <div key={inv.id} className="flex min-h-14 w-full items-center gap-3 px-4 py-3 hover:bg-muted/50">
                      <button type="button" onClick={() => setPreview({ kind: 'sales', id: inv.id })} className="flex flex-1 min-w-0 items-center gap-3 text-start">
                        <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-primary/20 bg-primary/5">
                          <FileText className="h-4 w-4 text-primary" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium truncate">{inv.invoice_number}</p>
                          <p className="text-xs text-muted-foreground">
                            {inv.issue_date} • {formatMoney(inv.total, inv.currency, locale)}
                            {inv.status !== 'draft' && inv.status !== 'paid' && outstanding > 0 && (
                              <> • {locale === 'ar' ? 'متبقي' : 'due'} {formatMoney(outstanding, inv.currency, locale)}</>
                            )}
                          </p>
                        </div>
                        <Badge tone={SALES_STATUS_TONE[inv.status] ?? 'neutral'}>{salesStatusLabel(locale, inv.status)}</Badge>
                      </button>
                      <div className="flex gap-1">
                        {inv.status === 'draft' && (
                          <button type="button" onClick={() => void handleIssue(inv)} disabled={actionPending} title={locale === 'ar' ? 'إصدار' : 'Issue'}
                            className="rounded-lg p-2 text-muted-foreground hover:bg-primary/10 hover:text-primary disabled:opacity-50">
                            <Send className="h-4 w-4" />
                          </button>
                        )}
                        {(inv.status === 'issued' || inv.status === 'partial') && (
                          <button type="button" onClick={() => openPay(inv)} disabled={actionPending} title={locale === 'ar' ? 'تسجيل دفعة' : 'Register payment'}
                            className="rounded-lg p-2 text-muted-foreground hover:bg-success/10 hover:text-success disabled:opacity-50">
                            <CreditCard className="h-4 w-4" />
                          </button>
                        )}
                        {inv.status === 'paid' && (
                          <span className="flex items-center rounded-lg p-2 text-success"><CheckCircle2 className="h-4 w-4" /></span>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader><h3 className="font-semibold">{locale === 'ar' ? 'قائمة فواتير المشتريات' : 'Purchase bills'}</h3></CardHeader>
          <CardContent className="p-0">
            {loading ? (
              <p className="px-4 py-8 text-center text-sm text-muted-foreground">{t('state_loading')}</p>
            ) : bills.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-muted-foreground">{locale === 'ar' ? 'لا توجد فواتير مشتريات بعد.' : 'No bills yet.'}</p>
            ) : (
              <div className="divide-y divide-border">
                  {bills.map(b => {
                  const outstanding = Math.max(0, b.total - b.amount_paid);
                  return (
                    <div key={b.id} className="flex min-h-14 w-full items-center gap-3 px-4 py-3 hover:bg-muted/50">
                      <button type="button" onClick={() => setPreview({ kind: 'bill', id: b.id })} className="flex flex-1 min-w-0 items-center gap-3 text-start">
                        <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-warning/20 bg-warning/5">
                          <FileText className="h-4 w-4 text-warning" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium truncate">
                            {b.invoice_number}
                            {b.vendor_invoice_number && <span className="ms-2 text-xs text-muted-foreground">#{b.vendor_invoice_number}</span>}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {b.issue_date} • {formatMoney(b.total, b.currency, locale)}
                            {b.status !== 'draft' && b.status !== 'paid' && outstanding > 0 && (
                              <> • {locale === 'ar' ? 'مستحق' : 'due'} {formatMoney(outstanding, b.currency, locale)}</>
                            )}
                          </p>
                        </div>
                        <Badge tone={BILL_STATUS_TONE[b.status] ?? 'neutral'}>{billStatusLabel(locale, b.status)}</Badge>
                      </button>
                      <div className="flex gap-1">
                        {b.status === 'draft' && (
                          <button type="button" onClick={() => void handleReceive(b)} disabled={actionPending} title={locale === 'ar' ? 'اعتماد / استلام' : 'Receive'}
                            className="rounded-lg p-2 text-muted-foreground hover:bg-primary/10 hover:text-primary disabled:opacity-50">
                            <CheckCircle2 className="h-4 w-4" />
                          </button>
                        )}
                        {(b.status === 'received' || b.status === 'partial') && (
                          <button type="button" onClick={() => openPayBill(b)} disabled={actionPending} title={locale === 'ar' ? 'تسجيل دفعة' : 'Register payment'}
                            className="rounded-lg p-2 text-muted-foreground hover:bg-success/10 hover:text-success disabled:opacity-50">
                            <CreditCard className="h-4 w-4" />
                          </button>
                        )}
                        {b.status === 'paid' && (
                          <span className="flex items-center rounded-lg p-2 text-success"><CheckCircle2 className="h-4 w-4" /></span>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* PDF preview */}
      {preview && (
        <ModalOverlay closeLabel={locale === 'ar' ? 'إغلاق المعاينة' : 'Close preview'} onClose={() => setPreview(null)} contentClassName="max-h-[90vh] w-full max-w-3xl overflow-auto rounded-2xl bg-card p-6 shadow-xl">
            <Suspense fallback={<p className="text-sm text-muted-foreground">{t('state_loading')}</p>}>
              {preview.kind === 'sales'
                ? <PdfViewLazy invoiceId={preview.id} />
                : <BillPdfViewLazy invoiceId={preview.id} />}
            </Suspense>
            <div className="flex justify-end pt-4">
              <Button variant="secondary" onClick={() => setPreview(null)}>{t('action_cancel')}</Button>
            </div>
        </ModalOverlay>
      )}

      {/* Payment dialog */}
      {payingTarget && (
        <ModalOverlay closeLabel={locale === 'ar' ? 'إلغاء تسجيل الدفعة' : 'Cancel payment'} onClose={() => setDialog(null)} onSubmit={submitPay} contentClassName="w-full max-w-md rounded-2xl bg-card p-6 shadow-xl space-y-3">
            <h3 className="mb-2 font-semibold">
              {paymentDialogTitle}
              {' — '}{payingTarget.invoice_number}
            </h3>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'المبلغ' : 'Amount'} ({payingTarget.currency})</FormLabel>
              <input type="number" step="0.001" min="0" value={payForm.amount} onChange={e => setPayForm(f => ({...f, amount: e.target.value}))}
                className="min-h-10 w-full rounded-lg border border-border bg-background px-3" dir="ltr" autoFocus />
            </FormField>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'الحساب' : 'From account'}</FormLabel>
              <select value={payForm.bank} onChange={e => setPayForm(f => ({...f, bank: e.target.value}))}
                className="min-h-10 w-full rounded-lg border border-border bg-background px-3">
                {activeBanks.map(a => <option key={a.id} value={a.id}>{a.currency} — {a.name_ar}</option>)}
              </select>
            </FormField>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'التاريخ' : 'Date'}</FormLabel>
              <input type="date" value={payForm.date} onChange={e => setPayForm(f => ({...f, date: e.target.value}))}
                className="min-h-10 w-full rounded-lg border border-border bg-background px-3" />
            </FormField>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'ملاحظات' : 'Memo'}</FormLabel>
              <input value={payForm.memo} onChange={e => setPayForm(f => ({...f, memo: e.target.value}))}
                className="min-h-10 w-full rounded-lg border border-border bg-background px-3" />
            </FormField>
            {payError && <FormError>{payError}</FormError>}
            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="secondary" onClick={() => setDialog(null)} disabled={actionPending}>{locale === 'ar' ? 'إلغاء' : 'Cancel'}</Button>
              <Button type="submit" disabled={actionPending}>{actionPending ? (locale === 'ar' ? 'جارٍ…' : 'Saving…') : (locale === 'ar' ? 'تسجيل الدفعة' : 'Register payment')}</Button>
            </div>
        </ModalOverlay>
      )}

      {/* Create sales invoice */}
      {dialog === 'create' && (
        <ModalOverlay closeLabel={locale === 'ar' ? 'إلغاء إنشاء الفاتورة' : 'Cancel invoice'} onClose={() => setDialog(null)} placement="start" contentClassName="my-8 w-full max-w-3xl rounded-2xl bg-card p-6 shadow-xl">
            <h3 className="mb-4 font-semibold">{locale === 'ar' ? 'فاتورة مبيعات جديدة' : 'New sales invoice'}</h3>
            <InvoiceForm
              projects={projects}
              partners={partners}
              bankAccounts={accounts}
              defaultCurrency={baseCurrency}
              defaultVatRate={defaultVat}
              onCancel={() => setDialog(null)}
              onSaved={async () => { setDialog(null); await refresh(); }}
            />
        </ModalOverlay>
      )}

      {/* Create purchase bill */}
      {dialog === 'create_bill' && (
        <ModalOverlay closeLabel={locale === 'ar' ? 'إلغاء إنشاء فاتورة المشتريات' : 'Cancel purchase bill'} onClose={() => setDialog(null)} placement="start" contentClassName="my-8 w-full max-w-3xl rounded-2xl bg-card p-6 shadow-xl">
            <h3 className="mb-4 font-semibold">{locale === 'ar' ? 'فاتورة مشتريات جديدة' : 'New purchase bill'}</h3>
            <PurchaseInvoiceForm
              projects={projects}
              partners={partners}
              bankAccounts={accounts}
              inventoryItems={inventoryItems}
              defaultCurrency={baseCurrency}
              defaultVatRate={defaultVat}
              onCancel={() => setDialog(null)}
              onSaved={async () => { setDialog(null); await refresh(); }}
            />
        </ModalOverlay>
      )}
    </div>
  );
}

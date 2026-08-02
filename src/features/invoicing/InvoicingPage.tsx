import { FileText, Plus, Receipt, CheckCircle2, Send, CreditCard } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { Suspense, lazy, useCallback, useEffect, useState } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import { useI18n } from '../../core/i18n/context';
import { formatMoney } from '../../core/lib/format';
import type { Currency, SalesInvoice } from '../../core/types/domain';
import { useProjects } from '../projects/hooks';
import { usePartners } from '../partners/hooks';
import { useBankAccounts, useCompanySettings } from '../banking/hooks';
import { issueInvoice, listInvoices, payInvoice } from './storage';
import { InvoiceForm } from './InvoiceForm';

const PdfViewLazy = lazy(() =>
  import('./InvoicePdfView').then((m) => ({ default: m.InvoicePdfView })),
);

const STATUS_TONE: Record<string, 'positive' | 'warning' | 'negative' | 'neutral'> = {
  draft: 'neutral',
  issued: 'neutral',
  partial: 'warning',
  paid: 'positive',
  void: 'negative',
  overdue: 'negative',
};

function statusLabel(locale: 'ar' | 'en', s: string) {
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

export function InvoicingPage() {
  const router = useRouter();
  const { t, locale } = useI18n();
  const { projects } = useProjects();
  const { partners } = usePartners();
  const { accounts } = useBankAccounts();
  const { settings } = useCompanySettings();

  const [invoices, setInvoices] = useState<SalesInvoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [previewId, setPreviewId] = useState<string | null>(null);
  const [dialog, setDialog] = useState<null | 'create' | { kind: 'pay'; invoice: SalesInvoice }>(null);
  const [actionPending, setActionPending] = useState(false);
  const [payForm, setPayForm] = useState({ amount: '', bank: '', date: new Date().toISOString().slice(0,10), memo: '' });
  const [payError, setPayError] = useState<string | null>(null);

  const baseCurrency: Currency = (settings?.base_currency as Currency) ?? 'OMR';
  const defaultVat = settings?.vat_enabled ? (settings.vat_rate ?? 0) : 0;
  const activeBanks = accounts.filter(a => !a.is_archived);

  async function handleIssue(inv: SalesInvoice) {
    if (inv.status !== 'draft') return;
    setActionPending(true);
    try { await issueInvoice(inv.id); await refresh(); }
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

  async function submitPay(e: React.FormEvent) {
    e.preventDefault();
    if (!dialog || typeof dialog === 'string' || dialog.kind !== 'pay') return;
    setPayError(null);
    const amount = Number(payForm.amount);
    if (!Number.isFinite(amount) || amount <= 0) { setPayError(locale === 'ar' ? 'أدخل مبلغاً صالحاً.' : 'Enter a valid amount.'); return; }
    if (!payForm.bank) { setPayError(locale === 'ar' ? 'اختر الحساب البنكي/الصندوق.' : 'Choose a bank/cash account.'); return; }
    setActionPending(true);
    try {
      await payInvoice(dialog.invoice.id, amount, payForm.bank, payForm.date, payForm.memo || undefined);
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
      const rows = await listInvoices();
      setInvoices(rows);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const totalDueBase = invoices
    .filter((i) => i.status !== 'void' && i.status !== 'draft')
    .reduce((s, i) => s + Math.max(0, i.total - i.amount_paid), 0);

  return (
    <div className="space-y-6">
      <PageHeader
        title={locale === 'ar' ? 'الفواتير' : 'Invoices'}
        description={locale === 'ar'
          ? 'إصدار فواتير المبيعات وتتبع التحصيل والدفع مع حساب القيمة المضافة.'
          : 'Issue VAT-compliant sales invoices, track receivables and payments.'}
      >
        <Button onClick={() => router.navigate({ to: '/finance' } as any)} variant="secondary">
          <Receipt className="h-4 w-4" /> {locale === 'ar' ? 'الذمم' : 'Obligations'}
        </Button>
        <Button onClick={() => setDialog('create')}>
          <Plus className="h-4 w-4" /> {locale === 'ar' ? 'فاتورة جديدة' : 'New invoice'}
        </Button>
      </PageHeader>

      {error && (
        <div className="rounded-2xl border border-danger/30 bg-danger/5 px-4 py-3 text-sm text-danger">
          {error}
        </div>
      )}

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'إجمالي الفواتير' : 'Total invoices'}</p>
            <p className="text-xl font-bold">{invoices.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'المبالغ المستحقة' : 'Outstanding'}</p>
            <p className="text-xl font-bold text-warning">{formatMoney(totalDueBase, baseCurrency, locale)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مسودات' : 'Drafts'}</p>
            <p className="text-xl font-bold">{invoices.filter(i => i.status === 'draft').length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مدفوعة' : 'Paid'}</p>
            <p className="text-xl font-bold text-success">{invoices.filter(i => i.status === 'paid').length}</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <h3 className="font-semibold">{locale === 'ar' ? 'قائمة الفواتير' : 'Invoice list'}</h3>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <p className="px-4 py-8 text-center text-sm text-muted-foreground">{t('state_loading')}</p>
          ) : invoices.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-muted-foreground">
              {locale === 'ar' ? 'لا توجد فواتير بعد. ابدأ بإنشاء أول فاتورة.' : 'No invoices yet.'}
            </p>
          ) : (
            <div className="divide-y divide-border">
              {invoices.map((inv) => {
                const outstanding = Math.max(0, inv.total - inv.amount_paid);
                return (
                <div key={inv.id} className="flex min-h-14 w-full items-center gap-3 px-4 py-3 hover:bg-muted/50">
                  <button onClick={() => setPreviewId(inv.id)} className="flex flex-1 min-w-0 items-center gap-3 text-start">
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
                    <Badge tone={STATUS_TONE[inv.status] ?? 'neutral'}>
                      {statusLabel(locale, inv.status)}
                    </Badge>
                  </button>
                  <div className="flex gap-1">
                    {inv.status === 'draft' && (
                      <button onClick={() => void handleIssue(inv)} disabled={actionPending}
                        title={locale === 'ar' ? 'إصدار' : 'Issue'}
                        className="rounded-lg p-2 text-muted-foreground hover:bg-primary/10 hover:text-primary disabled:opacity-50">
                        <Send className="h-4 w-4" />
                      </button>
                    )}
                    {(inv.status === 'issued' || inv.status === 'partial') && (
                      <button onClick={() => openPay(inv)} disabled={actionPending}
                        title={locale === 'ar' ? 'تسجيل دفعة' : 'Register payment'}
                        className="rounded-lg p-2 text-muted-foreground hover:bg-success/10 hover:text-success disabled:opacity-50">
                        <CreditCard className="h-4 w-4" />
                      </button>
                    )}
                    {inv.status === 'paid' && (
                      <span className="flex items-center rounded-lg p-2 text-success">
                        <CheckCircle2 className="h-4 w-4" />
                      </span>
                    )}
                  </div>
                </div>
              );})}
            </div>
          )}
        </CardContent>
      </Card>

      {previewId && (
        <div
          role="button"
          tabIndex={0}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 cursor-pointer"
          onClick={() => setPreviewId(null)}
          onKeyDown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') setPreviewId(null); }}
        >
          <div className="max-h-[90vh] w-full max-w-3xl overflow-auto rounded-2xl bg-card p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <Suspense fallback={<p className="text-sm text-muted-foreground">{t('state_loading')}</p>}>
              <PdfViewLazy invoiceId={previewId} />
            </Suspense>
            <div className="flex justify-end pt-4">
              <Button variant="secondary" onClick={() => setPreviewId(null)}>{t('action_cancel')}</Button>
            </div>
          </div>
        </div>
      )}

      {dialog && typeof dialog === 'object' && dialog.kind === 'pay' && (
        <div
          role="button"
          tabIndex={0}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 cursor-pointer"
          onClick={() => setDialog(null)}
          onKeyDown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') setDialog(null); }}
        >
          <form onSubmit={submitPay} onClick={(e) => e.stopPropagation()} className="w-full max-w-md rounded-2xl bg-card p-6 shadow-xl space-y-3">
            <h3 className="mb-2 font-semibold">
              {locale === 'ar' ? 'تسجيل دفعة على الفاتورة' : 'Register payment'} — {dialog.invoice.invoice_number}
            </h3>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'المبلغ' : 'Amount'} ({dialog.invoice.currency})</FormLabel>
              <input type="number" step="0.001" min="0" value={payForm.amount} onChange={e => setPayForm(f => ({...f, amount: e.target.value}))} className="min-h-10 w-full rounded-lg border border-border bg-background px-3" dir="ltr" autoFocus />
            </FormField>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'الحساب' : 'From account'}</FormLabel>
              <select value={payForm.bank} onChange={e => setPayForm(f => ({...f, bank: e.target.value}))} className="min-h-10 w-full rounded-lg border border-border bg-background px-3">
                {activeBanks.map(a => <option key={a.id} value={a.id}>{a.currency} — {a.name_ar}</option>)}
              </select>
            </FormField>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'التاريخ' : 'Date'}</FormLabel>
              <input type="date" value={payForm.date} onChange={e => setPayForm(f => ({...f, date: e.target.value}))} className="min-h-10 w-full rounded-lg border border-border bg-background px-3" />
            </FormField>
            <FormField>
              <FormLabel>{locale === 'ar' ? 'ملاحظات' : 'Memo'}</FormLabel>
              <input value={payForm.memo} onChange={e => setPayForm(f => ({...f, memo: e.target.value}))} className="min-h-10 w-full rounded-lg border border-border bg-background px-3" />
            </FormField>
            {payError && <FormError>{payError}</FormError>}
            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="secondary" onClick={() => setDialog(null)} disabled={actionPending}>{locale === 'ar' ? 'إلغاء' : 'Cancel'}</Button>
              <Button type="submit" disabled={actionPending}>{actionPending ? (locale === 'ar' ? 'جارٍ…' : 'Saving…') : (locale === 'ar' ? 'تسجيل الدفعة' : 'Register payment')}</Button>
            </div>
          </form>
        </div>
      )}

      {dialog === 'create' && (
        <div
          role="button"
          tabIndex={0}
          className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 cursor-pointer"
          onClick={() => setDialog(null)}
          onKeyDown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') setDialog(null); }}
        >
          <div className="my-8 w-full max-w-3xl rounded-2xl bg-card p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
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
          </div>
        </div>
      )}
    </div>
  );
}

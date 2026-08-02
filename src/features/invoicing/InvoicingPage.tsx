import { FileText, Plus, Receipt } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { Suspense, lazy, useCallback, useEffect, useState } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { useI18n } from '../../core/i18n/context';
import { formatMoney } from '../../core/lib/format';
import type { Currency, SalesInvoice } from '../../core/types/domain';
import { listInvoices } from './storage';

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
  const [invoices, setInvoices] = useState<SalesInvoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [previewId, setPreviewId] = useState<string | null>(null);

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

  const totalDue = invoices
    .filter((i) => i.status !== 'void' && i.status !== 'draft')
    .reduce((s, i) => s + Math.max(0, i.total - i.amount_paid), 0);

  const baseCurrency: Currency = 'OMR';

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
        <Button onClick={() => router.navigate({ to: '/banking' } as any)}>
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
            <p className="text-xl font-bold text-warning">{formatMoney(totalDue, baseCurrency, locale)}</p>
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
              {invoices.map((inv) => (
                <button
                  key={inv.id}
                  onClick={() => setPreviewId(inv.id)}
                  className="flex min-h-14 w-full items-center gap-3 px-4 py-3 text-start transition hover:bg-muted/50"
                >
                  <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-primary/20 bg-primary/5">
                    <FileText className="h-4 w-4 text-primary" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{inv.invoice_number}</p>
                    <p className="text-xs text-muted-foreground">
                      {inv.issue_date} • {formatMoney(inv.total, inv.currency, locale)}
                    </p>
                  </div>
                  <Badge tone={STATUS_TONE[inv.status] ?? 'neutral'}>
                    {statusLabel(locale, inv.status)}
                  </Badge>
                </button>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {previewId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => setPreviewId(null)}>
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
    </div>
  );
}

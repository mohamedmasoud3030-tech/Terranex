import { FileBarChart, Receipt } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { useI18n } from '../../core/i18n/context';
import { formatMoney } from '../../core/lib/format';
import type { Currency, PurchaseInvoice, SalesInvoice } from '../../core/types/domain';
import { useCompanySettings } from '../banking/hooks';
import { listInvoices } from '../invoicing/storage';
import { listPurchaseInvoices } from '../invoicing/purchaseStorage';

function startOfPeriod(year: number, period: 'month' | 'quarter', which: number): string {
  if (period === 'month') {
    const m = String(which).padStart(2, '0');
    return `${year}-${m}-01`;
  }
  const startMonth = ((which - 1) * 3) + 1;
  return `${year}-${String(startMonth).padStart(2, '0')}-01`;
}
function endOfPeriod(year: number, period: 'month' | 'quarter', which: number): string {
  const start = new Date(startOfPeriod(year, period, which));
  let endMonth: number;
  if (period === 'month') {
    endMonth = which + 1;
  } else {
    endMonth = ((which - 1) * 3) + 4;
  }
  const endYear = endMonth > 12 ? year + 1 : year;
  endMonth = endMonth > 12 ? 1 : endMonth;
  const end = new Date(endYear, endMonth - 1, 0);
  return end.toISOString().slice(0, 10);
}

export function VatReturnPage() {
  const router = useRouter();
  const { locale } = useI18n();
  const { settings } = useCompanySettings();
  const baseCurrency: Currency = (settings?.base_currency as Currency) ?? 'OMR';

  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [period, setPeriod] = useState<'month' | 'quarter'>('quarter');
  const [which, setWhich] = useState(Math.min(4, Math.floor(today.getMonth() / 3) + 1));
  const [invoices, setInvoices] = useState<SalesInvoice[]>([]);
  const [bills, setBills] = useState<PurchaseInvoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const [s, p] = await Promise.all([listInvoices(), listPurchaseInvoices()]);
      setInvoices(s); setBills(p); setError(null);
    } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void refresh(); }, [refresh]);

  const from = startOfPeriod(year, period, which);
  const to = endOfPeriod(year, period, which);

  const inRange = (d: string) => d >= from && d <= to;

  const relevantInvoices = useMemo(() => invoices.filter(i =>
    i.status !== 'void' && i.status !== 'draft' && inRange(i.issue_date)
  ), [invoices, from, to]);
  const relevantBills = useMemo(() => bills.filter(b =>
    b.status !== 'void' && b.status !== 'draft' && inRange(b.issue_date)
  ), [bills, from, to]);

  // Output VAT (collected from customers) - in document currency converted via fx
  const outputTaxBase = relevantInvoices.reduce((s, i) =>
    s + i.vat_amount * i.fx_rate_to_base, 0);
  const outputTaxableBase = relevantInvoices.reduce((s, i) =>
    s + i.subtotal * i.fx_rate_to_base, 0);
  const outputTotal = relevantInvoices.reduce((s, i) =>
    s + i.total * i.fx_rate_to_base, 0);

  // Input VAT (paid to vendors on purchases) - recoverable
  const inputTaxBase = relevantBills.reduce((s, b) =>
    s + b.vat_amount * b.fx_rate_to_base, 0);
  const inputTaxableBase = relevantBills.reduce((s, b) =>
    s + b.subtotal * b.fx_rate_to_base, 0);
  const inputTotal = relevantBills.reduce((s, b) =>
    s + b.total * b.fx_rate_to_base, 0);

  const vatPayable = Math.round((outputTaxBase - inputTaxBase) * 1000) / 1000;
  const netPosition = vatPayable; // positive = payable, negative = refund

  return (
    <div className="space-y-6">
      <PageHeader
        title={locale === 'ar' ? 'إقرار ضريبة القيمة المضافة' : 'VAT Return'}
        description={locale === 'ar'
          ? 'ملخص ضريبة المخرجات (المبيعات) وضريبة المدخلات (المشتريات) للفترة المحددة.'
          : 'Summary of output VAT (sales) and input VAT (purchases) for the selected period.'}
      >
        <Button onClick={() => router.navigate({ to: '/finance' } as any)} variant="secondary">
          <Receipt className="h-4 w-4" /> {locale === 'ar' ? 'المالية' : 'Finance'}
        </Button>
      </PageHeader>

      {error && <div className="rounded-2xl border border-danger/30 bg-danger/5 px-4 py-3 text-sm text-danger">{error}</div>}

      <Card>
        <CardHeader>
          <h3 className="flex items-center gap-2 font-semibold">
            <FileBarChart className="h-4 w-4" /> {locale === 'ar' ? 'فترة الإقرار' : 'Return period'}
          </h3>
        </CardHeader>
        <CardContent>
          <div className="grid gap-3 sm:grid-cols-4">
            <div>
              <label className="text-xs text-muted-foreground">{locale === 'ar' ? 'السنة' : 'Year'}</label>
              <input type="number" min="2000" max="2100" value={year} onChange={e => setYear(Number(e.target.value))}
                className="mt-1 min-h-10 w-full rounded-lg border border-border bg-background px-3" dir="ltr" />
            </div>
            <div>
              <label className="text-xs text-muted-foreground">{locale === 'ar' ? 'نوع الفترة' : 'Period type'}</label>
              <select value={period} onChange={e => { setPeriod(e.target.value as 'month' | 'quarter'); setWhich(1); }}
                className="mt-1 min-h-10 w-full rounded-lg border border-border bg-background px-3">
                <option value="month">{locale === 'ar' ? 'شهري' : 'Monthly'}</option>
                <option value="quarter">{locale === 'ar' ? 'ربع سنوي' : 'Quarterly'}</option>
              </select>
            </div>
            <div>
              <label className="text-xs text-muted-foreground">{locale === 'ar' ? 'الفترة' : 'Period #'}</label>
              <select value={which} onChange={e => setWhich(Number(e.target.value))}
                className="mt-1 min-h-10 w-full rounded-lg border border-border bg-background px-3">
                {period === 'month'
                  ? Array.from({ length: 12 }, (_, i) => i + 1).map(m => (
                      <option key={m} value={m}>{locale === 'ar' ? `شهر ${m}` : `Month ${m}`}</option>))
                  : [1, 2, 3, 4].map(q => (
                      <option key={q} value={q}>{locale === 'ar' ? `الربع ${q}` : `Q${q}`}</option>))}
              </select>
            </div>
            <div className="flex items-end">
              <p className="text-sm text-muted-foreground">{from} → {to}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {loading ? (
        <p className="text-sm text-muted-foreground">...</p>
      ) : (
        <>
          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <CardHeader><h3 className="font-semibold text-success">{locale === 'ar' ? 'المبيعات (ضريبة المخرجات)' : 'Sales (output VAT)'}</h3></CardHeader>
              <CardContent className="space-y-2 text-sm">
                <div className="flex justify-between"><span>{locale === 'ar' ? 'عدد الفواتير' : 'Invoice count'}</span><b>{relevantInvoices.length}</b></div>
                <div className="flex justify-between"><span>{locale === 'ar' ? 'الوعاء (أساس) بالعملة الأساس' : 'Taxable base'}</span><b>{formatMoney(outputTaxableBase, baseCurrency, locale)}</b></div>
                <div className="flex justify-between"><span>{locale === 'ar' ? 'إجمالي المبيعات' : 'Total sales'}</span><b>{formatMoney(outputTotal, baseCurrency, locale)}</b></div>
                <div className="flex justify-between border-t pt-2 text-success font-bold"><span>{locale === 'ar' ? 'ضريبة المخرجات' : 'Output VAT'}</span><span>{formatMoney(outputTaxBase, baseCurrency, locale)}</span></div>
              </CardContent>
            </Card>
            <Card>
              <CardHeader><h3 className="font-semibold text-warning">{locale === 'ar' ? 'المشتريات (ضريبة المدخلات)' : 'Purchases (input VAT)'}</h3></CardHeader>
              <CardContent className="space-y-2 text-sm">
                <div className="flex justify-between"><span>{locale === 'ar' ? 'عدد الفواتير' : 'Bill count'}</span><b>{relevantBills.length}</b></div>
                <div className="flex justify-between"><span>{locale === 'ar' ? 'الوعاء (أساس) بالعملة الأساس' : 'Taxable base'}</span><b>{formatMoney(inputTaxableBase, baseCurrency, locale)}</b></div>
                <div className="flex justify-between"><span>{locale === 'ar' ? 'إجمالي المشتريات' : 'Total purchases'}</span><b>{formatMoney(inputTotal, baseCurrency, locale)}</b></div>
                <div className="flex justify-between border-t pt-2 text-warning font-bold"><span>{locale === 'ar' ? 'ضريبة المدخلات القابلة للخصم' : 'Deductible input VAT'}</span><span>{formatMoney(inputTaxBase, baseCurrency, locale)}</span></div>
              </CardContent>
            </Card>
          </div>

          <Card className={netPosition >= 0 ? 'border-danger/30 bg-danger/5' : 'border-success/30 bg-success/5'}>
            <CardContent className="p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'صافي الضريبة المستحقة' : 'Net VAT payable / (refundable)'}</p>
                  <p className={`text-3xl font-bold ${netPosition >= 0 ? 'text-danger' : 'text-success'}`}>
                    {formatMoney(Math.abs(netPosition), baseCurrency, locale)}
                  </p>
                </div>
                <p className="max-w-md text-sm text-muted-foreground">
                  {netPosition >= 0
                    ? (locale === 'ar' ? 'يجب سداد هذا المبلغ للجهة الضريبية.' : 'Amount payable to the tax authority.')
                    : (locale === 'ar' ? 'لديك رصيد مسترد من الضريبة.' : 'You have a refundable VAT credit.')}
                </p>
              </div>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}

import { useEffect, useMemo, useState } from 'react';
import { Plus } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Card, CardContent } from '../../components/ui/Card';
import { todayIso } from '../../core/lib/dateUtils';
import type { Currency, ExchangeRate } from '../../core/types/domain';

const STORAGE_KEY = 'terranex.exchangeRates.v1';
const FOREIGN_CURRENCIES: Exclude<Currency, 'EGP'>[] = ['USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];
export const RATE_POLICY_CURRENCIES: Currency[] = ['EGP', ...FOREIGN_CURRENCIES];

export function loadExchangeRates(): ExchangeRate[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is ExchangeRate =>
      item && typeof item.id === 'string' && typeof item.rate === 'number' && item.rate > 0,
    ).sort((first, second) => second.effective_date.localeCompare(first.effective_date));
  } catch {
    return [];
  }
}

function saveExchangeRates(rates: ExchangeRate[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(rates));
}

export function ExchangeRateSection({ locale }: { locale: 'ar' | 'en' }) {
  const ar = locale === 'ar';
  const [rates, setRates] = useState(loadExchangeRates);
  const [formOpen, setFormOpen] = useState(false);
  const [currency, setCurrency] = useState<Exclude<Currency, 'EGP'>>('USD');
  const [rate, setRate] = useState('');
  const [effectiveDate, setEffectiveDate] = useState(todayIso());
  const [error, setError] = useState('');
  const latestByCurrency = useMemo(() => new Map(
    FOREIGN_CURRENCIES.map((item) => [item, rates.find((rateItem) => rateItem.from_currency === item)]),
  ), [rates]);

  useEffect(() => {
    const sync = (event: StorageEvent) => {
      if (event.key === STORAGE_KEY) setRates(loadExchangeRates());
    };
    window.addEventListener('storage', sync);
    return () => window.removeEventListener('storage', sync);
  }, []);

  function createRate() {
    const parsedRate = Number(rate);
    if (!Number.isFinite(parsedRate) || parsedRate <= 0) {
      setError(ar ? 'أدخل سعر صرف موجبًا.' : 'Enter a positive exchange rate.');
      return;
    }
    if (!effectiveDate) {
      setError(ar ? 'تاريخ السريان مطلوب.' : 'Effective date is required.');
      return;
    }
    const entry: ExchangeRate = {
      id: crypto.randomUUID(),
      from_currency: currency,
      to_currency: 'EGP',
      rate: parsedRate,
      effective_date: effectiveDate,
      source: 'manual',
      created_at: new Date().toISOString(),
    };
    const next = [entry, ...rates].sort((first, second) => second.effective_date.localeCompare(first.effective_date));
    saveExchangeRates(next);
    setRates(next);
    setRate('');
    setError('');
    setFormOpen(false);
  }

  return (
    <>
      <Card>
        <CardContent>
          <div className="flex items-start justify-between gap-3">
            <div>
              <h2 className="font-bold">{ar ? 'سياسة أسعار الصرف' : 'Exchange-rate policy'}</h2>
              <p className="mt-1 text-sm text-muted-foreground">{ar ? 'EGP هو الأساس، وست عملات أجنبية مدعومة. السعر المسجل في المعاملة لا يتغير بأثر رجعي.' : 'EGP is the base with six supported foreign currencies. A transaction keeps the rate captured when it was recorded.'}</p>
            </div>
            <Button variant="secondary" onClick={() => setFormOpen(true)}><Plus className="h-4 w-4" />{ar ? 'سعر جديد' : 'New rate'}</Button>
          </div>
          <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4 xl:grid-cols-7">
            {RATE_POLICY_CURRENCIES.map((item) => {
              const latest = item === 'EGP' ? undefined : latestByCurrency.get(item);
              return <div key={item} className="rounded-xl border p-3 text-center"><p className="text-xs font-bold">{item}</p><p className="mt-1 font-mono text-sm">{item === 'EGP' ? '1.0000' : latest?.rate.toFixed(4) ?? '—'}</p><p className="text-[10px] text-muted-foreground">{item === 'EGP' ? 'Base' : latest?.effective_date ?? 'No rate'}</p></div>;
            })}
          </div>
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-sm"><thead><tr><th className="p-2 text-start">Currency</th><th className="p-2 text-start">Rate to EGP</th><th className="p-2 text-start">Effective</th><th className="p-2 text-start">Source</th></tr></thead><tbody>{rates.map((item) => <tr key={item.id} className="border-t"><td className="p-2 font-bold">{item.from_currency}</td><td className="p-2 font-mono">{item.rate.toFixed(4)}</td><td className="p-2">{item.effective_date}</td><td className="p-2"><Badge tone="neutral">{item.source}</Badge></td></tr>)}</tbody></table>
          </div>
        </CardContent>
      </Card>
      <AdaptiveFormSurface
        open={formOpen}
        onOpenChange={setFormOpen}
        title={ar ? 'إضافة سعر صرف' : 'Add exchange rate'}
        description={ar ? 'يسري على الإدخالات الجديدة فقط؛ لا يعيد حساب المعاملات التاريخية.' : 'Applies to new entry assistance only; historical transactions are not recalculated.'}
        closeLabel={ar ? 'إغلاق' : 'Close'}
        cancelLabel={ar ? 'إلغاء' : 'Cancel'}
        submitLabel={ar ? 'حفظ السعر' : 'Save rate'}
        onSubmit={createRate}
        error={error ? <p role="alert" className="mb-3 rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</p> : undefined}
      >
        <div className="grid gap-4 sm:grid-cols-3">
          <label className="space-y-1 text-sm"><span>{ar ? 'العملة' : 'Currency'}</span><select className="min-h-11 w-full rounded-xl border bg-background px-3" value={currency} onChange={(event) => setCurrency(event.target.value as Exclude<Currency, 'EGP'>)}>{FOREIGN_CURRENCIES.map((item) => <option key={item}>{item}</option>)}</select></label>
          <label className="space-y-1 text-sm"><span>{ar ? 'السعر' : 'Rate'}</span><input type="number" min="0.0001" step="0.0001" className="min-h-11 w-full rounded-xl border bg-background px-3" value={rate} onChange={(event) => setRate(event.target.value)} /></label>
          <label className="space-y-1 text-sm"><span>{ar ? 'تاريخ السريان' : 'Effective date'}</span><input type="date" className="min-h-11 w-full rounded-xl border bg-background px-3" value={effectiveDate} onChange={(event) => setEffectiveDate(event.target.value)} /></label>
        </div>
      </AdaptiveFormSurface>
    </>
  );
}

export function getLatestFxRate(currency: Currency): number | null {
  if (currency === 'EGP') return 1;
  return loadExchangeRates().find((item) => item.from_currency === currency)?.rate ?? null;
}

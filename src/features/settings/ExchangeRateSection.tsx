/**
 * ExchangeRateSection — FX master rate table
 * ADR-001: rates are captured at transaction time. This panel lets the user
 * maintain a reference table of recent rates that can be looked up when
 * entering transactions (UI picks the latest rate for the chosen currency).
 *
 * Storage key: terranex.exchangeRates.v1
 */
import { todayIso } from '../../core/lib/dateUtils';
import React, { useState, useMemo } from 'react';
import { Plus, X, RefreshCw } from 'lucide-react';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import type { Currency, ExchangeRate } from '../../core/types/domain';

const STORAGE_KEY = 'terranex.exchangeRates.v1';
const CURRENCIES: Exclude<Currency, 'EGP'>[] = ['USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

function loadRates(): ExchangeRate[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (r): r is ExchangeRate =>
        r && typeof r.id === 'string' && typeof r.rate === 'number' && r.rate > 0,
    ).sort((a, b) => b.effective_date.localeCompare(a.effective_date));
  } catch {
    return [];
  }
}

function saveRates(rates: ExchangeRate[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(rates));
}

function makeId(): string {
  return `fx-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
}


interface FormState {
  currency: Exclude<Currency, 'EGP'>;
  rate: string;
  date: string;
}

const DEFAULT_FORM: FormState = { currency: 'USD', rate: '', date: todayIso() };

interface Props {
  locale: 'ar' | 'en';
}

export function ExchangeRateSection({ locale }: Props) {
  const ar = locale === 'ar';
  // Listen to storage events so multiple open tabs stay in sync (B4 fix)
  const [rates, setRates] = useState<ExchangeRate[]>(loadRates);
  React.useEffect(() => {
    function onStorage(e: StorageEvent) {
      if (e.key === STORAGE_KEY) setRates(loadRates());
    }
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState<FormState>(DEFAULT_FORM);
  const [error, setError] = useState('');

  // Latest rate per currency for quick reference
  const latestByCurrency = useMemo(() => {
    const map = new Map<string, ExchangeRate>();
    for (const r of [...rates].sort((a, b) => b.effective_date.localeCompare(a.effective_date))) {
      if (!map.has(r.from_currency)) map.set(r.from_currency, r);
    }
    return map;
  }, [rates]);

  function persist(next: ExchangeRate[]) {
    setRates(next);
    saveRates(next);
  }

  function handleAdd() {
    const rateNum = parseFloat(form.rate);
    if (!Number.isFinite(rateNum) || rateNum <= 0) {
      setError(ar ? 'أدخل سعر صرف موجب' : 'Enter a positive exchange rate');
      return;
    }
    if (!form.date) {
      setError(ar ? 'التاريخ مطلوب' : 'Date is required');
      return;
    }
    const entry: ExchangeRate = {
      id: makeId(),
      from_currency: form.currency,
      to_currency: 'EGP',
      rate: rateNum,
      effective_date: form.date,
      source: 'manual',
      created_at: new Date().toISOString(),
    };
    persist([entry, ...rates]);
    setForm(DEFAULT_FORM);
    setShowForm(false);
    setError('');
  }

  function handleDelete(id: string) {
    persist(rates.filter(r => r.id !== id));
  }

  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';

  return (
    <Card className="xl:col-span-3">
      <CardContent>
        <div className="mb-4 flex items-center justify-between gap-3">
          <div>
            <h3 className="text-lg font-bold">{ar ? 'أسعار الصرف (EGP)' : 'Exchange Rates (EGP)'}</h3>
            <p className="mt-0.5 text-sm text-muted-foreground">
              {ar
                ? 'سجل مرجعي لأسعار الصرف. كل معدل = 1 وحدة من العملة الأجنبية بالجنيه المصري. ADR-001: السعر يُدخل وقت المعاملة.'
                : 'Reference table for exchange rates. Each rate = 1 unit of foreign currency in EGP. ADR-001: rate is entered at transaction time.'}
            </p>
          </div>
          <Button variant="secondary" size="sm" onClick={() => { setShowForm(s => !s); setError(''); }}>
            <Plus className="h-4 w-4" /> {ar ? 'إضافة سعر' : 'Add Rate'}
          </Button>
        </div>

        {/* Quick summary — latest rate per currency */}
        <div className="mb-4 grid grid-cols-3 gap-2 sm:grid-cols-6">
          {CURRENCIES.map(ccy => {
            const latest = latestByCurrency.get(ccy);
            return (
              <div key={ccy} className={`rounded-xl border px-3 py-2.5 text-center ${latest ? 'border-border' : 'border-dashed border-border/50 opacity-50'}`}>
                <p className="text-xs font-bold text-muted-foreground">{ccy}</p>
                <p className="mt-0.5 text-sm font-bold">
                  {latest ? latest.rate.toFixed(2) : '—'}
                </p>
                {latest && (
                  <p className="text-[10px] text-muted-foreground">{latest.effective_date}</p>
                )}
              </div>
            );
          })}
        </div>

        {/* Add form */}
        {showForm && (
          <div className="mb-4 rounded-xl border border-border bg-muted/30 p-4">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-sm font-semibold">{ar ? 'إضافة سعر صرف جديد' : 'New Exchange Rate'}</p>
              <button onClick={() => setShowForm(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
              <div>
                <label className="mb-1 block text-xs font-medium">{ar ? 'العملة' : 'Currency'}</label>
                <select
                  className={ic}
                  value={form.currency}
                  onChange={e => setForm(f => ({ ...f, currency: e.target.value as Exclude<Currency, 'EGP'> }))}
                >
                  {CURRENCIES.map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium">
                  {ar ? `السعر (1 ${form.currency} = ? EGP)` : `Rate (1 ${form.currency} = ? EGP)`}
                </label>
                <input
                  type="number"
                  step="0.0001"
                  min="0.0001"
                  className={ic}
                  dir="ltr"
                  placeholder="e.g. 50.75"
                  value={form.rate}
                  onChange={e => setForm(f => ({ ...f, rate: e.target.value }))}
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium">{ar ? 'تاريخ السريان' : 'Effective Date'}</label>
                <input
                  type="date"
                  className={ic}
                  value={form.date}
                  onChange={e => setForm(f => ({ ...f, date: e.target.value }))}
                />
              </div>
            </div>
            {error && <p className="mt-2 text-xs text-danger">{error}</p>}
            <div className="mt-3 flex gap-2">
              <Button size="sm" onClick={handleAdd} className="flex-1">{ar ? 'حفظ السعر' : 'Save Rate'}</Button>
              <Button variant="ghost" size="sm" onClick={() => setShowForm(false)}>{ar ? 'إلغاء' : 'Cancel'}</Button>
            </div>
          </div>
        )}

        {/* Rates log */}
        {rates.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border py-8 text-center">
            <RefreshCw className="mx-auto mb-2 h-6 w-6 text-muted-foreground/40" />
            <p className="text-sm text-muted-foreground">
              {ar ? 'لا توجد أسعار مسجلة بعد. أضف أول سعر صرف.' : 'No rates recorded yet. Add your first rate.'}
            </p>
          </div>
        ) : (
          <div className="divide-y divide-border rounded-xl border border-border">
            <div className="grid grid-cols-5 gap-2 px-4 py-2 text-xs font-bold text-muted-foreground">
              <span>{ar ? 'العملة' : 'Currency'}</span>
              <span className="text-center">1 → EGP</span>
              <span className="text-center">{ar ? 'تاريخ السريان' : 'Effective Date'}</span>
              <span className="text-center">{ar ? 'المصدر' : 'Source'}</span>
              <span />
            </div>
            {rates.map(r => (
              <div key={r.id} className="grid grid-cols-5 items-center gap-2 px-4 py-3">
                <span className="text-sm font-bold">{r.from_currency}</span>
                <span className="text-center text-sm font-mono font-bold">{r.rate.toFixed(4)}</span>
                <span className="text-center text-xs text-muted-foreground">{r.effective_date}</span>
                <span className="text-center">
                  <Badge tone="neutral">{r.source}</Badge>
                </span>
                <div className="flex justify-end">
                  <button
                    onClick={() => handleDelete(r.id)}
                    className="rounded p-1 text-muted-foreground hover:text-danger"
                    aria-label="delete"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * Utility: get the latest stored rate for a given currency.
 * Used by TransactionForm to pre-fill the fx_rate field.
 */
export function getLatestFxRate(currency: Currency): number | null {
  if (currency === 'EGP') return 1;
  const rates = loadRates();
  const latest = rates
    .filter(r => r.from_currency === currency)
    .sort((a, b) => b.effective_date.localeCompare(a.effective_date))[0];
  return latest?.rate ?? null;
}

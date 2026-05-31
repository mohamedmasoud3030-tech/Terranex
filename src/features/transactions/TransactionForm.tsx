import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import type { TransactionInput } from './storage';
import type { Transaction, Currency, TransactionDirection, TransactionCategory } from '../../core/types/domain';

const CATEGORIES: { id: TransactionCategory; ar: string; group: string }[] = [
  { id: 'acquisition', ar: 'اقتناء أصل', group: 'عام' },
  { id: 'sale', ar: 'بيع', group: 'عام' },
  { id: 'development_cost', ar: 'تكلفة تطوير', group: 'عقاري' },
  { id: 'maintenance', ar: 'صيانة', group: 'عام' },
  { id: 'salary', ar: 'رواتب', group: 'عام' },
  { id: 'tax', ar: 'ضرائب ورسوم', group: 'عام' },
  { id: 'legal_fee', ar: 'رسوم قانونية', group: 'عام' },
  { id: 'transport', ar: 'مواصلات ونقل', group: 'عام' },
  { id: 'utility', ar: 'مرافق', group: 'عام' },
  { id: 'seed_input', ar: 'مدخلات بذور', group: 'زراعي' },
  { id: 'fertilizer', ar: 'أسمدة', group: 'زراعي' },
  { id: 'harvest_revenue', ar: 'إيرادات الحصاد', group: 'زراعي' },
  { id: 'irrigation', ar: 'ري', group: 'زراعي' },
  { id: 'feed', ar: 'أعلاف', group: 'حيواني' },
  { id: 'veterinary', ar: 'رعاية بيطرية', group: 'حيواني' },
  { id: 'vaccination', ar: 'تحصينات', group: 'حيواني' },
  { id: 'livestock_purchase', ar: 'شراء مواشٍ', group: 'حيواني' },
  { id: 'livestock_sale', ar: 'بيع مواشٍ', group: 'حيواني' },
  { id: 'loan_disbursement', ar: 'صرف قرض', group: 'تمويل' },
  { id: 'loan_repayment', ar: 'سداد قرض', group: 'تمويل' },
  { id: 'interest', ar: 'فوائد', group: 'تمويل' },
  { id: 'dividend', ar: 'أرباح موزعة', group: 'تمويل' },
  { id: 'other', ar: 'أخرى', group: 'عام' },
];

const CURRENCIES: Currency[] = ['EGP', 'USD', 'SAR', 'AED', 'EUR', 'GBP'];

interface Props {
  projectId: string;
  initial?: Partial<Transaction>;
  onSubmit: (input: TransactionInput) => void;
  onCancel: () => void;
  loading?: boolean;
}

export function TransactionForm({ projectId, initial, onSubmit, onCancel, loading }: Props) {
  const [direction, setDirection] = useState<TransactionDirection>(initial?.direction ?? 'expense');
  const [category, setCategory] = useState<TransactionCategory>(initial?.category ?? 'other');
  const [amount, setAmount] = useState(String(initial?.amount ?? ''));
  const [currency, setCurrency] = useState<Currency>(initial?.currency ?? 'EGP');
  const [fx_rate, setFxRate] = useState(String(initial?.fx_rate ?? 1));
  const [transaction_date, setDate] = useState(initial?.transaction_date ?? new Date().toISOString().slice(0, 10));
  const [description, setDescription] = useState(initial?.description ?? '');
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const [errors, setErrors] = useState<Record<string, string>>({});

  const amountNum = Number(amount);
  const fxNum = Number(fx_rate);
  const amountEgp = amountNum * fxNum;

  function validate(): boolean {
    const e: Record<string, string> = {};
    if (!Number.isFinite(amountNum) || amountNum <= 0) e.amount = 'أدخل مبلغاً صحيحاً أكبر من صفر';
    if (!Number.isFinite(fxNum) || fxNum <= 0) e.fx = 'أدخل سعر صرف صحيحاً أكبر من صفر';
    if (!transaction_date) e.date = 'التاريخ مطلوب';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!validate()) return;
    onSubmit({
      project_id: projectId,
      direction,
      category,
      amount: amountNum,
      currency,
      fx_rate: fxNum,
      amount_egp: amountEgp,
      transaction_date,
      description: description || undefined,
      notes: notes || undefined,
    });
  }

  const inputClass = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const labelClass = 'block text-sm font-medium text-foreground mb-1';
  const errorClass = 'mt-1 text-xs text-danger';

  return (
    <form onSubmit={handleSubmit} className="space-y-4" noValidate>
      {/* Direction toggle */}
      <div>
        <label className={labelClass}>الاتجاه</label>
        <div className="flex gap-2">
          {(['income', 'expense'] as const).map((d) => (
            <button
              key={d}
              type="button"
              onClick={() => setDirection(d)}
              className={`flex-1 rounded-xl border py-2.5 text-sm font-semibold transition ${
                direction === d
                  ? d === 'income'
                    ? 'border-success bg-success/10 text-success'
                    : 'border-danger bg-danger/10 text-danger'
                  : 'border-border text-muted-foreground hover:bg-muted'
              }`}
            >
              {d === 'income' ? '↑ إيراد' : '↓ مصروف'}
            </button>
          ))}
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={labelClass}>المبلغ *</label>
          <input
            type="number"
            min="0"
            step="0.01"
            className={inputClass}
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
          />
          {errors.amount && <p className={errorClass}>{errors.amount}</p>}
        </div>
        <div>
          <label className={labelClass}>العملة</label>
          <select className={inputClass} value={currency} onChange={(e) => setCurrency(e.target.value as Currency)}>
            {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
      </div>

      {currency !== 'EGP' && (
        <div>
          <label className={labelClass}>سعر الصرف (1 {currency} = ? EGP)</label>
          <input type="number" min="0" step="0.001" className={inputClass} value={fx_rate} onChange={(e) => setFxRate(e.target.value)} />
          {errors.fx && <p className={errorClass}>{errors.fx}</p>}
          <p className="mt-1 text-xs text-muted-foreground">المكافئ بالجنيه: {amountEgp.toLocaleString('ar-EG')} EGP</p>
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={labelClass}>التاريخ *</label>
          <input type="date" className={inputClass} value={transaction_date} onChange={(e) => setDate(e.target.value)} />
          {errors.date && <p className={errorClass}>{errors.date}</p>}
        </div>
        <div>
          <label className={labelClass}>التصنيف</label>
          <select className={inputClass} value={category} onChange={(e) => setCategory(e.target.value as TransactionCategory)}>
            {CATEGORIES.map((c) => <option key={c.id} value={c.id}>{c.group} — {c.ar}</option>)}
          </select>
        </div>
      </div>

      <div>
        <label className={labelClass}>الوصف</label>
        <input className={inputClass} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="وصف موجز للمعاملة…" />
      </div>

      <div>
        <label className={labelClass}>ملاحظات</label>
        <textarea className={inputClass} rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </div>

      <div className="flex flex-col gap-3 pt-2 min-[360px]:flex-row min-[360px]:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button
          type="submit"
          disabled={loading}
          className={direction === 'income' ? 'bg-success hover:bg-success/90' : 'bg-danger hover:bg-danger/90'}
        >
          {loading ? 'جار الحفظ…' : direction === 'income' ? 'حفظ الإيراد' : 'حفظ المصروف'}
        </Button>
      </div>
    </form>
  );
}

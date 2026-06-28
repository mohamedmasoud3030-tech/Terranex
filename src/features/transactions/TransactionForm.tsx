import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormHint, FormLabel, SelectInput, TextArea, TextInput } from '../../components/ui/FormControls';
import type { Transaction, Currency, TransactionDirection, TransactionCategory } from '../../core/types/domain';
import { useDocuments } from '../documents/hooks';
import { usePartners } from '../partners/hooks';
import type { DeferredExpenseTransactionInput } from './deferredExpenseWorkflow';

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
  onSubmit: (input: DeferredExpenseTransactionInput) => void;
  onCancel: () => void;
  loading?: boolean;
}

export function TransactionForm({ projectId, initial, onSubmit, onCancel, loading }: Props) {
  const { partners } = usePartners();
  const { documents } = useDocuments(projectId);
  const [direction, setDirection] = useState<TransactionDirection>(initial?.direction ?? 'expense');
  const [category, setCategory] = useState<TransactionCategory>(initial?.category ?? 'other');
  const [amount, setAmount] = useState(String(initial?.amount ?? ''));
  const [currency, setCurrency] = useState<Currency>(initial?.currency ?? 'EGP');
  const [fx_rate, setFxRate] = useState(String(initial?.fx_rate ?? 1));
  const [partner_id, setPartnerId] = useState(initial?.partner_id ?? '');
  const [document_id, setDocumentId] = useState(initial?.document_id ?? '');
  const [transaction_date, setDate] = useState(initial?.transaction_date ?? new Date().toISOString().slice(0, 10));
  const [description, setDescription] = useState(initial?.description ?? '');
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const [createPayableObligation, setCreatePayableObligation] = useState(false);
  const [payableDueDate, setPayableDueDate] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});

  const amountNum = Number(amount);
  const fxNum = Number(fx_rate);
  const effectiveFxRate = currency === 'EGP' ? 1 : fxNum;
  const amountEgp = amountNum * effectiveFxRate;
  const availableDocuments = documents.filter((document) => !document.transaction_id || document.transaction_id === initial?.id);
  const isDeferredExpense = direction === 'expense' && createPayableObligation;

  function validate(): boolean {
    const e: Record<string, string> = {};
    if (!partner_id) e.partner = 'اختر الطرف أو الشريك المرتبط بالمعاملة';
    if (!document_id) e.document = 'اختر الوثيقة الداعمة للمعاملة';
    if (!Number.isFinite(amountNum) || amountNum <= 0) e.amount = 'أدخل مبلغاً صحيحاً أكبر من صفر';
    if (currency !== 'EGP' && (!Number.isFinite(fxNum) || fxNum <= 0)) e.fx = 'أدخل سعر صرف صحيحاً أكبر من صفر';
    if (!transaction_date) e.date = 'التاريخ مطلوب';
    if (isDeferredExpense && !payableDueDate) e.payableDueDate = 'أدخل تاريخ استحقاق الذمة الدائنة';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!validate()) return;
    onSubmit({
      project_id: projectId,
      partner_id,
      document_id,
      direction,
      category,
      amount: amountNum,
      currency,
      fx_rate: effectiveFxRate,
      amount_egp: amountEgp,
      transaction_date,
      description: description || undefined,
      notes: notes || undefined,
      create_payable_obligation: isDeferredExpense || undefined,
      payable_due_date: isDeferredExpense ? payableDueDate : undefined,
    });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4" noValidate>
      <FormField>
        <FormLabel>الاتجاه</FormLabel>
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
      </FormField>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="transaction-amount">المبلغ *</FormLabel>
          <TextInput id="transaction-amount" type="number" min="0" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
          {errors.amount && <FormError>{errors.amount}</FormError>}
        </FormField>
        <FormField>
          <FormLabel htmlFor="transaction-currency">العملة</FormLabel>
          <SelectInput id="transaction-currency" value={currency} onChange={(e) => setCurrency(e.target.value as Currency)}>
            {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </SelectInput>
        </FormField>
      </div>

      {currency !== 'EGP' && (
        <FormField>
          <FormLabel htmlFor="transaction-fx-rate">سعر الصرف (1 {currency} = ? EGP)</FormLabel>
          <TextInput id="transaction-fx-rate" type="number" min="0" step="0.001" value={fx_rate} onChange={(e) => setFxRate(e.target.value)} />
          {errors.fx && <FormError>{errors.fx}</FormError>}
          <FormHint>المكافئ بالجنيه: {amountEgp.toLocaleString('ar-EG')} EGP</FormHint>
        </FormField>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="transaction-partner">الطرف أو الشريك *</FormLabel>
          <SelectInput id="transaction-partner" value={partner_id} onChange={(e) => setPartnerId(e.target.value)}>
            <option value="">اختر الطرف…</option>
            {partners.map((partner) => <option key={partner.id} value={partner.id}>{partner.name_ar}</option>)}
          </SelectInput>
          {errors.partner && <FormError>{errors.partner}</FormError>}
        </FormField>
        <FormField>
          <FormLabel htmlFor="transaction-document">الوثيقة الداعمة *</FormLabel>
          <SelectInput id="transaction-document" value={document_id} onChange={(e) => setDocumentId(e.target.value)}>
            <option value="">اختر الوثيقة…</option>
            {availableDocuments.map((document) => <option key={document.id} value={document.id}>{document.title_ar}</option>)}
          </SelectInput>
          {errors.document && <FormError>{errors.document}</FormError>}
          {availableDocuments.length === 0 && <FormHint>أضف مستندًا مرتبطًا بالمشروع قبل تسجيل المعاملة.</FormHint>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="transaction-date">التاريخ *</FormLabel>
          <TextInput id="transaction-date" type="date" value={transaction_date} onChange={(e) => setDate(e.target.value)} />
          {errors.date && <FormError>{errors.date}</FormError>}
        </FormField>
        <FormField>
          <FormLabel htmlFor="transaction-category">التصنيف</FormLabel>
          <SelectInput id="transaction-category" value={category} onChange={(e) => setCategory(e.target.value as TransactionCategory)}>
            {CATEGORIES.map((c) => <option key={c.id} value={c.id}>{c.group} — {c.ar}</option>)}
          </SelectInput>
        </FormField>
      </div>

      {direction === 'expense' && (
        <div className="rounded-xl border border-border bg-muted/30 p-3">
          <label className="flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              checked={createPayableObligation}
              onChange={(e) => setCreatePayableObligation(e.target.checked)}
              className="mt-1 h-4 w-4"
            />
            <span>
              <span className="block text-sm font-semibold text-foreground">هذا مصروف آجل لم يتم سداده بعد</span>
              <span className="mt-1 block text-xs leading-5 text-muted-foreground">سيُحفظ المصروف وتُنشأ ذمة دائنة مرتبطة تلقائيًا بنفس المشروع والطرف والوثيقة.</span>
            </span>
          </label>
          {createPayableObligation && (
            <FormField className="mt-3">
              <FormLabel htmlFor="payable-due-date">تاريخ استحقاق الذمة الدائنة *</FormLabel>
              <TextInput id="payable-due-date" type="date" value={payableDueDate} onChange={(e) => setPayableDueDate(e.target.value)} />
              {errors.payableDueDate && <FormError>{errors.payableDueDate}</FormError>}
            </FormField>
          )}
        </div>
      )}

      <FormField>
        <FormLabel htmlFor="transaction-description">الوصف</FormLabel>
        <TextInput id="transaction-description" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="وصف موجز للمعاملة…" />
      </FormField>

      <FormField>
        <FormLabel htmlFor="transaction-notes">ملاحظات</FormLabel>
        <TextArea id="transaction-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </FormField>

      <div className="flex flex-col gap-3 pt-2 min-[360px]:flex-row min-[360px]:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit" disabled={loading} className={direction === 'income' ? 'bg-success hover:bg-success/90' : 'bg-danger hover:bg-danger/90'}>
          {loading ? 'جار الحفظ…' : isDeferredExpense ? 'حفظ المصروف وإنشاء الذمة' : direction === 'income' ? 'حفظ الإيراد' : 'حفظ المصروف'}
        </Button>
      </div>
    </form>
  );
}

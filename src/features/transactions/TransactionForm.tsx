import React, { useState } from 'react';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormHint, FormLabel } from '../../components/ui/FormControls';
import type { Transaction, Currency, TransactionDirection, TransactionCategory } from '../../core/types/domain';
import { useDocuments } from '../documents/hooks';
import { usePartners } from '../partners/hooks';
import type { DeferredExpenseTransactionInput } from './deferredExpenseWorkflow';
import { transactionSchema, type TransactionFormValues } from '../../core/lib/validation';
import { useI18n } from '../../core/i18n/context';

const CATEGORIES: { id: TransactionCategory; ar: string; en: string; group: string }[] = [
  { id: 'acquisition', ar: 'اقتناء أصل', en: 'Acquisition', group: 'عام' },
  { id: 'sale', ar: 'بيع', en: 'Sale', group: 'عام' },
  { id: 'development_cost', ar: 'تكلفة تطوير', en: 'Development', group: 'عقاري' },
  { id: 'maintenance', ar: 'صيانة', en: 'Maintenance', group: 'عام' },
  { id: 'salary', ar: 'رواتب', en: 'Salary', group: 'عام' },
  { id: 'tax', ar: 'ضرائب ورسوم', en: 'Tax', group: 'عام' },
  { id: 'legal_fee', ar: 'رسوم قانونية', en: 'Legal', group: 'عام' },
  { id: 'transport', ar: 'مواصلات ونقل', en: 'Transport', group: 'عام' },
  { id: 'utility', ar: 'مرافق', en: 'Utility', group: 'عام' },
  { id: 'seed_input', ar: 'مدخلات بذور', en: 'Seeds', group: 'زراعي' },
  { id: 'fertilizer', ar: 'أسمدة', en: 'Fertilizer', group: 'زراعي' },
  { id: 'harvest_revenue', ar: 'إيرادات الحصاد', en: 'Harvest', group: 'زراعي' },
  { id: 'irrigation', ar: 'ري', en: 'Irrigation', group: 'زراعي' },
  { id: 'feed', ar: 'أعلاف', en: 'Feed', group: 'حيواني' },
  { id: 'veterinary', ar: 'رعاية بيطرية', en: 'Vet', group: 'حيواني' },
  { id: 'vaccination', ar: 'تحصينات', en: 'Vaccination', group: 'حيواني' },
  { id: 'livestock_purchase', ar: 'شراء مواشٍ', en: 'Livestock Buy', group: 'حيواني' },
  { id: 'livestock_sale', ar: 'بيع مواشٍ', en: 'Livestock Sale', group: 'حيواني' },
  { id: 'loan_disbursement', ar: 'صرف قرض', en: 'Loan', group: 'تمويل' },
  { id: 'loan_repayment', ar: 'سداد قرض', en: 'Repayment', group: 'تمويل' },
  { id: 'interest', ar: 'فوائد', en: 'Interest', group: 'تمويل' },
  { id: 'dividend', ar: 'أرباح موزعة', en: 'Dividend', group: 'تمويل' },
  { id: 'other', ar: 'أخرى', en: 'Other', group: 'عام' },
];

const CURRENCIES: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

interface Props {
  projectId: string;
  initial?: Partial<Transaction>;
  onSubmit: (input: DeferredExpenseTransactionInput) => void;
  onCancel: () => void;
  loading?: boolean;
}

export function TransactionForm({ projectId, initial, onSubmit, onCancel, loading }: Props) {
  const { t, locale } = useI18n();
  const { partners } = usePartners();
  const { documents } = useDocuments(projectId);

  const {
    register,
    handleSubmit,
    watch,
    control,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<TransactionFormValues>({
    resolver: zodResolver(transactionSchema) as any,
    defaultValues: {
      project_id: projectId,
      direction: initial?.direction ?? 'expense',
      category: initial?.category ?? 'other',
      amount: initial?.amount ?? undefined,
      currency: initial?.currency ?? 'EGP',
      fx_rate: initial?.fx_rate ?? 1,
      transaction_date: initial?.transaction_date ?? new Date().toISOString().slice(0, 10),
      partner_id: initial?.partner_id ?? '',
      document_id: initial?.document_id ?? '',
      description: initial?.description ?? '',
      notes: initial?.notes ?? '',
    },
    mode: 'onBlur',
  });

  const direction = watch('direction');
  const currency = watch('currency');
  const amount = watch('amount') || 0;
  const fx_rate = watch('fx_rate') || 1;
  const effectiveFx = currency === 'EGP' ? 1 : fx_rate;
  const amountEgp = Number(amount) * effectiveFx;

  const [createPayableObligation, setCreatePayableObligation] = useState(false);
  const [payableDueDate, setPayableDueDate] = useState('');

  const availableDocuments = documents.filter((d) => !d.transaction_id || d.transaction_id === initial?.id);

  // auto force fx_rate = 1 when EGP
  React.useEffect(() => {
    if (currency === 'EGP') {
      setValue('fx_rate', 1, { shouldValidate: true });
    }
  }, [currency, setValue]);

  const submit = (values: TransactionFormValues) => {
    if (direction === 'expense' && createPayableObligation && !payableDueDate) {
      alert(locale === 'ar' ? 'أدخل تاريخ استحقاق الذمة الدائنة' : 'Enter payable due date');
      return;
    }
    onSubmit({
      project_id: values.project_id,
      partner_id: values.partner_id || undefined,
      document_id: values.document_id || undefined,
      direction: values.direction,
      category: values.category as TransactionCategory,
      amount: Number(values.amount),
      currency: values.currency as Currency,
      fx_rate: values.currency === 'EGP' ? 1 : Number(values.fx_rate),
      amount_egp: Number(values.amount) * (values.currency === 'EGP' ? 1 : Number(values.fx_rate)),
      transaction_date: values.transaction_date,
      description: values.description || undefined,
      notes: values.notes || undefined,
      create_payable_obligation: createPayableObligation || undefined,
      payable_due_date: createPayableObligation ? payableDueDate : undefined,
    });
  };

  return (
    <form onSubmit={handleSubmit(submit)} className="space-y-4" noValidate>
      {/* Direction */}
      <FormField>
        <FormLabel>{t('transaction_direction')}</FormLabel>
        <Controller
          name="direction"
          control={control}
          render={({ field }) => (
            <div className="flex gap-2">
              {( ['income','expense'] as const).map(d => (
                <button
                  key={d}
                  type="button"
                  onClick={() => field.onChange(d)}
                  className={`flex-1 rounded-xl border py-2.5 text-sm font-semibold transition ${
                    field.value === d
                      ? d === 'income'
                        ? 'border-success bg-success/10 text-success'
                        : 'border-danger bg-danger/10 text-danger'
                      : 'border-border text-muted-foreground hover:bg-muted'
                  }`}
                >
                  {d === 'income' ? `↑ ${t('transaction_direction_income')}` : `↓ ${t('transaction_direction_expense')}`}
                </button>
              ))}
            </div>
          )}
        />
        {errors.direction && <FormError>{errors.direction.message}</FormError>}
      </FormField>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="tx-amount">{t('transaction_amount')} *</FormLabel>
          <input
            id="tx-amount"
            type="number"
            step="0.01"
            min="0"
            {...register('amount', { valueAsNumber: true })}
            className="w-full rounded-xl border border-border bg-background px-3 py-2.5 ltr"
            dir="ltr"
            placeholder="0.00"
          />
          {errors.amount && <FormError>{errors.amount.message}</FormError>}
        </FormField>

        <FormField>
          <FormLabel>{t('transaction_currency')}</FormLabel>
          <select {...register('currency')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5">
            {CURRENCIES.map(c => <option key={c} value={c}>{c} — {t(`currency_${c}` as any)}</option>)}
          </select>
          {errors.currency && <FormError>{errors.currency.message}</FormError>}
        </FormField>
      </div>

      {currency !== 'EGP' && (
        <FormField>
          <FormLabel>{t('transaction_fx_rate')}</FormLabel>
          <input
            type="number"
            step="0.0001"
            min="0"
            {...register('fx_rate', { valueAsNumber: true })}
            className="w-full rounded-xl border border-border bg-background px-3 py-2.5 ltr"
            dir="ltr"
          />
          {errors.fx_rate && <FormError>{errors.fx_rate.message}</FormError>}
          <FormHint>المكافئ: {amountEgp.toLocaleString('ar-EG')} EGP</FormHint>
        </FormField>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{t('transaction_counterparty')} *</FormLabel>
          <select {...register('partner_id')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5">
            <option value="">{locale==='ar' ? 'اختر الطرف…' : 'Choose…'}</option>
            {partners.map(p => <option key={p.id} value={p.id}>{locale==='ar' ? p.name_ar : (p.name_en || p.name_ar)}</option>)}
          </select>
          {errors.partner_id && <FormError>{errors.partner_id.message}</FormError>}
        </FormField>

        <FormField>
          <FormLabel>{t('transaction_document')} *</FormLabel>
          <select {...register('document_id')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5">
            <option value="">{locale==='ar' ? 'اختر الوثيقة…' : 'Choose…'}</option>
            {availableDocuments.map(d => <option key={d.id} value={d.id}>{d.title_ar}</option>)}
          </select>
          {errors.document_id && <FormError>{errors.document_id.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{t('transaction_date')} *</FormLabel>
          <input type="date" {...register('transaction_date')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5" />
          {errors.transaction_date && <FormError>{errors.transaction_date.message}</FormError>}
        </FormField>

        <FormField>
          <FormLabel>{t('transaction_category')}</FormLabel>
          <select {...register('category')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5">
            {CATEGORIES.map(c => (
              <option key={c.id} value={c.id}>{c.group} — {locale==='ar'?c.ar:c.en}</option>
            ))}
          </select>
          {errors.category && <FormError>{errors.category.message}</FormError>}
        </FormField>
      </div>

      {direction === 'expense' && (
        <div className="rounded-xl border border-border bg-muted/30 p-3">
          <label className="flex items-start gap-3 cursor-pointer">
            <input type="checkbox" checked={createPayableObligation} onChange={e => setCreatePayableObligation(e.target.checked)} className="mt-1" />
            <span className="text-sm">
              <b>{locale==='ar' ? 'مصروف آجل لم يُسدد بعد' : 'Deferred expense'}</b>
              <br />
              <span className="text-xs text-muted-foreground">
                {locale==='ar' ? 'سيُنشئ ذمة دائنة تلقائياً' : 'Will auto-create a payable obligation'}
              </span>
            </span>
          </label>
          {createPayableObligation && (
            <div className="mt-3">
              <FormLabel>تاريخ استحقاق الذمة *</FormLabel>
              <input
                type="date"
                value={payableDueDate}
                onChange={e => setPayableDueDate(e.target.value)}
                className="w-full rounded-xl border border-border bg-background px-3 py-2.5 mt-1"
                required={createPayableObligation}
              />
            </div>
          )}
        </div>
      )}

      <FormField>
        <FormLabel>{t('transaction_notes')}</FormLabel>
        <textarea {...register('description')} rows={2} className="w-full rounded-xl border border-border bg-background px-3 py-2.5" placeholder={locale==='ar' ? 'وصف اختياري…' : 'Optional…'} />
      </FormField>

      <input type="hidden" {...register('project_id')} />

      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel}>{t('action_cancel')}</Button>
        <Button type="submit" disabled={loading || isSubmitting} className={direction === 'income' ? 'bg-success hover:bg-success/90' : ''}>
          {loading || isSubmitting ? (locale==='ar' ? 'جار الحفظ…' : 'Saving…') : t('action_save')}
        </Button>
      </div>

            {/* RHF debug — error summary */}
      {Object.keys(errors).length > 0 && (
        <div className="rounded-xl bg-danger/5 border border-danger/20 p-3 text-xs text-danger" dir="rtl">
          {Object.entries(errors).map(([k, err]: any) => (
            <div key={k}>• {k}: {err?.message}</div>
          ))}
        </div>
      )}
    </form>
  );
}

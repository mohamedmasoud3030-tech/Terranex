import { useState, type FormEvent } from 'react';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import type { AdjustmentReason, Asset } from '../../core/types/domain';
import type { StockAdjustmentInput } from '../events/storage';
import { validateStockAdjustment } from './model';

const reasonLabels: Record<AdjustmentReason, { ar: string; en: string }> = {
  opening_balance: { ar: 'رصيد افتتاحي', en: 'Opening balance' },
  data_correction: { ar: 'تصحيح بيانات', en: 'Data correction' },
  external_audit: { ar: 'مراجعة خارجية', en: 'External audit' },
  reconciliation: { ar: 'مطابقة', en: 'Reconciliation' },
  other: { ar: 'أخرى', en: 'Other' },
};

interface StockAdjustmentFormProps {
  formId: string;
  asset: Asset;
  currentQuantity: number;
  locale: 'ar' | 'en';
  serverError?: string | null;
  onReview: (input: StockAdjustmentInput) => void;
}

export function StockAdjustmentForm({
  formId,
  asset,
  currentQuantity,
  locale,
  serverError,
  onReview,
}: StockAdjustmentFormProps) {
  const currentValue = asset.current_value_egp ?? asset.acquisition_cost_egp;
  const [quantityAfter, setQuantityAfter] = useState(String(currentQuantity));
  const [valueAfter, setValueAfter] = useState(String(currentValue));
  const [reason, setReason] = useState<AdjustmentReason>('data_correction');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [notes, setNotes] = useState('');
  const [errors, setErrors] = useState<string[]>([]);

  function submit(event: FormEvent) {
    event.preventDefault();
    const input: StockAdjustmentInput = {
      asset_id: asset.id,
      project_id: asset.project_id,
      adjustment_date: date,
      quantity_before: currentQuantity,
      quantity_after: Number(quantityAfter),
      value_egp_before: currentValue,
      value_egp_after: Number(valueAfter),
      reason,
      notes: notes.trim() || undefined,
    };
    const messages = validateStockAdjustment(currentQuantity, input);
    const nextErrors = messages.map((message) =>
      locale === 'ar' ? adjustmentErrorAr(message) : adjustmentErrorEn(message),
    );
    setErrors(nextErrors);
    if (messages.length) return;
    onReview(input);
  }

  return (
    <form id={formId} onSubmit={submit} className="space-y-4" noValidate>
      <FormErrorSummary
        serverError={[...errors, ...(serverError ? [serverError] : [])].join(' ')}
        title={locale === 'ar' ? 'راجع بيانات التصحيح' : 'Review adjustment data'}
      />
      <div className="rounded-2xl border bg-muted/30 p-4">
        <p className="text-sm font-semibold">{locale === 'ar' ? asset.name_ar : asset.name_en}</p>
        <dl className="mt-3 grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt className="text-muted-foreground">{locale === 'ar' ? 'الكمية قبل' : 'Quantity before'}</dt>
            <dd className="font-bold">{currentQuantity} {asset.unit ?? ''}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">{locale === 'ar' ? 'القيمة قبل' : 'Value before'}</dt>
            <dd className="font-bold">{currentValue.toLocaleString()} EGP</dd>
          </div>
        </dl>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor={`${formId}-quantity-after`}>{locale === 'ar' ? 'الكمية بعد' : 'Quantity after'}</FormLabel>
          <input id={`${formId}-quantity-after`} type="number" min="0" value={quantityAfter} onChange={(event) => setQuantityAfter(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" />
        </FormField>
        <FormField>
          <FormLabel htmlFor={`${formId}-value-after`}>{locale === 'ar' ? 'القيمة بعد EGP' : 'Value after EGP'}</FormLabel>
          <input id={`${formId}-value-after`} type="number" min="0" step="0.01" value={valueAfter} onChange={(event) => setValueAfter(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" />
        </FormField>
      </div>
      <FormField>
        <FormLabel htmlFor={`${formId}-reason`}>{locale === 'ar' ? 'سبب التصحيح' : 'Adjustment reason'}</FormLabel>
        <select id={`${formId}-reason`} value={reason} onChange={(event) => setReason(event.target.value as AdjustmentReason)} className="min-h-11 w-full rounded-xl border bg-background px-3">
          {(Object.keys(reasonLabels) as AdjustmentReason[]).map((item) => (
            <option key={item} value={item}>{reasonLabels[item][locale]}</option>
          ))}
        </select>
      </FormField>
      <FormField>
        <FormLabel htmlFor={`${formId}-date`}>{locale === 'ar' ? 'التاريخ' : 'Date'}</FormLabel>
        <input id={`${formId}-date`} type="date" value={date} onChange={(event) => setDate(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" />
      </FormField>
      <FormField>
        <FormLabel htmlFor={`${formId}-notes`}>{locale === 'ar' ? 'ملاحظات المراجعة' : 'Audit notes'}</FormLabel>
        <textarea id={`${formId}-notes`} rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} className="w-full rounded-xl border bg-background px-3 py-2.5" />
      </FormField>
    </form>
  );
}

function adjustmentErrorAr(message: string) {
  if (message === 'quantity_before_must_match_live_balance') return 'الكمية السابقة يجب أن تطابق الرصيد الحي.';
  if (message === 'quantity_after_must_be_non_negative') return 'الكمية الجديدة يجب أن تكون صفرًا أو أكثر.';
  if (message === 'value_before_must_be_non_negative') return 'القيمة السابقة غير صالحة.';
  if (message === 'value_after_must_be_non_negative') return 'القيمة الجديدة يجب أن تكون صفرًا أو أكثر.';
  return 'تاريخ التصحيح مطلوب.';
}

function adjustmentErrorEn(message: string) {
  if (message === 'quantity_before_must_match_live_balance') return 'Previous quantity must match the live balance.';
  if (message === 'quantity_after_must_be_non_negative') return 'New quantity must be zero or greater.';
  if (message === 'value_before_must_be_non_negative') return 'Previous value is invalid.';
  if (message === 'value_after_must_be_non_negative') return 'New value must be zero or greater.';
  return 'Adjustment date is required.';
}

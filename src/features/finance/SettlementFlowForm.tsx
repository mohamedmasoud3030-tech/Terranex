import { useMemo, useState, type FormEvent } from 'react';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import type { Document, Obligation } from '../../core/types/domain';
import { formatEgp } from '../../core/lib/profitability';
import {
  buildSettlementAllocationFormPlans,
  getCompatibleSettleableObligations,
  getObligationRemainingEgp,
  getSettlementAllocationPlanTotal,
} from '../settlements/allocationForm';
import type { RecordSettlementWithAllocationsInput } from '../settlements/workflow';
import type { SettlementPaymentMethod } from '../settlements/types';
import { FINANCE_ATOMICITY_NOTICE } from './financeWriteBoundary';

interface SettlementFlowFormProps {
  formId: string;
  obligations: Obligation[];
  documents: Document[];
  anchorId?: string;
  locale: 'ar' | 'en';
  serverError?: string | null;
  onSubmit: (input: RecordSettlementWithAllocationsInput) => void | Promise<void>;
}

export function SettlementFlowForm({ formId, obligations, documents, anchorId, locale, serverError, onSubmit }: SettlementFlowFormProps) {
  const settleable = obligations.filter((item) => item.status === 'open' || item.status === 'partial');
  const [selectedAnchorId, setSelectedAnchorId] = useState(anchorId ?? settleable[0]?.id ?? '');
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState<SettlementPaymentMethod>('bank_transfer');
  const [reference, setReference] = useState('');
  const [receiptId, setReceiptId] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const anchor = settleable.find((item) => item.id === selectedAnchorId);
  const candidates = useMemo(
    () => getCompatibleSettleableObligations(anchor, settleable),
    [anchor, settleable],
  );
  const previewPlans = candidates.flatMap((item) => {
    const amount = Number(amounts[item.id]);
    return Number.isFinite(amount) && amount > 0 ? [{ obligation_id: item.id, allocated_amount_egp: amount }] : [];
  });
  const total = getSettlementAllocationPlanTotal(previewPlans);
  const receipts = documents.filter((document) =>
    document.type === 'receipt'
    && (!anchor?.project_id || document.project_id === anchor.project_id)
    && (!anchor || !document.partner_id || document.partner_id === anchor.partner_id),
  );

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      const plans = buildSettlementAllocationFormPlans(candidates, amounts);
      await onSubmit({
        amount: getSettlementAllocationPlanTotal(plans),
        currency: 'EGP',
        fx_rate: 1,
        settlement_date: date,
        payment_method: method,
        reference_number: reference.trim() || undefined,
        receipt_document_id: receiptId || undefined,
        notes: notes.trim() || undefined,
        allocations: plans,
      });
      setError(null);
    } catch (submissionError) {
      setError(translateServerError(submissionError));
    }
  }

  return (
    <form id={formId} onSubmit={(event) => void submit(event)} className="space-y-4" noValidate>
      <FormErrorSummary serverError={error ?? serverError} title={locale === 'ar' ? 'تعذر تسجيل التسوية' : 'Settlement could not be recorded'} />
      <p className="rounded-2xl border border-warning/30 bg-warning/5 p-3 text-xs">{FINANCE_ATOMICITY_NOTICE[locale]}</p>
      <FormField>
        <FormLabel htmlFor={`${formId}-anchor`}>{locale === 'ar' ? 'الذمة المرجعية' : 'Anchor obligation'}</FormLabel>
        <select id={`${formId}-anchor`} value={selectedAnchorId} onChange={(event) => { setSelectedAnchorId(event.target.value); setAmounts({}); }} className="min-h-11 w-full rounded-xl border bg-background px-3">
          <option value="">{locale === 'ar' ? 'اختر ذمة…' : 'Choose obligation…'}</option>
          {settleable.map((item) => <option key={item.id} value={item.id}>{item.direction} · {formatEgp(getObligationRemainingEgp(item))} EGP</option>)}
        </select>
      </FormField>
      {anchor && (
        <div className="space-y-2">
          <p className="text-sm font-bold">{locale === 'ar' ? 'توزيع الدفعة' : 'Allocate payment'} · {formatEgp(total)} EGP</p>
          {candidates.map((item) => {
            const remaining = getObligationRemainingEgp(item);
            return (
              <label key={item.id} className="grid gap-2 rounded-xl border p-3 sm:grid-cols-[1fr_11rem] sm:items-center">
                <span className="text-sm">{item.due_date ?? '—'} · {locale === 'ar' ? 'المتبقي' : 'Remaining'} {formatEgp(remaining)} EGP</span>
                <input type="number" min="0" max={remaining} step="0.01" value={amounts[item.id] ?? ''} onChange={(event) => setAmounts((current) => ({ ...current, [item.id]: event.target.value }))} className="min-h-11 rounded-xl border bg-background px-3" dir="ltr" />
              </label>
            );
          })}
        </div>
      )}
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField><FormLabel>{locale === 'ar' ? 'التاريخ' : 'Date'}</FormLabel><input type="date" value={date} onChange={(event) => setDate(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" /></FormField>
        <FormField><FormLabel>{locale === 'ar' ? 'طريقة الدفع' : 'Payment method'}</FormLabel><select value={method} onChange={(event) => setMethod(event.target.value as SettlementPaymentMethod)} className="min-h-11 w-full rounded-xl border bg-background px-3"><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="cheque">Cheque</option><option value="card">Card</option><option value="other">Other</option></select></FormField>
        <FormField><FormLabel>{locale === 'ar' ? 'المرجع' : 'Reference'}</FormLabel><input value={reference} onChange={(event) => setReference(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" /></FormField>
        <FormField><FormLabel>{locale === 'ar' ? 'الإيصال' : 'Receipt'}</FormLabel><select value={receiptId} onChange={(event) => setReceiptId(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3"><option value="">{locale === 'ar' ? 'بدون إيصال' : 'No receipt'}</option>{receipts.map((document) => <option key={document.id} value={document.id}>{document.title_ar}</option>)}</select></FormField>
      </div>
      <FormField><FormLabel>{locale === 'ar' ? 'ملاحظات' : 'Notes'}</FormLabel><textarea rows={2} value={notes} onChange={(event) => setNotes(event.target.value)} className="w-full rounded-xl border bg-background px-3 py-2.5" /></FormField>
    </form>
  );
}

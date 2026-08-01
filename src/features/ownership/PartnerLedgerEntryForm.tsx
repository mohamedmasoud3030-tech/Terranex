import { useMemo, useRef, useState, type FormEvent } from 'react';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import type { Currency, Partner, PartnerLedgerEntry, PartnerLedgerEntryType, Project } from '../../core/types/domain';
import { createOwnershipRequestId, type RecordPartnerLedgerEntryInput } from './service';
import { partnerName } from './model';

const entryTypes: PartnerLedgerEntryType[] = [
  'capital_contribution',
  'withdrawal',
  'distribution_entitlement',
  'distribution_payment',
  'correction',
  'reversal',
];

const currencies: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

export function PartnerLedgerEntryForm({
  formId,
  projects,
  partners,
  ledgerEntries,
  locale,
  defaultProjectId,
  defaultPartnerId,
  pending = false,
  onSubmit,
}: {
  formId: string;
  projects: Project[];
  partners: Partner[];
  ledgerEntries: PartnerLedgerEntry[];
  locale: 'ar' | 'en';
  defaultProjectId?: string;
  defaultPartnerId?: string;
  pending?: boolean;
  onSubmit: (input: RecordPartnerLedgerEntryInput) => Promise<void>;
}) {
  const today = new Date().toISOString().slice(0, 10);
  const [projectId, setProjectId] = useState(defaultProjectId ?? '');
  const [partnerId, setPartnerId] = useState(defaultPartnerId ?? '');
  const [entryType, setEntryType] = useState<PartnerLedgerEntryType>('capital_contribution');
  const [amount, setAmount] = useState('');
  const [currency, setCurrency] = useState<Currency>('EGP');
  const [fxRate, setFxRate] = useState('1');
  const [postingDate, setPostingDate] = useState(today);
  const [notes, setNotes] = useState('');
  const [reversalOfId, setReversalOfId] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(createOwnershipRequestId());
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const inputClass = 'min-h-11 w-full rounded-xl border bg-background px-3 text-sm disabled:opacity-60';
  const needsConfirmation = entryType === 'withdrawal' || entryType === 'distribution_payment' || entryType === 'reversal';
  const reversalCandidates = useMemo(
    () => ledgerEntries.filter((entry) => (!projectId || entry.project_id === projectId) && (!partnerId || entry.partner_id === partnerId) && entry.entry_type !== 'reversal'),
    [ledgerEntries, partnerId, projectId],
  );

  function entryTypeLabel(type: PartnerLedgerEntryType) {
    const labels: Record<PartnerLedgerEntryType, string> = {
      capital_contribution: label('مساهمة رأسمالية', 'Capital contribution'),
      withdrawal: label('سحب', 'Withdrawal'),
      distribution_entitlement: label('استحقاق توزيع', 'Distribution entitlement'),
      distribution_payment: label('دفعة توزيع', 'Distribution payment'),
      correction: label('تصحيح', 'Correction'),
      reversal: label('عكس قيد', 'Reversal'),
    };
    return labels[type];
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const numericAmount = Number(amount);
    const numericFx = Number(fxRate);
    if (!projectId) {
      setError(label('اختر المشروع.', 'Choose a project.'));
      return;
    }
    if (!partnerId) {
      setError(label('اختر الشريك.', 'Choose a partner.'));
      return;
    }
    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      setError(label('المبلغ يجب أن يكون أكبر من صفر.', 'Amount must be positive.'));
      return;
    }
    if (!Number.isFinite(numericFx) || numericFx <= 0) {
      setError(label('سعر الصرف يجب أن يكون أكبر من صفر.', 'FX rate must be positive.'));
      return;
    }
    if (!postingDate) {
      setError(label('تاريخ القيد مطلوب.', 'Posting date is required.'));
      return;
    }
    if (!notes.trim()) {
      setError(label('الشرح مطلوب لحفظ قيد الشريك.', 'Explanation is required for partner ledger entries.'));
      return;
    }
    if (entryType === 'reversal' && !reversalOfId) {
      setError(label('اختر القيد الأصلي المراد عكسه.', 'Choose the original entry to reverse.'));
      return;
    }
    if (needsConfirmation && !confirmed) {
      setError(label('يجب تأكيد أثر هذه الحركة قبل الحفظ.', 'You must confirm the impact before saving.'));
      return;
    }

    await onSubmit({
      requestId: requestId.current,
      project_id: projectId,
      partner_id: partnerId,
      entry_type: entryType,
      amount: numericAmount,
      currency,
      fx_rate: numericFx,
      posting_date: postingDate,
      notes: notes.trim(),
      reversal_of_id: entryType === 'reversal' ? reversalOfId : undefined,
    });
  }

  return (
    <form id={formId} onSubmit={submit} className="space-y-4" noValidate>
      {error && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</p>}
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{label('المشروع', 'Project')}</FormLabel>
          <select aria-label={label('المشروع', 'Project')} value={projectId} onChange={(event) => setProjectId(event.target.value)} className={inputClass} disabled={pending || Boolean(defaultProjectId)}>
            <option value="">{label('اختر المشروع', 'Choose project')}</option>
            {projects.map((project) => <option key={project.id} value={project.id}>{locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{label('الشريك', 'Partner')}</FormLabel>
          <select aria-label={label('الشريك', 'Partner')} value={partnerId} onChange={(event) => setPartnerId(event.target.value)} className={inputClass} disabled={pending || Boolean(defaultPartnerId)}>
            <option value="">{label('اختر الشريك', 'Choose partner')}</option>
            {partners.map((partner) => <option key={partner.id} value={partner.id}>{partnerName(partner, locale)}</option>)}
          </select>
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{label('نوع القيد', 'Entry type')}</FormLabel>
          <select aria-label={label('نوع القيد', 'Entry type')} value={entryType} onChange={(event) => { setEntryType(event.target.value as PartnerLedgerEntryType); setConfirmed(false); }} className={inputClass} disabled={pending}>
            {entryTypes.map((type) => <option key={type} value={type}>{entryTypeLabel(type)}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{label('تاريخ القيد', 'Posting date')}</FormLabel>
          <input aria-label={label('تاريخ القيد', 'Posting date')} type="date" value={postingDate} onChange={(event) => setPostingDate(event.target.value)} className={inputClass} disabled={pending} />
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel>{label('المبلغ', 'Amount')}</FormLabel>
          <input aria-label={label('المبلغ', 'Amount')} type="number" min="0.01" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} className={inputClass} disabled={pending} />
        </FormField>
        <FormField>
          <FormLabel>{label('العملة', 'Currency')}</FormLabel>
          <select aria-label={label('العملة', 'Currency')} value={currency} onChange={(event) => { const next = event.target.value as Currency; setCurrency(next); if (next === 'EGP') setFxRate('1'); }} className={inputClass} disabled={pending}>
            {currencies.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{label('سعر الصرف', 'FX rate')}</FormLabel>
          <input aria-label={label('سعر الصرف', 'FX rate')} type="number" min="0.000001" step="0.000001" value={fxRate} onChange={(event) => setFxRate(event.target.value)} className={inputClass} disabled={pending || currency === 'EGP'} />
        </FormField>
      </div>

      {entryType === 'reversal' && (
        <FormField>
          <FormLabel>{label('القيد الأصلي', 'Original entry')}</FormLabel>
          <select aria-label={label('القيد الأصلي', 'Original entry')} value={reversalOfId} onChange={(event) => setReversalOfId(event.target.value)} className={inputClass} disabled={pending}>
            <option value="">{label('اختر القيد المراد عكسه', 'Choose entry to reverse')}</option>
            {reversalCandidates.map((entry) => <option key={entry.id} value={entry.id}>{entry.posting_date} · {entryTypeLabel(entry.entry_type)} · {entry.amount_egp.toLocaleString()} EGP</option>)}
          </select>
        </FormField>
      )}

      <FormField>
        <FormLabel>{label('الشرح / المرجع', 'Explanation / reference')}</FormLabel>
        <textarea aria-label={label('الشرح / المرجع', 'Explanation / reference')} value={notes} onChange={(event) => setNotes(event.target.value)} rows={3} className={`${inputClass} py-3`} disabled={pending} />
      </FormField>

      {needsConfirmation && (
        <label className="flex items-start gap-2 rounded-2xl border border-warning/30 bg-warning/5 p-3 text-sm">
          <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} className="mt-1" disabled={pending} />
          <span>{label('أؤكد أن هذه الحركة تؤثر على رصيد الشريك وستبقى ظاهرة في السجل غير القابل للحذف.', 'I confirm this movement affects the partner balance and remains visible in the immutable ledger.')}</span>
        </label>
      )}
    </form>
  );
}

import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import type { BankAccount, Currency, Partner, PartnerLedgerEntry, PartnerLedgerEntryType, Project } from '../../core/types/domain';
import { listBankAccounts } from '../banking/storage';
import { createOwnershipRequestId, type RecordPartnerLedgerEntryInput } from './service';
import { partnerName } from './model';

const entryTypes: PartnerLedgerEntryType[] = [
  'capital_contribution',
  'withdrawal',
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
  const [bankAccountId, setBankAccountId] = useState('');
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([]);
  const [banksLoading, setBanksLoading] = useState(true);
  const [notes, setNotes] = useState('');
  const [reversalOfId, setReversalOfId] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(createOwnershipRequestId());
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const inputClass = 'min-h-11 w-full rounded-xl border bg-background px-3 text-sm disabled:opacity-60';
  const isCapitalCash = entryType === 'capital_contribution' || entryType === 'withdrawal';
  const needsConfirmation = entryType === 'withdrawal' || entryType === 'reversal';

  useEffect(() => {
    let active = true;
    void listBankAccounts()
      .then((rows) => { if (active) setBankAccounts(rows.filter((row) => !row.is_archived)); })
      .catch((err) => { if (active) setError(err instanceof Error ? err.message : String(err)); })
      .finally(() => { if (active) setBanksLoading(false); });
    return () => { active = false; };
  }, []);

  const reversedIds = useMemo(() => new Set(
    ledgerEntries
      .filter((entry) => entry.entry_type === 'reversal' && entry.reversal_of_id)
      .map((entry) => entry.reversal_of_id as string),
  ), [ledgerEntries]);
  const reversalCandidates = useMemo(
    () => ledgerEntries.filter((entry) =>
      (!projectId || entry.project_id === projectId)
      && (!partnerId || entry.partner_id === partnerId)
      && entry.entry_type !== 'reversal'
      && entry.entry_type !== 'distribution_entitlement'
      && !reversedIds.has(entry.id)
    ),
    [ledgerEntries, partnerId, projectId, reversedIds],
  );
  const reversalTarget = reversalCandidates.find((entry) => entry.id === reversalOfId);

  function entryTypeLabel(type: PartnerLedgerEntryType) {
    const labels: Record<PartnerLedgerEntryType, string> = {
      capital_contribution: label('مساهمة رأسمالية داخلة', 'Capital contribution'),
      withdrawal: label('سحب من رأس المال', 'Capital withdrawal'),
      distribution_entitlement: label('استحقاق توزيع — من دورة التوزيع', 'Distribution entitlement — lifecycle only'),
      distribution_payment: label('دفعة توزيع — من دورة التوزيع', 'Distribution payment — lifecycle only'),
      correction: label('تصحيح غير نقدي', 'Non-cash correction'),
      reversal: label('عكس قيد سابق', 'Reverse prior entry'),
    };
    return labels[type];
  }

  function selectBank(id: string) {
    setBankAccountId(id);
    const bank = bankAccounts.find((row) => row.id === id);
    if (bank) {
      setCurrency(bank.currency);
      if (bank.currency === 'EGP') setFxRate('1');
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const numericAmount = reversalTarget?.amount ?? Number(amount);
    const numericFx = reversalTarget?.fx_rate ?? Number(fxRate);
    const effectiveCurrency = reversalTarget?.currency ?? currency;
    if (!projectId) { setError(label('اختر المشروع.', 'Choose a project.')); return; }
    if (!partnerId) { setError(label('اختر الشريك.', 'Choose a partner.')); return; }
    if (entryType !== 'reversal' && (!Number.isFinite(numericAmount) || numericAmount <= 0)) {
      setError(label('المبلغ يجب أن يكون أكبر من صفر.', 'Amount must be positive.')); return;
    }
    if (!Number.isFinite(numericFx) || numericFx <= 0) {
      setError(label('سعر الصرف يجب أن يكون أكبر من صفر.', 'FX rate must be positive.')); return;
    }
    if (!postingDate) { setError(label('تاريخ القيد مطلوب.', 'Posting date is required.')); return; }
    if (!notes.trim()) { setError(label('الشرح مطلوب لحفظ قيد الشريك.', 'Explanation is required.')); return; }
    if (isCapitalCash && !bankAccountId) {
      setError(label('اختر حساب البنك أو الخزينة للحركة النقدية.', 'Choose the bank or cash account.')); return;
    }
    if (entryType === 'reversal' && !reversalTarget) {
      setError(label('اختر القيد الأصلي المراد عكسه.', 'Choose the original entry to reverse.')); return;
    }
    if (needsConfirmation && !confirmed) {
      setError(label('يجب تأكيد أثر هذه الحركة قبل الحفظ.', 'Confirm the impact before saving.')); return;
    }

    await onSubmit({
      requestId: requestId.current,
      project_id: projectId,
      partner_id: partnerId,
      entry_type: entryType,
      amount: numericAmount,
      currency: effectiveCurrency,
      fx_rate: numericFx,
      posting_date: postingDate,
      bank_account_id: isCapitalCash ? bankAccountId : undefined,
      notes: notes.trim(),
      reversal_of_id: entryType === 'reversal' ? reversalOfId : undefined,
    });
  }

  return (
    <form id={formId} onSubmit={submit} className="space-y-4" noValidate>
      {error && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</p>}
      <p className="rounded-xl border border-border bg-muted/20 p-3 text-xs text-muted-foreground">
        {label(
          'المساهمة والسحب يُسجلان مع حركة بنك أو خزينة ذرية. استحقاقات ودفعات الأرباح تُدار فقط من شاشة التوزيع بعد الاعتماد.',
          'Contributions and withdrawals post atomically with a bank/cash movement. Profit entitlements and payments are managed only through the approved distribution workflow.',
        )}
      </p>
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
          <select aria-label={label('نوع القيد', 'Entry type')} value={entryType} onChange={(event) => {
            setEntryType(event.target.value as PartnerLedgerEntryType);
            setConfirmed(false); setReversalOfId('');
          }} className={inputClass} disabled={pending}>
            {entryTypes.map((type) => <option key={type} value={type}>{entryTypeLabel(type)}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{label(entryType === 'reversal' ? 'تاريخ العكس' : 'تاريخ القيد', entryType === 'reversal' ? 'Reversal date' : 'Posting date')}</FormLabel>
          <input aria-label={label('تاريخ القيد', 'Posting date')} type="date" value={postingDate} onChange={(event) => setPostingDate(event.target.value)} className={inputClass} disabled={pending} />
        </FormField>
      </div>

      {entryType !== 'reversal' && (
        <div className="grid gap-4 sm:grid-cols-3">
          <FormField>
            <FormLabel>{label('المبلغ', 'Amount')}</FormLabel>
            <input aria-label={label('المبلغ', 'Amount')} type="number" min="0.01" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} className={inputClass} disabled={pending} />
          </FormField>
          <FormField>
            <FormLabel>{label('العملة', 'Currency')}</FormLabel>
            <select aria-label={label('العملة', 'Currency')} value={currency} onChange={(event) => {
              const next = event.target.value as Currency; setCurrency(next); if (next === 'EGP') setFxRate('1');
            }} className={inputClass} disabled={pending || (isCapitalCash && Boolean(bankAccountId))}>
              {currencies.map((item) => <option key={item} value={item}>{item}</option>)}
            </select>
          </FormField>
          <FormField>
            <FormLabel>{label('سعر الصرف', 'FX rate')}</FormLabel>
            <input aria-label={label('سعر الصرف', 'FX rate')} type="number" min="0.000001" step="0.000001" value={fxRate} onChange={(event) => setFxRate(event.target.value)} className={inputClass} disabled={pending || currency === 'EGP'} />
          </FormField>
        </div>
      )}

      {isCapitalCash && (
        <FormField>
          <FormLabel>{label('حساب البنك أو الخزينة', 'Bank or cash account')}</FormLabel>
          <select aria-label={label('حساب البنك أو الخزينة', 'Bank or cash account')} value={bankAccountId} onChange={(event) => selectBank(event.target.value)} className={inputClass} disabled={pending || banksLoading}>
            <option value="">{banksLoading ? label('جارٍ تحميل الحسابات…', 'Loading accounts…') : label('اختر الحساب', 'Choose account')}</option>
            {bankAccounts.map((bank) => <option key={bank.id} value={bank.id}>{bank.name_ar} · {bank.currency}</option>)}
          </select>
          {!banksLoading && bankAccounts.length === 0 && <p className="text-xs text-warning">{label('أضف حساب بنك أو خزينة أولًا.', 'Add a bank or cash account first.')}</p>}
        </FormField>
      )}

      {entryType === 'reversal' && (
        <FormField>
          <FormLabel>{label('القيد الأصلي', 'Original entry')}</FormLabel>
          <select aria-label={label('القيد الأصلي', 'Original entry')} value={reversalOfId} onChange={(event) => setReversalOfId(event.target.value)} className={inputClass} disabled={pending}>
            <option value="">{label('اختر القيد المراد عكسه', 'Choose entry to reverse')}</option>
            {reversalCandidates.map((entry) => <option key={entry.id} value={entry.id}>{entry.posting_date} · {entryTypeLabel(entry.entry_type)} · {entry.amount_egp.toLocaleString()} EGP</option>)}
          </select>
          {reversalTarget && <p className="text-xs text-muted-foreground">{label('سيُنشأ قيد عكسي وحركة نقدية معاكسة عند وجود حساب مرتبط.', 'A reversal entry and opposite cash movement will be created when applicable.')}</p>}
        </FormField>
      )}

      <FormField>
        <FormLabel>{label(entryType === 'reversal' ? 'سبب العكس' : 'الشرح / المرجع', entryType === 'reversal' ? 'Reversal reason' : 'Explanation / reference')}</FormLabel>
        <textarea aria-label={label('الشرح / المرجع', 'Explanation / reference')} value={notes} onChange={(event) => setNotes(event.target.value)} rows={3} className={`${inputClass} py-3`} disabled={pending} />
      </FormField>

      {needsConfirmation && (
        <label className="flex items-start gap-2 rounded-2xl border border-warning/30 bg-warning/5 p-3 text-sm">
          <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} className="mt-1" disabled={pending} />
          <span>{label('أؤكد أنني راجعت الأثر المالي والبنكي لهذه الحركة.', 'I confirm that I reviewed the financial and banking impact.')}</span>
        </label>
      )}
    </form>
  );
}
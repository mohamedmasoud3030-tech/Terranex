import { useState, type FormEvent } from 'react';
import { FormError, FormField, FormLabel, TextInput, SelectInput } from '../../components/ui/FormControls';
import { Button } from '../../components/ui/Button';
import type { BankAccountInput } from './types';
import type { Currency } from '../../core/types/domain';
import { todayIso } from '../../core/lib/dateUtils';

interface Props {
  initial?: Partial<BankAccountInput>;
  onSubmit: (input: BankAccountInput) => void | Promise<void>;
  onCancel: () => void;
  saving?: boolean;
}

const CURRENCIES: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

const ACCOUNT_TYPE_LABELS = {
  bank: 'بنك',
  cash: 'صندوق',
  wallet: 'محفظة إلكترونية',
} as const;

export function BankAccountForm({ initial, onSubmit, onCancel, saving }: Props) {
  const [nameAr, setNameAr] = useState(initial?.name_ar ?? '');
  const [nameEn, setNameEn] = useState(initial?.name_en ?? '');
  const [accountType, setAccountType] = useState<'bank'|'cash'|'wallet'>(initial?.account_type ?? 'bank');
  const [currency, setCurrency] = useState<Currency>(initial?.currency ?? 'OMR');
  const [openingBalance, setOpeningBalance] = useState(String(initial?.opening_balance ?? ''));
  const [openingDate, setOpeningDate] = useState(initial?.opening_date ?? todayIso());
  const [bankName, setBankName] = useState(initial?.bank_name ?? '');
  const [accountNumber, setAccountNumber] = useState(initial?.account_number ?? '');
  const [iban, setIban] = useState(initial?.iban ?? '');
  const [error, setError] = useState('');

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    if (nameAr.trim().length < 2) { setError('اسم الحساب مطلوب (حرفان على الأقل).'); return; }
    const bal = Number(openingBalance);
    if (!Number.isFinite(bal) || bal < 0) { setError('الرصيد الافتتاحي يجب أن يكون رقماً غير سالب.'); return; }
    const input: BankAccountInput = {
      name_ar: nameAr.trim(),
      name_en: nameEn.trim() || undefined,
      account_type: accountType,
      currency,
      opening_balance: bal,
      opening_date: openingDate,
      bank_name: bankName.trim() || undefined,
      account_number: accountNumber.trim() || undefined,
      iban: iban.trim() || undefined,
    };
    await onSubmit(input);
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <FormField>
          <FormLabel>اسم الحساب (عربي)</FormLabel>
          <TextInput value={nameAr} onChange={e => setNameAr(e.target.value)} placeholder="مثال: البنك الأهلي - جاري" autoFocus />
        </FormField>
        <FormField>
          <FormLabel>الاسم بالإنجليزية (اختياري)</FormLabel>
          <TextInput value={nameEn} onChange={e => setNameEn(e.target.value)} placeholder="National Bank - Current" dir="ltr" />
        </FormField>
        <FormField>
          <FormLabel>نوع الحساب</FormLabel>
          <SelectInput value={accountType} onChange={e => setAccountType(e.target.value as 'bank'|'cash'|'wallet')}>
            {Object.entries(ACCOUNT_TYPE_LABELS).map(([v, l]) => (
              <option key={v} value={v}>{l}</option>
            ))}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel>العملة</FormLabel>
          <SelectInput value={currency} onChange={e => setCurrency(e.target.value as Currency)}>
            {CURRENCIES.map(c => <option key={c} value={c}>{c}</option>)}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel>الرصيد الافتتاحي</FormLabel>
          <TextInput type="number" min="0" step="0.001" value={openingBalance} onChange={e => setOpeningBalance(e.target.value)} placeholder="0.000" />
        </FormField>
        <FormField>
          <FormLabel>تاريخ الرصيد الافتتاحي</FormLabel>
          <TextInput type="date" value={openingDate} onChange={e => setOpeningDate(e.target.value)} />
        </FormField>
      </div>

      {accountType === 'bank' && (
        <div className="grid grid-cols-2 gap-3">
          <FormField>
            <FormLabel>اسم البنك</FormLabel>
            <TextInput value={bankName} onChange={e => setBankName(e.target.value)} placeholder="مثال: بنك مسقط" />
          </FormField>
          <FormField>
            <FormLabel>رقم الحساب</FormLabel>
            <TextInput value={accountNumber} onChange={e => setAccountNumber(e.target.value)} placeholder="xxxx-xxxx-xxxx" dir="ltr" />
          </FormField>
          <FormField className="col-span-2">
            <FormLabel>IBAN (اختياري)</FormLabel>
            <TextInput value={iban} onChange={e => setIban(e.target.value)} placeholder="OM00 0000 0000 0000" dir="ltr" />
          </FormField>
        </div>
      )}

      {error && <FormError>{error}</FormError>}
      <div className="flex gap-2 pt-2">
        <Button type="submit" variant="primary" size="sm" className="flex-1" disabled={saving}>
          {saving ? 'جارٍ الحفظ…' : initial ? 'حفظ التعديلات' : 'إضافة الحساب'}
        </Button>
        <Button type="button" variant="ghost" size="sm" onClick={onCancel} disabled={saving}>إلغاء</Button>
      </div>
    </form>
  );
}

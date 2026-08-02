import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormLabel, SelectInput, TextInput, TextArea } from '../../components/ui/FormControls';
import type { BankTransactionInput, TransferInput } from './types';
import type { BankAccount, Currency } from '../../core/types/domain';
import type { BankAccountWithBalance } from './types';
import { todayIso } from '../../core/lib/dateUtils';

interface ManualProps {
  accounts: BankAccountWithBalance[];
  onSubmit: (input: BankTransactionInput) => void | Promise<void>;
  onCancel: () => void;
  saving?: boolean;
}

export function ManualTransactionForm({ accounts, onSubmit, onCancel, saving }: ManualProps) {
  const active = accounts.filter(a => !a.is_archived);
  const [accountId, setAccountId] = useState(active[0]?.id ?? '');
  const [direction, setDirection] = useState<'deposit'|'withdrawal'>('deposit');
  const [amount, setAmount] = useState('');
  const [date, setDate] = useState(todayIso());
  const [memo, setMemo] = useState('');
  const [fxRate, setFxRate] = useState('1');
  const [error, setError] = useState('');

  const account = active.find(a => a.id === accountId);
  const currency = account?.currency ?? 'EGP' as Currency;

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    if (!accountId) { setError('اختر الحساب.'); return; }
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) { setError('أدخل مبلغاً صحيحاً أكبر من صفر.'); return; }
    const fx = Number(fxRate);
    if (!Number.isFinite(fx) || fx <= 0) { setError('سعر الصرف غير صالح.'); return; }
    const input: BankTransactionInput = {
      bank_account_id: accountId,
      direction,
      amount: amt,
      currency,
      fx_rate_to_base: fx,
      transaction_date: date,
      memo: memo.trim() || undefined,
      reference_type: 'manual',
    };
    await onSubmit(input);
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <FormField>
          <FormLabel>الحساب</FormLabel>
          <SelectInput value={accountId} onChange={e => setAccountId(e.target.value)}>
            {active.map(a => <option key={a.id} value={a.id}>{a.name_ar} ({a.currency})</option>)}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel>نوع الحركة</FormLabel>
          <SelectInput value={direction} onChange={e => setDirection(e.target.value as 'deposit'|'withdrawal')}>
            <option value="deposit">إيداع</option>
            <option value="withdrawal">سحب / دفع</option>
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel>المبلغ ({currency})</FormLabel>
          <TextInput type="number" min="0" step="0.001" value={amount} onChange={e => setAmount(e.target.value)} placeholder="0.000" dir="ltr" />
        </FormField>
        <FormField>
          <FormLabel>سعر الصرف إلى العملة الأساس</FormLabel>
          <TextInput type="number" min="0" step="0.000001" value={fxRate} onChange={e => setFxRate(e.target.value)} dir="ltr" />
        </FormField>
        <FormField className="col-span-2">
          <FormLabel>التاريخ</FormLabel>
          <TextInput type="date" value={date} onChange={e => setDate(e.target.value)} />
        </FormField>
      </div>
      <FormField>
        <FormLabel>ملاحظات</FormLabel>
        <TextArea rows={2} value={memo} onChange={e => setMemo(e.target.value)} placeholder="مثال: إيداع نقدية مبيعات اليوم" />
      </FormField>
      {error && <FormError>{error}</FormError>}
      <div className="flex gap-2 pt-2">
        <Button type="submit" variant="primary" size="sm" className="flex-1" disabled={saving || active.length === 0}>
          {saving ? 'جارٍ الحفظ…' : 'تسجيل الحركة'}
        </Button>
        <Button type="button" variant="ghost" size="sm" onClick={onCancel} disabled={saving}>إلغاء</Button>
      </div>
    </form>
  );
}

interface TransferProps {
  accounts: BankAccountWithBalance[];
  onSubmit: (input: TransferInput) => void | Promise<void>;
  onCancel: () => void;
  saving?: boolean;
}

export function TransferForm({ accounts, onSubmit, onCancel, saving }: TransferProps) {
  const active = accounts.filter(a => !a.is_archived);
  const [fromId, setFromId] = useState(active[0]?.id ?? '');
  const [toId, setToId] = useState(active[1]?.id ?? active[0]?.id ?? '');
  const [amount, setAmount] = useState('');
  const [date, setDate] = useState(todayIso());
  const [memo, setMemo] = useState('');
  const [fxFrom, setFxFrom] = useState('1');
  const [fxTo, setFxTo] = useState('1');
  const [error, setError] = useState('');

  const fromAcc = active.find(a => a.id === fromId);
  const toAcc = active.find(a => a.id === toId);
  const sameCurrency = fromAcc && toAcc && fromAcc.currency === toAcc.currency;

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    if (!fromId || !toId) { setError('اختر حسابي المصدر والوجهة.'); return; }
    if (fromId === toId) { setError('لا يمكن التحويل من وإلى نفس الحساب.'); return; }
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) { setError('أدخل مبلغاً صحيحاً أكبر من صفر.'); return; }
    const f1 = Number(fxFrom), f2 = Number(fxTo);
    if (!Number.isFinite(f1) || f1 <= 0 || !Number.isFinite(f2) || f2 <= 0) {
      setError('أسعار الصرف غير صالحة.'); return;
    }
    const input: TransferInput = {
      from_account: fromId,
      to_account: toId,
      amount: amt,
      currency: fromAcc!.currency,
      fx_rate_from: f1,
      fx_rate_to: sameCurrency ? f1 : f2,
      transaction_date: date,
      memo: memo.trim() || undefined,
    };
    await onSubmit(input);
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <FormField>
          <FormLabel>من حساب</FormLabel>
          <SelectInput value={fromId} onChange={e => setFromId(e.target.value)}>
            {active.map(a => <option key={a.id} value={a.id}>{a.name_ar} ({a.currency})</option>)}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel>إلى حساب</FormLabel>
          <SelectInput value={toId} onChange={e => setToId(e.target.value)}>
            {active.map(a => <option key={a.id} value={a.id}>{a.name_ar} ({a.currency})</option>)}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel>المبلغ ({fromAcc?.currency ?? ''})</FormLabel>
          <TextInput type="number" min="0" step="0.001" value={amount} onChange={e => setAmount(e.target.value)} dir="ltr" />
        </FormField>
        <FormField>
          <FormLabel>التاريخ</FormLabel>
          <TextInput type="date" value={date} onChange={e => setDate(e.target.value)} />
        </FormField>
        <FormField>
          <FormLabel>سعر الصرف (من)</FormLabel>
          <TextInput type="number" min="0" step="0.000001" value={fxFrom} onChange={e => { setFxFrom(e.target.value); if (sameCurrency) setFxTo(e.target.value); }} dir="ltr" />
        </FormField>
        {!sameCurrency && (
          <FormField>
            <FormLabel>سعر الصرف (إلى)</FormLabel>
            <TextInput type="number" min="0" step="0.000001" value={fxTo} onChange={e => setFxTo(e.target.value)} dir="ltr" />
          </FormField>
        )}
      </div>
      <FormField>
        <FormLabel>ملاحظات (اختياري)</FormLabel>
        <TextArea rows={2} value={memo} onChange={e => setMemo(e.target.value)} placeholder="مثال: تحويل نقدية من الصندوق للبنك" />
      </FormField>
      {error && <FormError>{error}</FormError>}
      <div className="flex gap-2 pt-2">
        <Button type="submit" variant="primary" size="sm" className="flex-1" disabled={saving || active.length < 2}>
          {saving ? 'جارٍ التحويل…' : 'تسجيل التحويل'}
        </Button>
        <Button type="button" variant="ghost" size="sm" onClick={onCancel} disabled={saving}>إلغاء</Button>
      </div>
    </form>
  );
}

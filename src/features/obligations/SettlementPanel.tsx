import { useMemo, useState, type FormEvent } from 'react';
import { Paperclip, PlusCircle, RotateCcw } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { FormError, FormField, FormLabel, SelectInput, TextArea, TextInput } from '../../components/ui/FormControls';
import { formatEgp } from '../../core/lib/profitability';
import type { Document, Obligation } from '../../core/types/domain';
import { useSettlements } from '../settlements/hooks';
import type { SettlementPaymentMethod } from '../settlements/types';

const PAYMENT_METHODS: Array<{ value: Exclude<SettlementPaymentMethod, 'unknown'>; label: string }> = [
  { value: 'cash', label: 'نقدي' },
  { value: 'bank_transfer', label: 'تحويل بنكي' },
  { value: 'cheque', label: 'شيك' },
  { value: 'card', label: 'بطاقة' },
  { value: 'other', label: 'أخرى' },
];

function paymentMethodLabel(method: SettlementPaymentMethod) {
  if (method === 'unknown') return 'غير محدد — سجل مهاجر';
  return PAYMENT_METHODS.find((item) => item.value === method)?.label ?? method;
}

export function SettlementPanel({ obligation, receipts }: { obligation: Obligation; receipts: Document[] }) {
  const { settlements, createSettlement, reverseSettlement } = useSettlements(obligation.id);
  const [showForm, setShowForm] = useState(false);
  const [amount, setAmount] = useState('');
  const [settlementDate, setSettlementDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [paymentMethod, setPaymentMethod] = useState<Exclude<SettlementPaymentMethod, 'unknown'>>('cash');
  const [referenceNumber, setReferenceNumber] = useState('');
  const [receiptDocumentId, setReceiptDocumentId] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [reverseId, setReverseId] = useState<string | null>(null);
  const [reverseReason, setReverseReason] = useState('');
  const receiptById = useMemo(() => new Map(receipts.map((document) => [document.id, document])), [receipts]);
  const availableReceipts = receipts.filter((document) => (!obligation.project_id || document.project_id === obligation.project_id) && (!document.partner_id || document.partner_id === obligation.partner_id));
  const remainingEgp = Math.max(0, obligation.amount_egp - obligation.amount_settled_egp);

  function resetForm() {
    setAmount('');
    setReferenceNumber('');
    setReceiptDocumentId('');
    setNotes('');
    setError(null);
    setShowForm(false);
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    try {
      createSettlement({
        amount: Number(amount),
        currency: obligation.currency,
        fx_rate: obligation.amount > 0 ? obligation.amount_egp / obligation.amount : 1,
        settlement_date: settlementDate,
        payment_method: paymentMethod,
        reference_number: referenceNumber || undefined,
        receipt_document_id: receiptDocumentId || undefined,
        notes: notes || undefined,
      });
      resetForm();
    } catch (settlementError) {
      setError(settlementError instanceof Error ? settlementError.message : 'تعذر تسجيل التسوية.');
    }
  }

  function reverse(id: string) {
    try {
      reverseSettlement(id, reverseReason);
      setReverseId(null);
      setReverseReason('');
      setError(null);
    } catch (settlementError) {
      setError(settlementError instanceof Error ? settlementError.message : 'تعذر عكس التسوية.');
    }
  }

  return <div className="mt-4 rounded-2xl border border-border bg-muted/30 p-4">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p className="text-sm font-semibold">Timeline التسويات</p>
        <p className="mt-0.5 text-xs text-muted-foreground">الرصيد المتبقي: {formatEgp(remainingEgp)} EGP</p>
      </div>
      {remainingEgp > 0 && obligation.status !== 'written_off' && obligation.status !== 'disputed' && <Button size="sm" onClick={() => setShowForm((current) => !current)}><PlusCircle className="h-4 w-4" /> تسجيل دفعة</Button>}
    </div>
    {showForm && <form onSubmit={submit} className="mt-4 space-y-3 rounded-xl border border-border bg-card p-3">
      <div className="grid gap-3 md:grid-cols-3">
        <FormField>
          <FormLabel htmlFor="settlement-amount" className="sr-only">المبلغ</FormLabel>
          <TextInput id="settlement-amount" type="number" min="0" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder={`المبلغ (${obligation.currency})`} />
        </FormField>
        <FormField>
          <FormLabel htmlFor="settlement-date" className="sr-only">تاريخ التسوية</FormLabel>
          <TextInput id="settlement-date" type="date" value={settlementDate} onChange={(event) => setSettlementDate(event.target.value)} />
        </FormField>
        <FormField>
          <FormLabel htmlFor="settlement-payment-method" className="sr-only">طريقة الدفع</FormLabel>
          <SelectInput id="settlement-payment-method" value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value as Exclude<SettlementPaymentMethod, 'unknown'>)}>
            {PAYMENT_METHODS.map((method) => <option key={method.value} value={method.value}>{method.label}</option>)}
          </SelectInput>
        </FormField>
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="settlement-reference" className="sr-only">رقم المرجع</FormLabel>
          <TextInput id="settlement-reference" value={referenceNumber} onChange={(event) => setReferenceNumber(event.target.value)} placeholder="رقم المرجع" />
        </FormField>
        <FormField>
          <FormLabel htmlFor="settlement-receipt" className="sr-only">الإيصال</FormLabel>
          <SelectInput id="settlement-receipt" value={receiptDocumentId} onChange={(event) => setReceiptDocumentId(event.target.value)}>
            <option value="">بدون إيصال</option>
            {availableReceipts.map((document) => <option key={document.id} value={document.id}>{document.title_ar}</option>)}
          </SelectInput>
        </FormField>
      </div>
      <FormField>
        <FormLabel htmlFor="settlement-notes" className="sr-only">ملاحظات</FormLabel>
        <TextArea id="settlement-notes" rows={2} value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="ملاحظات" />
      </FormField>
      {error && <FormError>{error}</FormError>}
      <div className="flex justify-end gap-2"><Button type="button" size="sm" variant="secondary" onClick={resetForm}>إلغاء</Button><Button type="submit" size="sm" variant="success">تسجيل التسوية</Button></div>
    </form>}
    {settlements.length === 0 ? <p className="mt-4 text-xs text-muted-foreground">لم تُسجل دفعات على هذا الالتزام بعد.</p> : <div className="mt-4 space-y-3">{settlements.map((settlement) => {
      const receipt = settlement.receipt_document_id ? receiptById.get(settlement.receipt_document_id) : undefined;
      return <div key={settlement.id} className="rounded-xl border border-border bg-card p-3 text-sm">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><span className="font-semibold">{formatEgp(settlement.amount_egp)} EGP</span><Badge tone={settlement.status === 'active' ? 'positive' : 'neutral'}>{settlement.status === 'active' ? 'نشطة' : 'معكوسة'}</Badge>{settlement.origin === 'legacy_balance_migration' && <Badge tone="info">مهاجرة</Badge>}</div><p className="mt-1 text-xs text-muted-foreground">{settlement.settlement_date} · {paymentMethodLabel(settlement.payment_method)}</p>{settlement.reference_number && <p className="mt-1 text-xs">المرجع: {settlement.reference_number}</p>}{receipt && <p className="mt-1 flex items-center gap-1 text-xs"><Paperclip className="h-3 w-3" /> {receipt.title_ar}</p>}{settlement.notes && <p className="mt-1 text-xs text-muted-foreground">{settlement.notes}</p>}{settlement.reversal_reason && <p className="mt-1 text-xs text-danger">سبب العكس: {settlement.reversal_reason}</p>}</div>{settlement.status === 'active' && <Button type="button" size="sm" variant="secondary" onClick={() => setReverseId(settlement.id)}><RotateCcw className="h-4 w-4" /> عكس</Button>}</div>
        {reverseId === settlement.id && <div className="mt-3 flex flex-col gap-2 sm:flex-row"><FormField className="flex-1"><FormLabel htmlFor={`reverse-reason-${settlement.id}`} className="sr-only">سبب العكس</FormLabel><TextInput id={`reverse-reason-${settlement.id}`} value={reverseReason} onChange={(event) => setReverseReason(event.target.value)} placeholder="سبب العكس *" /></FormField><Button type="button" size="sm" variant="danger" onClick={() => reverse(settlement.id)}>تأكيد العكس</Button></div>}
      </div>;
    })}</div>}
    {!showForm && error && <FormError className="mt-3">{error}</FormError>}
  </div>;
}

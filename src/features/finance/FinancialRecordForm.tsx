import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { BASE_CURRENCY, RECORD_TYPE_LABELS_AR, SECTOR_LABELS_AR, type FinancialRecord, type FinancialRecordInput, type FinancialRecordSector, type FinancialRecordType } from './types';

interface FinancialRecordFormProps {
  record?: FinancialRecord | null;
  onSubmit: (input: FinancialRecordInput) => void;
  onCancel: () => void;
}

const recordTypes = Object.keys(RECORD_TYPE_LABELS_AR) as FinancialRecordType[];
const sectors = Object.keys(SECTOR_LABELS_AR) as FinancialRecordSector[];

function today() {
  return new Date().toISOString().slice(0, 10);
}

export function FinancialRecordForm({ record, onSubmit, onCancel }: FinancialRecordFormProps) {
  const [date, setDate] = useState(record?.date ?? today());
  const [type, setType] = useState<FinancialRecordType>(record?.type ?? 'income');
  const [sector, setSector] = useState<FinancialRecordSector>(record?.sector ?? 'general');
  const [title, setTitle] = useState(record?.title ?? '');
  const [counterparty, setCounterparty] = useState(record?.counterparty ?? '');
  const [amount, setAmount] = useState(record?.amount.toString() ?? '');
  const [notes, setNotes] = useState(record?.notes ?? '');
  const [error, setError] = useState('');

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const parsedAmount = Number(amount);
    if (!date || !title.trim() || !Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      setError('أدخل التاريخ، العنوان، ومبلغًا صحيحًا أكبر من صفر.');
      return;
    }

    setError('');
    onSubmit({
      date,
      type,
      sector,
      title,
      counterparty,
      amount: parsedAmount,
      notes,
    });
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      {error && (
        <p className="rounded-xl border border-danger/30 bg-danger/5 px-4 py-3 text-sm font-semibold text-danger" role="alert">
          {error}
        </p>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        <label className="space-y-2 text-sm font-semibold">
          <span>التاريخ</span>
          <input className="w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" type="date" value={date} onChange={(event) => setDate(event.target.value)} required />
        </label>

        <label className="space-y-2 text-sm font-semibold">
          <span>نوع السجل</span>
          <select className="w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" value={type} onChange={(event) => setType(event.target.value as FinancialRecordType)} required>
            {recordTypes.map((recordType) => (
              <option key={recordType} value={recordType}>{RECORD_TYPE_LABELS_AR[recordType]}</option>
            ))}
          </select>
        </label>

        <label className="space-y-2 text-sm font-semibold">
          <span>القطاع</span>
          <select className="w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" value={sector} onChange={(event) => setSector(event.target.value as FinancialRecordSector)} required>
            {sectors.map((sectorId) => (
              <option key={sectorId} value={sectorId}>{SECTOR_LABELS_AR[sectorId]}</option>
            ))}
          </select>
        </label>

        <label className="space-y-2 text-sm font-semibold">
          <span>المبلغ بالجنيه المصري</span>
          <input className="w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" inputMode="decimal" min="0.01" step="0.01" type="number" value={amount} onChange={(event) => setAmount(event.target.value)} required />
        </label>
      </div>

      <label className="space-y-2 text-sm font-semibold">
        <span>عنوان السجل</span>
        <input className="w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" value={title} onChange={(event) => setTitle(event.target.value)} placeholder="مثال: إيراد بيع محصول أو مصروف صيانة" required />
      </label>

      <label className="space-y-2 text-sm font-semibold">
        <span>الطرف المقابل</span>
        <input className="w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" value={counterparty} onChange={(event) => setCounterparty(event.target.value)} placeholder="اختياري" />
      </label>

      <label className="space-y-2 text-sm font-semibold">
        <span>ملاحظات</span>
        <textarea className="min-h-24 w-full rounded-xl border border-border bg-background px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-primary" value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="اختياري" />
      </label>

      <div className="rounded-2xl border border-border bg-muted/60 p-3 text-sm text-muted-foreground">
        العملة الأساسية لهذا التطبيق المحلي هي الجنيه المصري فقط: ج.م / {BASE_CURRENCY}.
      </div>

      <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit">{record ? 'حفظ التعديل' : 'حفظ السجل'}</Button>
      </div>
    </form>
  );
}

import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormHint, FormLabel, SelectInput, TextArea, TextInput } from '../../components/ui/FormControls';
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
        <FormError className="rounded-xl border border-danger/30 bg-danger/5 px-4 py-3 text-sm font-semibold" role="alert">
          {error}
        </FormError>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="financial-record-date">التاريخ</FormLabel>
          <TextInput id="financial-record-date" type="date" value={date} onChange={(event) => setDate(event.target.value)} required />
        </FormField>

        <FormField>
          <FormLabel htmlFor="financial-record-type">نوع السجل</FormLabel>
          <SelectInput id="financial-record-type" value={type} onChange={(event) => setType(event.target.value as FinancialRecordType)} required>
            {recordTypes.map((recordType) => (
              <option key={recordType} value={recordType}>{RECORD_TYPE_LABELS_AR[recordType]}</option>
            ))}
          </SelectInput>
        </FormField>

        <FormField>
          <FormLabel htmlFor="financial-record-sector">القطاع</FormLabel>
          <SelectInput id="financial-record-sector" value={sector} onChange={(event) => setSector(event.target.value as FinancialRecordSector)} required>
            {sectors.map((sectorId) => (
              <option key={sectorId} value={sectorId}>{SECTOR_LABELS_AR[sectorId]}</option>
            ))}
          </SelectInput>
        </FormField>

        <FormField>
          <FormLabel htmlFor="financial-record-amount">المبلغ بالجنيه المصري</FormLabel>
          <TextInput id="financial-record-amount" inputMode="decimal" min="0.01" step="0.01" type="number" value={amount} onChange={(event) => setAmount(event.target.value)} required />
        </FormField>
      </div>

      <FormField>
        <FormLabel htmlFor="financial-record-title">عنوان السجل</FormLabel>
        <TextInput id="financial-record-title" value={title} onChange={(event) => setTitle(event.target.value)} placeholder="مثال: إيراد بيع محصول أو مصروف صيانة" required />
      </FormField>

      <FormField>
        <FormLabel htmlFor="financial-record-counterparty">الطرف المقابل</FormLabel>
        <TextInput id="financial-record-counterparty" value={counterparty} onChange={(event) => setCounterparty(event.target.value)} placeholder="اختياري" />
      </FormField>

      <FormField>
        <FormLabel htmlFor="financial-record-notes">ملاحظات</FormLabel>
        <TextArea id="financial-record-notes" rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="اختياري" />
      </FormField>

      <FormHint className="rounded-2xl border border-border bg-muted/60 p-3 text-sm">
        العملة الأساسية لهذا التطبيق المحلي هي الجنيه المصري فقط: ج.م / {BASE_CURRENCY}.
      </FormHint>

      <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit">{record ? 'حفظ التعديل' : 'حفظ السجل'}</Button>
      </div>
    </form>
  );
}

export const PARTY_TYPE_LABEL: Record<'PERSON' | 'ORGANIZATION', string> = {
  PERSON: 'فرد',
  ORGANIZATION: 'شركة / جهة',
};

export function customerInvoiceState(outstandingMinorUnits: string, isReversed: boolean): {
  key: 'SETTLED' | 'PARTIAL' | 'OPEN' | 'REVERSED';
  label: string;
} {
  if (isReversed) return { key: 'REVERSED', label: 'معكوسة' };
  if (outstandingMinorUnits === '0') return { key: 'SETTLED', label: 'مسددة بالكامل' };
  return { key: 'OPEN', label: 'قيد التحصيل' };
}

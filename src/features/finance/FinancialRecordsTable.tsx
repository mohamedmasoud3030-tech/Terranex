import { Pencil, Trash2 } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { MoneyValue } from '../../components/ui/MoneyValue';
import { formatDate } from '../../core/lib/date';
import { RECORD_TYPE_LABELS_AR, SECTOR_LABELS_AR, type FinancialRecord } from './types';

interface FinancialRecordsTableProps {
  records: FinancialRecord[];
  onEdit: (record: FinancialRecord) => void;
  onDelete: (id: string) => void;
}

export function FinancialRecordsTable({ records, onEdit, onDelete }: FinancialRecordsTableProps) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[780px] border-separate border-spacing-0 text-sm">
        <thead>
          <tr className="text-muted-foreground">
            <th className="border-b border-border px-3 py-3 text-start font-semibold">التاريخ</th>
            <th className="border-b border-border px-3 py-3 text-start font-semibold">النوع</th>
            <th className="border-b border-border px-3 py-3 text-start font-semibold">القطاع</th>
            <th className="border-b border-border px-3 py-3 text-start font-semibold">العنوان</th>
            <th className="border-b border-border px-3 py-3 text-start font-semibold">الطرف</th>
            <th className="border-b border-border px-3 py-3 text-start font-semibold">المبلغ</th>
            <th className="border-b border-border px-3 py-3 text-start font-semibold">إجراءات</th>
          </tr>
        </thead>
        <tbody>
          {records.map((record) => (
            <tr key={record.id} className="align-top transition hover:bg-muted/50">
              <td className="border-b border-border px-3 py-3">{formatDate(record.date)}</td>
              <td className="border-b border-border px-3 py-3 font-semibold">{RECORD_TYPE_LABELS_AR[record.type]}</td>
              <td className="border-b border-border px-3 py-3">{SECTOR_LABELS_AR[record.sector]}</td>
              <td className="border-b border-border px-3 py-3">
                <p className="font-semibold">{record.title}</p>
                {record.notes && <p className="mt-1 max-w-xs text-xs leading-6 text-muted-foreground">{record.notes}</p>}
              </td>
              <td className="border-b border-border px-3 py-3">{record.counterparty || 'غير محدد'}</td>
              <td className="border-b border-border px-3 py-3"><MoneyValue amount={record.amount} currency="EGP" /></td>
              <td className="border-b border-border px-3 py-3">
                <div className="flex gap-2">
                  <Button type="button" variant="secondary" size="sm" onClick={() => onEdit(record)}>
                    <Pencil className="h-4 w-4" aria-hidden="true" />
                    تعديل
                  </Button>
                  <Button type="button" variant="danger" size="sm" onClick={() => onDelete(record.id)}>
                    <Trash2 className="h-4 w-4" aria-hidden="true" />
                    حذف
                  </Button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

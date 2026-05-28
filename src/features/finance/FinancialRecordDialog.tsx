import { X } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { FinancialRecordForm } from './FinancialRecordForm';
import type { FinancialRecord, FinancialRecordInput } from './types';

interface FinancialRecordDialogProps {
  open: boolean;
  record?: FinancialRecord | null;
  onSubmit: (input: FinancialRecordInput) => void;
  onClose: () => void;
}

export function FinancialRecordDialog({ open, record, onSubmit, onClose }: FinancialRecordDialogProps) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/45 p-3 sm:items-center" role="dialog" aria-modal="true" aria-labelledby="financial-record-dialog-title">
      <div className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-3xl border border-border bg-card p-5 shadow-2xl">
        <div className="mb-5 flex items-start justify-between gap-4">
          <div>
            <p className="text-sm text-muted-foreground">سجل مالي محلي محفوظ في المتصفح</p>
            <h2 id="financial-record-dialog-title" className="mt-1 text-2xl font-bold">
              {record ? 'تعديل سجل مالي' : 'إضافة سجل مالي جديد'}
            </h2>
          </div>
          <Button type="button" variant="ghost" size="icon" onClick={onClose} aria-label="إغلاق النموذج">
            <X className="h-5 w-5" aria-hidden="true" />
          </Button>
        </div>
        <FinancialRecordForm record={record} onSubmit={onSubmit} onCancel={onClose} />
      </div>
    </div>
  );
}

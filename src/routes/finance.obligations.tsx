import { useState } from 'react';
import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { PageHeader } from '../components/layout/PageHeader';
import { EmptyState } from '../components/ui/States';
import { Button } from '../components/ui/Button';
import { FinancialRecordDialog } from '../features/finance/FinancialRecordDialog';
import { FinancialRecordsTable } from '../features/finance/FinancialRecordsTable';
import { useFinancialRecords } from '../features/finance/hooks';
import type { FinancialRecord, FinancialRecordInput } from '../features/finance/types';

export const financeObligationsRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/obligations',
  component: FinanceRecordsPage,
});

function FinanceRecordsPage() {
  const { records, createRecord, updateRecord, deleteRecord, resetRecords } = useFinancialRecords();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingRecord, setEditingRecord] = useState<FinancialRecord | null>(null);

  function openCreateDialog() {
    setEditingRecord(null);
    setIsDialogOpen(true);
  }

  function handleSubmit(input: FinancialRecordInput) {
    if (editingRecord) {
      updateRecord(editingRecord.id, input);
    } else {
      createRecord(input);
    }
    setIsDialogOpen(false);
    setEditingRecord(null);
  }

  function handleDelete(id: string) {
    if (window.confirm('هل تريد حذف هذا السجل المالي؟')) {
      deleteRecord(id);
    }
  }

  function handleReset() {
    if (window.confirm('سيتم حذف كل السجلات المالية المحلية من هذا المتصفح. هل أنت متأكد؟')) {
      resetRecords();
    }
  }

  return (
    <>
      <PageHeader
        title="السجلات المالية"
        description="صفحة العمل المحلية الأولى: إنشاء، عرض، تعديل، حذف، ومسح السجلات المحفوظة في المتصفح."
        action={{ label: 'إضافة سجل جديد', onClick: openCreateDialog }}
      >
        {records.length > 0 && <Button type="button" variant="danger" onClick={handleReset}>مسح بيانات المتصفح</Button>}
      </PageHeader>

      <section className="rounded-3xl border border-border bg-card p-4 shadow-sm">
        {records.length === 0 ? (
          <EmptyState
            title="لا توجد بيانات بعد"
            description="ابدأ بإضافة أول سجل مالي لتظهر الأرقام هنا"
            action={{ label: 'إضافة سجل جديد', onClick: openCreateDialog }}
          />
        ) : (
          <FinancialRecordsTable
            records={records}
            onEdit={(record) => {
              setEditingRecord(record);
              setIsDialogOpen(true);
            }}
            onDelete={handleDelete}
          />
        )}
      </section>

      <FinancialRecordDialog
        open={isDialogOpen}
        record={editingRecord}
        onSubmit={handleSubmit}
        onClose={() => {
          setIsDialogOpen(false);
          setEditingRecord(null);
        }}
      />
    </>
  );
}

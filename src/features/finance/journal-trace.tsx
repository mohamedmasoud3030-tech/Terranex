import { formatMinorUnits } from '@/shared/money';
import type { JournalLedgerLine } from './queries';

const SOURCE_LABEL: Record<string, string> = {
  CONTRIBUTION_CASH_ATTRIBUTION: 'إسناد مساهمة',
  COST_OBLIGATION: 'اعتماد التزام',
  PAYMENT: 'دفعة',
  REVERSAL: 'عكس',
};

export function JournalTrace({ lines }: { lines: JournalLedgerLine[] }) {
  if (lines.length === 0) return <p className="muted">لا توجد قيود بعد.</p>;
  const batches = new Map<string, JournalLedgerLine[]>();
  for (const line of lines) {
    const list = batches.get(line.batch_id) ?? [];
    list.push(line);
    batches.set(line.batch_id, list);
  }
  return (
    <div className="stack">
      {[...batches.entries()].map(([batchId, batchLines]) => {
        const first = batchLines[0];
        const balanced = batchLines.reduce(
          (acc, line) => ({
            debit: acc.debit + (line.debit_minor_units ? BigInt(line.debit_minor_units) : 0n),
            credit: acc.credit + (line.credit_minor_units ? BigInt(line.credit_minor_units) : 0n),
          }),
          { debit: 0n, credit: 0n },
        );
        return (
          <div key={batchId} className="card stack">
            <div className="top" style={{ border: 0, margin: 0, padding: 0 }}>
              <strong>{SOURCE_LABEL[first.source_type] ?? first.source_type}</strong>
              <span className="status">{first.reversal_of_batch_id ? 'معكوس' : 'مرحّل'}</span>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>الحساب</th><th>مدين</th><th>دائن</th><th>العملة</th><th>تاريخ القيد</th></tr>
                </thead>
                <tbody>
                  {batchLines.map((line) => (
                    <tr key={line.line_id}>
                      <td>{line.account_label}</td>
                      <td>{formatMinorUnits(line.debit_minor_units, line.currency)}</td>
                      <td>{formatMinorUnits(line.credit_minor_units, line.currency)}</td>
                      <td>{line.currency}</td>
                      <td>{line.line_transaction_date}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot>
                  <tr>
                    <th>المجموع</th>
                    <th>{formatMinorUnits(balanced.debit, first.currency)}</th>
                    <th>{formatMinorUnits(balanced.credit, first.currency)}</th>
                    <th colSpan={2} />
                  </tr>
                </tfoot>
              </table>
            </div>
            <p className="muted">القيد {balanced.debit === balanced.credit ? 'متوازن' : 'غير متوازن — خطأ نظام'}</p>
          </div>
        );
      })}
    </div>
  );
}

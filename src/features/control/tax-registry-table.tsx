import type { TaxTreatment } from './queries';

/** Read-only tax treatment table. Shared by the project integrity page and /vat. */
export function TaxRegistryTable({ rows }: Readonly<{ rows: readonly TaxTreatment[] }>) {
  if (rows.length === 0) return <p className="muted">لا توجد معالجات ضريبية مسجلة.</p>;
  return (
    <div className="table-wrap">
      <table className="table-stackable">
        <caption className="sr-only">جدول: الضريبة · النطاق · المعالجة · جهة التقدير · سارية</caption>
        <thead>
          <tr><th scope="col">الضريبة</th><th scope="col">النطاق</th><th scope="col">المعالجة</th><th scope="col">جهة التقدير</th><th scope="col">سارية</th></tr>
        </thead>
        <tbody>
          {rows.map((tax) => (
            <tr key={tax.tax_registry_id}>
              <td data-label="الضريبة">{tax.tax_name} ({tax.tax_domain})</td>
              <td data-label="النطاق">{tax.applies_to}</td>
              <td data-label="المعالجة">{tax.treatment_status}</td>
              <td data-label="جهة التقدير">{tax.authority ?? '—'}</td>
              <td data-label="سارية">{tax.status === 'ACTIVE' ? 'نعم' : 'لا'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

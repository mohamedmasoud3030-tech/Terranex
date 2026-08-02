import { InvoicePdfViewBase } from './InvoicePdfDocument';
import { listInvoiceLines } from './storage';

export function InvoicePdfView({ invoiceId }: Readonly<{ invoiceId: string }>) {
  return <InvoicePdfViewBase invoiceId={invoiceId} table="sales_invoices" kind="sales" listLines={listInvoiceLines} />;
}

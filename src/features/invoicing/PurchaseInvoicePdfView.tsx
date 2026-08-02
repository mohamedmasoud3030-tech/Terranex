import { InvoicePdfViewBase } from './InvoicePdfDocument';
import { listPurchaseInvoiceLines } from './purchaseStorage';

export function PurchaseInvoicePdfView({ invoiceId }: Readonly<{ invoiceId: string }>) {
  return <InvoicePdfViewBase invoiceId={invoiceId} table="purchase_invoices" kind="purchase" listLines={listPurchaseInvoiceLines} />;
}

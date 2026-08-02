import type { InventoryItem } from '../../core/types/domain';
import { InvoiceForm, type InvoiceFormProps } from './InvoiceForm';

type Props = Readonly<InvoiceFormProps & { inventoryItems: InventoryItem[] }>;

export function PurchaseInvoiceForm(props: Props) {
  return <InvoiceForm {...props} mode="purchase" />;
}

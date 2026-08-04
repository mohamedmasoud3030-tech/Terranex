import { requestOdooSync } from '../../core/odoo/hooks';
import { requireClient } from '../../core/storage/supabaseClientRegistry';
import type { PurchaseInvoice, PurchaseInvoiceLine } from '../../core/types/domain';

const TABLE = 'purchase_invoices';
const LINES = 'purchase_invoice_lines';

export async function listPurchaseInvoices(): Promise<PurchaseInvoice[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(TABLE).select('*').order('issue_date', { ascending: false });
  if (error) throw new Error(`تعذر تحميل فواتير المشتريات: ${error.message}`);
  return (data ?? []) as PurchaseInvoice[];
}

export async function listPurchaseInvoiceLines(invoiceId: string): Promise<PurchaseInvoiceLine[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(LINES).select('*').eq('invoice_id', invoiceId).order('line_no');
  if (error) throw new Error(`تعذر تحميل بنود فاتورة المشتريات: ${error.message}`);
  return (data ?? []) as PurchaseInvoiceLine[];
}

export interface PurchaseInvoiceInput {
  request_id?: string;
  vendor_invoice_number?: string;
  project_id?: string;
  partner_id?: string;
  bank_account_id?: string;
  issue_date: string;
  due_date?: string;
  currency: PurchaseInvoice['currency'];
  fx_rate_to_base?: number;
  vat_rate?: number;
  notes?: string;
  lines: Array<{
    description_ar?: string;
    description_en?: string;
    quantity: number;
    unit_price: number;
    inventory_item_id?: string;
  }>;
}

export async function createPurchaseInvoice(input: PurchaseInvoiceInput): Promise<PurchaseInvoice> {
  const supabase = requireClient();
  const { data, error } = await supabase.rpc('create_purchase_invoice_atomic', {
    p_request_id: input.request_id ?? crypto.randomUUID(),
    p_vendor_invoice_number: input.vendor_invoice_number ?? null,
    p_partner_id: input.partner_id ?? null,
    p_project_id: input.project_id ?? null,
    p_bank_account_id: input.bank_account_id ?? null,
    p_issue_date: input.issue_date,
    p_due_date: input.due_date ?? null,
    p_currency: input.currency,
    p_fx_rate: input.fx_rate_to_base ?? 1,
    p_vat_rate: input.vat_rate ?? 0,
    p_notes: input.notes ?? null,
    p_lines: input.lines.map(line => ({
      description_ar: line.description_ar?.trim() || null,
      description_en: line.description_en?.trim() || null,
      quantity: Number(line.quantity),
      unit_price: Number(line.unit_price),
      inventory_item_id: line.inventory_item_id ?? null,
    })),
  });
  if (error) throw new Error(`تعذر إنشاء فاتورة المشتريات: ${error.message}`);

  const { data: row, error: fetchError } = await supabase.from(TABLE).select('*').eq('id', data as string).single();
  if (fetchError) throw new Error(`تعذر تحميل فاتورة المشتريات بعد الإنشاء: ${fetchError.message}`);
  return row as PurchaseInvoice;
}

export async function receivePurchaseInvoice(id: string, receiptDate = new Date().toISOString().slice(0, 10), requestId?: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('receive_purchase_invoice_with_stock', {
    p_request_id: requestId ?? crypto.randomUUID(),
    p_invoice_id: id,
    p_receipt_date: receiptDate,
  });
  if (error) throw new Error(`تعذر اعتماد فاتورة المشتريات: ${error.message}`);

  // Receiving queued the vendor bill in the same database transaction.
  void requestOdooSync();
}

export async function payPurchaseInvoice(
  id: string,
  amount: number,
  bankAccountId: string,
  date: string,
  memo?: string,
  requestId?: string,
): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('pay_purchase_invoice', {
    p_request_id: requestId ?? crypto.randomUUID(),
    p_invoice_id: id,
    p_amount: amount,
    p_bank_account: bankAccountId,
    p_date: date,
    p_memo: memo ?? null,
  });
  if (error) throw new Error(`تعذر تسجيل الدفعة: ${error.message}`);

  // The immutable supplier-payment row and Odoo event were committed in the
  // same RPC transaction. The durable outbox retains failed attempts.
  void requestOdooSync();
}
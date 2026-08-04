import { requestOdooSync } from '../../core/odoo/hooks';
import { requireClient } from '../../core/storage/supabaseClientRegistry';
import type { SalesInvoice, SalesInvoiceLine } from '../../core/types/domain';

const TABLE = 'sales_invoices';
const LINES = 'sales_invoice_lines';

export async function listInvoices(): Promise<SalesInvoice[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(TABLE).select('*').order('issue_date', { ascending: false });
  if (error) throw new Error(`تعذر تحميل الفواتير: ${error.message}`);
  return (data ?? []) as SalesInvoice[];
}

export async function listInvoiceLines(invoiceId: string): Promise<SalesInvoiceLine[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(LINES).select('*').eq('invoice_id', invoiceId).order('line_no');
  if (error) throw new Error(`تعذر تحميل بنود الفاتورة: ${error.message}`);
  return (data ?? []) as SalesInvoiceLine[];
}

export interface InvoiceInput {
  request_id?: string;
  project_id?: string;
  partner_id?: string;
  bank_account_id?: string;
  issue_date: string;
  due_date?: string;
  currency: SalesInvoice['currency'];
  fx_rate_to_base?: number;
  vat_rate?: number;
  notes?: string;
  lines: Array<{ description_ar?: string; description_en?: string; quantity: number; unit_price: number }>;
}

export async function createInvoice(input: InvoiceInput): Promise<SalesInvoice> {
  const supabase = requireClient();
  const { data, error } = await supabase.rpc('create_sales_invoice_atomic', {
    p_request_id: input.request_id ?? `inv_${crypto.randomUUID()}`,
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
    })),
  });
  if (error) throw new Error(`تعذر إنشاء الفاتورة: ${error.message}`);

  const { data: row, error: fetchError } = await supabase.from(TABLE).select('*').eq('id', data as string).single();
  if (fetchError) throw new Error(`تعذر تحميل الفاتورة بعد الإنشاء: ${fetchError.message}`);
  return row as SalesInvoice;
}

export async function issueInvoice(id: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('issue_sales_invoice', {
    p_request_id: `issue_${crypto.randomUUID()}`,
    p_invoice_id: id,
  });
  if (error) throw new Error(`تعذر إصدار الفاتورة: ${error.message}`);

  // The status transition queued the invoice transactionally. Draining is
  // best-effort; the durable outbox keeps failures for retry.
  void requestOdooSync();
}

export async function payInvoice(
  id: string,
  amount: number,
  bankAccountId: string,
  date: string,
  memo?: string,
  requestId?: string,
): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('pay_sales_invoice', {
    p_request_id: requestId ?? `pay_${crypto.randomUUID()}`,
    p_invoice_id: id,
    p_amount: amount,
    p_bank_account: bankAccountId,
    p_date: date,
    p_memo: memo ?? null,
  });
  if (error) throw new Error(`تعذر تسجيل الدفعة: ${error.message}`);
  // Payment-to-Odoo posting is deliberately deferred to the next bridge slice.
}

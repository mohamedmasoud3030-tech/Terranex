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
  request_id?: string; // stable idempotency UUID (client-generated)
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

/**
 * Create a sales invoice atomically on the server.
 * The server derives owner_id, computes totals, generates a sequential invoice
 * number, and inserts the header+lines in a single transaction. No orphan rows.
 */
export async function createInvoice(input: InvoiceInput): Promise<SalesInvoice> {
  const supabase = requireClient();
  const requestId = input.request_id ?? `inv_${crypto.randomUUID()}`;
  const { data, error } = await supabase.rpc('create_sales_invoice_atomic', {
    p_request_id: requestId,
    p_partner_id: input.partner_id ?? null,
    p_project_id: input.project_id ?? null,
    p_bank_account_id: input.bank_account_id ?? null,
    p_issue_date: input.issue_date,
    p_due_date: input.due_date ?? null,
    p_currency: input.currency,
    p_fx_rate: input.fx_rate_to_base ?? 1,
    p_vat_rate: input.vat_rate ?? 0,
    p_notes: input.notes ?? null,
    p_lines: input.lines.map(l => ({
      description_ar: l.description_ar?.trim() ?? null,
      description_en: l.description_en?.trim() ?? null,
      quantity: Number(l.quantity),
      unit_price: Number(l.unit_price),
    })),
  });
  if (error) throw new Error(`تعذر إنشاء الفاتورة: ${error.message}`);

  // Return the created invoice
  const invoiceId = data as unknown as string;
  const { data: row, error: fe } = await supabase.from(TABLE).select('*').eq('id', invoiceId).single();
  if (fe) throw new Error(`تعذر تحميل الفاتورة بعد الإنشاء: ${fe.message}`);
  return row as SalesInvoice;
}

export async function issueInvoice(id: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('issue_sales_invoice', {
    p_request_id: `issue_${crypto.randomUUID()}`,
    p_invoice_id: id,
  });
  if (error) throw new Error(`تعذر إصدار الفاتورة: ${error.message}`);
}

/**
 * Register a payment against a sales invoice.
 *
 * Server RPC is fully atomic: it (1) idempotency-checks by request_id,
 * (2) writes an immutable invoice_payments audit row, (3) creates the
 * matching bank_transaction, (4) updates invoice.amount_paid/status —
 * all in a single Postgres transaction. The client does NOT post its
 * own bank_transaction (that was a two-phase gap in earlier versions).
 */
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
}

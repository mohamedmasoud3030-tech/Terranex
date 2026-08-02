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

function nextInvoiceNumber() {
  const y = new Date().getFullYear();
  const rand = Math.floor(Math.random() * 9000 + 1000);
  return `INV-${y}-${rand}`;
}

export interface InvoiceInput {
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
  const subtotal = input.lines.reduce((s, l) => s + l.quantity * l.unit_price, 0);
  const vatRate = input.vat_rate ?? 0;
  const vatAmount = Math.round(subtotal * vatRate) / 100;
  const total = Math.round((subtotal + vatAmount) * 1000) / 1000;
  const { data, error } = await supabase.from(TABLE).insert({
    invoice_number: nextInvoiceNumber(),
    project_id: input.project_id ?? null,
    partner_id: input.partner_id ?? null,
    bank_account_id: input.bank_account_id ?? null,
    issue_date: input.issue_date,
    due_date: input.due_date ?? null,
    currency: input.currency,
    fx_rate_to_base: input.fx_rate_to_base ?? 1,
    subtotal: Math.round(subtotal * 1000) / 1000,
    vat_rate: vatRate,
    vat_amount: vatAmount,
    total,
    amount_paid: 0,
    status: 'draft',
    notes: input.notes ?? null,
  }).select().single();
  if (error) throw new Error(`تعذر إنشاء الفاتورة: ${error.message}`);
  const invoice = data as SalesInvoice;

  if (input.lines.length > 0) {
    const { error: le } = await supabase.from(LINES).insert(
      input.lines.map((l, i) => ({
        invoice_id: invoice.id,
        line_no: i + 1,
        description_ar: l.description_ar ?? null,
        description_en: l.description_en ?? null,
        quantity: l.quantity,
        unit_price: l.unit_price,
        line_total: Math.round(l.quantity * l.unit_price * 1000) / 1000,
      })),
    );
    if (le) throw new Error(`تعذر حفظ بنود الفاتورة: ${le.message}`);
  }
  return invoice;
}

export async function issueInvoice(id: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('issue_sales_invoice', {
    p_request_id: `issue_${id}_${Date.now()}`,
    p_invoice_id: id,
  });
  if (error) throw new Error(`تعذر إصدار الفاتورة: ${error.message}`);
}

export async function payInvoice(id: string, amount: number, bankAccountId: string, date: string, memo?: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('pay_sales_invoice', {
    p_request_id: `pay_${id}_${Date.now()}`,
    p_invoice_id: id,
    p_amount: amount,
    p_bank_account: bankAccountId,
    p_date: date,
    p_memo: memo ?? null,
  });
  if (error) throw new Error(`تعذر تسجيل الدفعة: ${error.message}`);
}

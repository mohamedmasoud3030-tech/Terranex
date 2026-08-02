import { requireClient } from '../../core/storage/supabaseClientRegistry';
import type { Currency, JournalEntry, JournalEntryLine } from '../../core/types/domain';

const TABLE = 'journal_entries';
const LINES = 'journal_entry_lines';

export async function listJournalEntries(): Promise<JournalEntry[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(TABLE).select('*').order('entry_date', { ascending: false });
  if (error) throw new Error(`تعذر تحميل السندات: ${error.message}`);
  return (data ?? []) as JournalEntry[];
}

export async function listJournalEntryLines(entryId: string): Promise<JournalEntryLine[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(LINES).select('*').eq('entry_id', entryId).order('line_no');
  if (error) throw new Error(`تعذر تحميل بنود السند: ${error.message}`);
  return (data ?? []) as JournalEntryLine[];
}

export interface JournalEntryInput {
  request_id?: string;
  entry_date: string;
  description_ar?: string;
  description_en?: string;
  currency: Currency;
  fx_rate_to_base?: number;
  notes?: string;
  lines: Array<{
    account_code?: string;
    description_ar?: string;
    description_en?: string;
    debit: number;
    credit: number;
    bank_account_id?: string;
    partner_id?: string;
    project_id?: string;
  }>;
}

export async function createJournalEntry(input: JournalEntryInput): Promise<JournalEntry> {
  const supabase = requireClient();
  const { data, error } = await supabase.rpc('create_journal_entry_atomic', {
    p_request_id: input.request_id ?? crypto.randomUUID(),
    p_entry_date: input.entry_date,
    p_description_ar: input.description_ar ?? null,
    p_description_en: input.description_en ?? null,
    p_currency: input.currency,
    p_fx_rate: input.fx_rate_to_base ?? 1,
    p_notes: input.notes ?? null,
    p_lines: input.lines.map(line => ({
      account_code: line.account_code?.trim() || null,
      description_ar: line.description_ar?.trim() || null,
      description_en: line.description_en?.trim() || null,
      debit: Number(line.debit) || 0,
      credit: Number(line.credit) || 0,
      bank_account_id: line.bank_account_id ?? null,
      partner_id: line.partner_id ?? null,
      project_id: line.project_id ?? null,
    })),
  });
  if (error) throw new Error(`تعذر إنشاء السند: ${error.message}`);

  const { data: row, error: fetchError } = await supabase.from(TABLE).select('*').eq('id', data as string).single();
  if (fetchError) throw new Error(`تعذر تحميل السند بعد الإنشاء: ${fetchError.message}`);
  return row as JournalEntry;
}

export async function postJournalEntry(id: string, requestId?: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('post_journal_entry', {
    p_request_id: requestId ?? crypto.randomUUID(),
    p_entry_id: id,
  });
  if (error) throw new Error(`تعذر اعتماد السند: ${error.message}`);
}

export async function voidJournalEntry(id: string, reason?: string, requestId?: string): Promise<void> {
  const supabase = requireClient();
  const { error } = await supabase.rpc('void_journal_entry', {
    p_request_id: requestId ?? crypto.randomUUID(),
    p_entry_id: id,
    p_reason: reason ?? null,
  });
  if (error) throw new Error(`تعذر إلغاء أو عكس السند: ${error.message}`);
}

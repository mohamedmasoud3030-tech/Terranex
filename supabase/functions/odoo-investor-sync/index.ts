import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

type InvestorEntityType = 'distribution' | 'partner_ledger_entry';
interface OutboxEvent {
  id: string;
  owner_id: string;
  entity_type: InvestorEntityType;
  entity_id: string;
  attempt_count: number;
}
interface MappingRow { odoo_model: string; odoo_record_id: number }
interface JsonRpcResponse<T> {
  result?: T;
  error?: { message: string; data?: { message?: string } };
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}
function optionalInt(name: string): number | undefined {
  const raw = Deno.env.get(name)?.trim();
  if (!raw) return undefined;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) throw new Error(`${name} must be a positive integer`);
  return value;
}
function roundMoney(value: number): number { return Number(value.toFixed(2)); }
function relationId(value: unknown): number | null {
  if (typeof value === 'number' && value > 0) return value;
  if (Array.isArray(value) && typeof value[0] === 'number' && value[0] > 0) return value[0];
  return null;
}

class OdooClient {
  private readonly url = env('ODOO_URL').replace(/\/$/, '');
  private readonly db = env('ODOO_DB');
  private readonly username = env('ODOO_USERNAME');
  private readonly key = env('ODOO_API_KEY');
  private uid: number | null = null;
  private requestId = 1;

  private async rpc<T>(service: string, method: string, args: unknown[]): Promise<T> {
    const response = await fetch(`${this.url}/jsonrpc`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'call', params: { service, method, args }, id: this.requestId++ }),
    });
    if (!response.ok) throw new Error(`Odoo HTTP ${response.status}`);
    const body = await response.json() as JsonRpcResponse<T>;
    if (body.error) throw new Error(body.error.data?.message || body.error.message);
    return body.result as T;
  }
  async login(): Promise<number> {
    if (this.uid) return this.uid;
    const uid = await this.rpc<number>('common', 'authenticate', [this.db, this.username, this.key, {}]);
    if (!uid) throw new Error('Odoo authentication failed');
    this.uid = uid;
    return uid;
  }
  async call<T>(model: string, method: string, args: unknown[] = [], kwargs: Record<string, unknown> = {}): Promise<T> {
    const uid = await this.login();
    return this.rpc<T>('object', 'execute_kw', [this.db, uid, this.key, model, method, args, kwargs]);
  }
  async create(model: string, values: Record<string, unknown>): Promise<number> {
    return this.call<number>(model, 'create', [values]);
  }
  async write(model: string, id: number, values: Record<string, unknown>): Promise<void> {
    await this.call<boolean>(model, 'write', [[id], values]);
  }
  async searchRead<T extends Record<string, unknown>>(model: string, domain: unknown[], fields: string[], limit = 1): Promise<T[]> {
    return this.call<T[]>(model, 'search_read', [domain], { fields, limit });
  }
}

async function mapping(service: SupabaseClient, ownerId: string, type: string, id: string): Promise<MappingRow | null> {
  const { data, error } = await service.from('odoo_entity_mappings')
    .select('odoo_model,odoo_record_id').eq('owner_id', ownerId).eq('entity_type', type).eq('entity_id', id).maybeSingle();
  if (error) throw error;
  return data as MappingRow | null;
}
async function requiredMapping(service: SupabaseClient, ownerId: string, type: string, id: string): Promise<number> {
  const row = await mapping(service, ownerId, type, id);
  if (!row) throw new Error(`Required Odoo mapping is missing: ${type}:${id}. Run the general Odoo sync first.`);
  return row.odoo_record_id;
}
async function accountId(odoo: OdooClient, code: string): Promise<number> {
  const domain: unknown[] = [['code', '=', code]];
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) domain.push(['company_ids', 'in', [companyId]]);
  const rows = await odoo.searchRead<{ id: number }>('account.account', domain, ['id'], 2);
  if (!rows[0]?.id) throw new Error(`Odoo account code not found: ${code}`);
  if (rows.length > 1) throw new Error(`Odoo account code is ambiguous: ${code}`);
  return rows[0].id;
}
async function currencyId(odoo: OdooClient, code: string): Promise<number> {
  const rows = await odoo.searchRead<{ id: number }>('res.currency', [['name', '=', code]], ['id'], 1);
  if (!rows[0]?.id) throw new Error(`Odoo currency not found: ${code}`);
  return rows[0].id;
}
async function miscJournalId(odoo: OdooClient): Promise<number> {
  const configured = optionalInt('ODOO_MISC_JOURNAL_ID');
  if (configured) return configured;
  const domain: unknown[] = [['type', '=', 'general']];
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) domain.push(['company_id', '=', companyId]);
  const rows = await odoo.searchRead<{ id: number }>('account.journal', domain, ['id'], 1);
  if (!rows[0]?.id) throw new Error('No miscellaneous Odoo journal found; configure ODOO_MISC_JOURNAL_ID');
  return rows[0].id;
}
async function bankDefaultAccount(service: SupabaseClient, odoo: OdooClient, ownerId: string, bankId: string): Promise<number> {
  const journalId = await requiredMapping(service, ownerId, 'bank_account', bankId);
  const rows = await odoo.searchRead<{ id: number; default_account_id: unknown }>(
    'account.journal', [['id', '=', journalId]], ['id', 'default_account_id'], 1,
  );
  const id = relationId(rows[0]?.default_account_id);
  if (!id) throw new Error(`Odoo bank journal ${journalId} has no default account`);
  return id;
}

function foreignFields(currencyCode: string, currencyIdValue: number | null, amount: number): Record<string, unknown> {
  if (currencyCode === 'EGP' || !currencyIdValue) return {};
  return { currency_id: currencyIdValue, amount_currency: Number(amount.toFixed(4)) };
}

async function postStableMove(
  service: SupabaseClient,
  odoo: OdooClient,
  event: OutboxEvent,
  ref: string,
  values: Record<string, unknown>,
): Promise<number> {
  const mapped = await mapping(service, event.owner_id, event.entity_type, event.entity_id);
  let recordId = mapped?.odoo_record_id ?? null;
  if (!recordId) {
    const existing = await odoo.searchRead<{ id: number; state: string }>(
      'account.move', [['ref', '=', ref]], ['id', 'state'], 2,
    );
    if (existing.length > 1) throw new Error(`Multiple Odoo moves use the stable Terranex ref: ${ref}`);
    recordId = existing[0]?.id ?? null;
  }
  if (recordId) {
    const states = await odoo.searchRead<{ id: number; state: string }>('account.move', [['id', '=', recordId]], ['id', 'state'], 1);
    if (states[0]?.state === 'posted') return recordId;
    if (states[0]?.state && states[0].state !== 'draft') throw new Error(`Odoo move is not editable: ${states[0].state}`);
    await odoo.write('account.move', recordId, values);
  } else {
    recordId = await odoo.create('account.move', values);
  }
  await odoo.call('account.move', 'action_post', [[recordId]]);
  return recordId;
}

async function syncDistribution(service: SupabaseClient, odoo: OdooClient, event: OutboxEvent): Promise<number> {
  const { data: distribution, error } = await service.from('distributions').select('*')
    .eq('owner_id', event.owner_id).eq('id', event.entity_id).single();
  if (error) throw error;
  if (!['approved', 'paid'].includes(String(distribution.status))) throw new Error('Only approved distributions can post to Odoo');
  const { data: allocations, error: allocationError } = await service.from('distribution_allocations').select('*')
    .eq('owner_id', event.owner_id).eq('distribution_id', event.entity_id).order('partner_id');
  if (allocationError) throw allocationError;
  if (!allocations?.length) throw new Error('Approved distribution has no allocations');
  await requiredMapping(service, event.owner_id, 'project', String(distribution.project_id));

  const retained = await accountId(odoo, env('ODOO_RETAINED_EARNINGS_ACCOUNT_CODE'));
  const payable = await accountId(odoo, env('ODOO_DISTRIBUTION_PAYABLE_ACCOUNT_CODE'));
  const code = String(distribution.currency || 'EGP');
  const foreignId = code === 'EGP' ? null : await currencyId(odoo, code);
  const lines: unknown[] = [[0, 0, {
    name: `اعتماد توزيع أرباح ${event.entity_id}`,
    account_id: retained,
    debit: roundMoney(Number(distribution.total_amount_egp)),
    credit: 0,
    ...foreignFields(code, foreignId, Number(distribution.total_amount)),
  }]];
  let creditTotal = 0;
  for (const allocation of allocations) {
    const partnerId = await requiredMapping(service, event.owner_id, 'partner', String(allocation.partner_id));
    const base = roundMoney(Number(allocation.allocated_amount_egp));
    creditTotal = roundMoney(creditTotal + base);
    lines.push([0, 0, {
      name: 'استحقاق توزيع أرباح للشريك', account_id: payable, partner_id: partnerId,
      debit: 0, credit: base,
      ...foreignFields(code, foreignId, -Number(allocation.allocated_amount)),
    }]);
  }
  const debitTotal = roundMoney(Number(distribution.total_amount_egp));
  const difference = roundMoney(debitTotal - creditTotal);
  if (Math.abs(difference) > 0.05) throw new Error(`Distribution does not balance in EGP: ${debitTotal}/${creditTotal}`);
  if (difference !== 0) {
    const last = lines[lines.length - 1] as [number, number, Record<string, unknown>];
    last[2].credit = roundMoney(Number(last[2].credit) + difference);
  }
  const ref = `Terranex distribution:${event.entity_id}`;
  const values: Record<string, unknown> = {
    move_type: 'entry', date: distribution.distribution_date, journal_id: await miscJournalId(odoo),
    ref, narration: distribution.notes || false, line_ids: lines,
  };
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) values.company_id = companyId;
  return postStableMove(service, odoo, event, ref, values);
}

async function syncLedgerEntry(service: SupabaseClient, odoo: OdooClient, event: OutboxEvent): Promise<number> {
  const { data: entry, error } = await service.from('partner_ledger_entries').select('*')
    .eq('owner_id', event.owner_id).eq('id', event.entity_id).single();
  if (error) throw error;
  let source = entry;
  let reverse = false;
  if (entry.entry_type === 'reversal') {
    if (!entry.reversal_of_id) throw new Error('Ledger reversal has no original entry');
    const { data: original, error: originalError } = await service.from('partner_ledger_entries').select('*')
      .eq('owner_id', event.owner_id).eq('id', entry.reversal_of_id).single();
    if (originalError) throw originalError;
    source = original;
    reverse = true;
  }
  if (!['capital_contribution', 'withdrawal', 'distribution_payment'].includes(String(source.entry_type))) {
    throw new Error(`Unsupported investor accounting entry: ${source.entry_type}`);
  }
  if (!entry.bank_account_id) throw new Error('Investor cash entry has no bank account');
  await requiredMapping(service, event.owner_id, 'project', String(entry.project_id));
  const partnerId = await requiredMapping(service, event.owner_id, 'partner', String(entry.partner_id));
  const bank = await bankDefaultAccount(service, odoo, event.owner_id, String(entry.bank_account_id));
  const capital = await accountId(odoo, env('ODOO_PARTNER_CAPITAL_ACCOUNT_CODE'));
  const payable = await accountId(odoo, env('ODOO_DISTRIBUTION_PAYABLE_ACCOUNT_CODE'));
  const code = String(entry.currency || 'EGP');
  const foreignId = code === 'EGP' ? null : await currencyId(odoo, code);
  const base = roundMoney(Number(entry.amount_egp));
  const originalAmount = Number(entry.amount);

  let debitAccount: number;
  let creditAccount: number;
  let label: string;
  if (source.entry_type === 'capital_contribution') {
    debitAccount = bank; creditAccount = capital; label = 'مساهمة رأسمالية';
  } else if (source.entry_type === 'withdrawal') {
    debitAccount = capital; creditAccount = bank; label = 'سحب من رأس المال';
  } else {
    debitAccount = payable; creditAccount = bank; label = 'سداد توزيع أرباح';
  }
  if (reverse) [debitAccount, creditAccount] = [creditAccount, debitAccount];
  const signed = reverse ? -originalAmount : originalAmount;
  const lines: unknown[] = [
    [0, 0, {
      name: reverse ? `عكس ${label}` : label, account_id: debitAccount,
      partner_id: debitAccount === bank ? false : partnerId, debit: base, credit: 0,
      ...foreignFields(code, foreignId, signed),
    }],
    [0, 0, {
      name: reverse ? `عكس ${label}` : label, account_id: creditAccount,
      partner_id: creditAccount === bank ? false : partnerId, debit: 0, credit: base,
      ...foreignFields(code, foreignId, -signed),
    }],
  ];
  const ref = `Terranex ledger:${event.entity_id}`;
  const values: Record<string, unknown> = {
    move_type: 'entry', date: entry.posting_date, journal_id: await miscJournalId(odoo),
    ref, narration: entry.notes || false, line_ids: lines,
  };
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) values.company_id = companyId;
  return postStableMove(service, odoo, event, ref, values);
}

async function processEvent(service: SupabaseClient, odoo: OdooClient, event: OutboxEvent): Promise<number> {
  return event.entity_type === 'distribution'
    ? syncDistribution(service, odoo, event)
    : syncLedgerEntry(service, odoo, event);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) throw new Error('Missing Authorization header');
    const url = env('SUPABASE_URL');
    const anon = env('SUPABASE_ANON_KEY');
    const serviceKey = env('SUPABASE_SERVICE_ROLE_KEY');
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: settings, error: settingsError } = await service.from('company_settings')
      .select('odoo_enabled,country,base_currency,odoo_localization')
      .eq('owner_id', userData.user.id).maybeSingle();
    if (settingsError) throw settingsError;
    if (!settings?.odoo_enabled) return new Response(JSON.stringify({ processed: 0, skipped: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
    if (settings.country !== 'EG' || settings.base_currency !== 'EGP' || settings.odoo_localization !== 'l10n_eg') {
      throw new Error('Investor bridge is configured for Egypt (EG/EGP/l10n_eg)');
    }
    let limit = 20;
    try {
      const body = await request.json() as { limit?: number };
      if (body.limit !== undefined) limit = Math.max(1, Math.min(100, Math.trunc(body.limit)));
    } catch { /* empty body */ }
    const workerId = crypto.randomUUID();
    const { data: rows, error: claimError } = await service.rpc('claim_odoo_investor_sync_batch', {
      p_owner_id: userData.user.id, p_limit: limit, p_worker_id: workerId,
    });
    if (claimError) throw claimError;
    const odoo = new OdooClient();
    const results: Array<{ eventId: string; status: 'synced' | 'failed'; error?: string }> = [];
    for (const event of (rows ?? []) as OutboxEvent[]) {
      try {
        const recordId = await processEvent(service, odoo, event);
        const { error } = await service.rpc('complete_odoo_sync', {
          p_event_id: event.id, p_odoo_model: 'account.move', p_odoo_record_id: recordId,
          p_metadata: { worker_id: workerId, investor_accounting: true, egypt_localization: 'l10n_eg' },
        });
        if (error) throw error;
        results.push({ eventId: event.id, status: 'synced' });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const retry = Math.min(3600, 30 * (2 ** Math.min(event.attempt_count, 6)));
        await service.rpc('fail_odoo_sync', { p_event_id: event.id, p_error: message, p_retry_seconds: retry });
        results.push({ eventId: event.id, status: 'failed', error: message });
      }
    }
    return new Response(JSON.stringify({
      processed: results.length,
      synced: results.filter(item => item.status === 'synced').length,
      failed: results.filter(item => item.status === 'failed').length,
      results,
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
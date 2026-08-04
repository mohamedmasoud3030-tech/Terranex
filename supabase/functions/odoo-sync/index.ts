import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

type EntityType =
  | 'partner'
  | 'project'
  | 'sales_invoice'
  | 'purchase_invoice'
  | 'bank_account'
  | 'sales_payment'
  | 'purchase_payment';
type InvoiceEntityType = 'sales_invoice' | 'purchase_invoice';
type PaymentEntityType = 'sales_payment' | 'purchase_payment';
type Operation = 'upsert' | 'void';

interface OutboxEvent {
  id: string;
  owner_id: string;
  entity_type: EntityType;
  entity_id: string;
  operation: Operation;
  attempt_count: number;
}

interface MappingRow {
  odoo_model: string;
  odoo_record_id: number;
}

interface OdooAction {
  res_id?: number;
  domain?: unknown;
}

interface JsonRpcResponse<T> {
  jsonrpc: '2.0';
  id: number;
  result?: T;
  error?: {
    code: number;
    message: string;
    data?: { message?: string; debug?: string; name?: string };
  };
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
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

class OdooServerClient {
  private readonly baseUrl: string;
  private readonly db: string;
  private readonly username: string;
  private readonly apiKey: string;
  private uid: number | null = null;
  private requestId = 1;

  constructor() {
    this.baseUrl = env('ODOO_URL').replace(/\/$/, '');
    this.db = env('ODOO_DB');
    this.username = env('ODOO_USERNAME');
    this.apiKey = env('ODOO_API_KEY');
  }

  private async rpc<T>(service: string, method: string, args: unknown[]): Promise<T> {
    const response = await fetch(`${this.baseUrl}/jsonrpc`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'call',
        params: { service, method, args },
        id: this.requestId++,
      }),
    });
    if (!response.ok) throw new Error(`Odoo HTTP ${response.status}`);
    const body = await response.json() as JsonRpcResponse<T>;
    if (body.error) {
      throw new Error(body.error.data?.message || body.error.message || 'Unknown Odoo error');
    }
    return body.result as T;
  }

  async login(): Promise<number> {
    if (this.uid !== null) return this.uid;
    const uid = await this.rpc<number>('common', 'authenticate', [
      this.db,
      this.username,
      this.apiKey,
      {},
    ]);
    if (!uid || typeof uid !== 'number') throw new Error('Odoo authentication failed');
    this.uid = uid;
    return uid;
  }

  async callKw<T>(
    model: string,
    method: string,
    args: unknown[] = [],
    kwargs: Record<string, unknown> = {},
  ): Promise<T> {
    const uid = await this.login();
    return this.rpc<T>('object', 'execute_kw', [
      this.db,
      uid,
      this.apiKey,
      model,
      method,
      args,
      kwargs,
    ]);
  }

  async create(
    model: string,
    values: Record<string, unknown>,
    context?: Record<string, unknown>,
  ): Promise<number> {
    return this.callKw<number>(model, 'create', [values], context ? { context } : {});
  }

  async write(model: string, id: number, values: Record<string, unknown>): Promise<void> {
    await this.callKw<boolean>(model, 'write', [[id], values]);
  }

  async searchRead<T extends Record<string, unknown>>(
    model: string,
    domain: unknown[],
    fields: string[],
    limit = 1,
  ): Promise<T[]> {
    return this.callKw<T[]>(model, 'search_read', [domain], { fields, limit });
  }
}

async function getMapping(
  service: SupabaseClient,
  ownerId: string,
  entityType: EntityType,
  entityId: string,
): Promise<MappingRow | null> {
  const { data, error } = await service
    .from('odoo_entity_mappings')
    .select('odoo_model,odoo_record_id')
    .eq('owner_id', ownerId)
    .eq('entity_type', entityType)
    .eq('entity_id', entityId)
    .maybeSingle();
  if (error) throw error;
  return data as MappingRow | null;
}

type MutableDependencyType = 'partner' | 'project' | 'bank_account';

async function saveDependencyMapping(
  service: SupabaseClient,
  ownerId: string,
  entityType: MutableDependencyType,
  entityId: string,
  model: string,
  recordId: number,
): Promise<void> {
  const { error } = await service.from('odoo_entity_mappings').upsert({
    owner_id: ownerId,
    entity_type: entityType,
    entity_id: entityId,
    odoo_model: model,
    odoo_record_id: recordId,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: 'owner_id,entity_type,entity_id' });
  if (error) throw error;

  const tableByType: Record<MutableDependencyType, string> = {
    partner: 'partners',
    project: 'projects',
    bank_account: 'bank_accounts',
  };
  const { error: updateError } = await service
    .from(tableByType[entityType])
    .update({ odoo_res_id: recordId })
    .eq('owner_id', ownerId)
    .eq('id', entityId);
  if (updateError) throw updateError;
}

function partnerValues(partner: Record<string, unknown>): Record<string, unknown> {
  const role = String(partner.counterparty_role ?? '');
  const isEquity = partner.category === 'equity_partner';
  return {
    name: String(partner.name_ar || partner.name_en || partner.id),
    company_type: isEquity ? 'company' : 'person',
    customer_rank: role === 'client' || isEquity ? 1 : 0,
    supplier_rank: ['supplier', 'service_provider'].includes(role) ? 1 : 0,
    phone: partner.phone || false,
    email: partner.email || false,
    street: partner.address || false,
    comment: [partner.name_en ? `EN: ${partner.name_en}` : '', partner.notes || '']
      .filter(Boolean)
      .join('\n'),
    ref: String(partner.id),
  };
}

async function syncPartnerRecord(
  service: SupabaseClient,
  odoo: OdooServerClient,
  ownerId: string,
  partnerId: string,
): Promise<number> {
  const { data, error } = await service
    .from('partners')
    .select('*')
    .eq('owner_id', ownerId)
    .eq('id', partnerId)
    .single();
  if (error) throw error;
  const mapping = await getMapping(service, ownerId, 'partner', partnerId);
  if (mapping) {
    await odoo.write('res.partner', mapping.odoo_record_id, partnerValues(data));
    return mapping.odoo_record_id;
  }
  const recordId = await odoo.create('res.partner', partnerValues(data));
  await saveDependencyMapping(service, ownerId, 'partner', partnerId, 'res.partner', recordId);
  return recordId;
}

async function analyticPlanId(odoo: OdooServerClient): Promise<number> {
  const configured = optionalInt('ODOO_ANALYTIC_PLAN_ID');
  if (configured) return configured;
  const rows = await odoo.searchRead<{ id: number }>('account.analytic.plan', [], ['id'], 1);
  if (!rows[0]?.id) throw new Error('No Odoo analytic plan found; configure ODOO_ANALYTIC_PLAN_ID');
  return rows[0].id;
}

async function syncProjectRecord(
  service: SupabaseClient,
  odoo: OdooServerClient,
  ownerId: string,
  projectId: string,
): Promise<number> {
  const { data, error } = await service
    .from('projects')
    .select('*')
    .eq('owner_id', ownerId)
    .eq('id', projectId)
    .single();
  if (error) throw error;
  const values: Record<string, unknown> = {
    name: String(data.name_ar || data.name_en || data.id),
    code: String(data.id).replaceAll('-', '').slice(0, 12).toUpperCase(),
    plan_id: await analyticPlanId(odoo),
    active: !['cancelled', 'completed'].includes(String(data.status ?? '')),
  };
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) values.company_id = companyId;

  const mapping = await getMapping(service, ownerId, 'project', projectId);
  if (mapping) {
    await odoo.write('account.analytic.account', mapping.odoo_record_id, values);
    return mapping.odoo_record_id;
  }
  const recordId = await odoo.create('account.analytic.account', values);
  await saveDependencyMapping(service, ownerId, 'project', projectId, 'account.analytic.account', recordId);
  return recordId;
}

async function currencyId(odoo: OdooServerClient, code: string): Promise<number> {
  const rows = await odoo.searchRead<{ id: number }>('res.currency', [['name', '=', code]], ['id'], 1);
  if (!rows[0]?.id) throw new Error(`Odoo currency not found: ${code}`);
  return rows[0].id;
}

function journalCode(bankAccountId: string): string {
  return `T${bankAccountId.replaceAll('-', '').slice(0, 4).toUpperCase()}`;
}

async function syncBankAccountRecord(
  service: SupabaseClient,
  odoo: OdooServerClient,
  ownerId: string,
  bankAccountId: string,
): Promise<number> {
  const { data, error } = await service
    .from('bank_accounts')
    .select('*')
    .eq('owner_id', ownerId)
    .eq('id', bankAccountId)
    .single();
  if (error) throw error;

  const values: Record<string, unknown> = {
    name: String(data.name_ar || data.name_en || data.bank_name || data.id),
    code: journalCode(bankAccountId),
    type: data.account_type === 'cash' ? 'cash' : 'bank',
    currency_id: await currencyId(odoo, String(data.currency || 'EGP')),
    active: !data.is_archived,
  };
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) values.company_id = companyId;

  const mapping = await getMapping(service, ownerId, 'bank_account', bankAccountId);
  if (mapping) {
    await odoo.write('account.journal', mapping.odoo_record_id, values);
    return mapping.odoo_record_id;
  }
  const recordId = await odoo.create('account.journal', values);
  await saveDependencyMapping(service, ownerId, 'bank_account', bankAccountId, 'account.journal', recordId);
  return recordId;
}

async function taxId(
  odoo: OdooServerClient,
  rate: number,
  use: 'sale' | 'purchase',
): Promise<number | null> {
  if (!rate) return null;
  const domain: unknown[] = [
    ['amount', '=', rate],
    ['type_tax_use', '=', use],
    ['active', '=', true],
  ];
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) domain.push(['company_id', '=', companyId]);
  const rows = await odoo.searchRead<{ id: number }>('account.tax', domain, ['id'], 1);
  if (!rows[0]?.id) {
    throw new Error(`No active Odoo ${use} tax found for rate ${rate}% under l10n_eg`);
  }
  return rows[0].id;
}

async function syncInvoiceRecord(
  service: SupabaseClient,
  odoo: OdooServerClient,
  event: OutboxEvent & { entity_type: InvoiceEntityType },
): Promise<{ model: string; recordId: number }> {
  const isSale = event.entity_type === 'sales_invoice';
  const table = isSale ? 'sales_invoices' : 'purchase_invoices';
  const linesTable = isSale ? 'sales_invoice_lines' : 'purchase_invoice_lines';
  const { data: invoice, error } = await service
    .from(table)
    .select('*')
    .eq('owner_id', event.owner_id)
    .eq('id', event.entity_id)
    .single();
  if (error) throw error;

  const mapping = await getMapping(service, event.owner_id, event.entity_type, event.entity_id);
  if (event.operation === 'void') {
    if (!mapping) throw new Error('Cannot void invoice before it has an Odoo mapping');
    await odoo.callKw('account.move', 'button_cancel', [[mapping.odoo_record_id]]);
    return { model: 'account.move', recordId: mapping.odoo_record_id };
  }

  if (!invoice.partner_id) throw new Error('Invoice must have a partner before Odoo posting');
  const partnerId = await syncPartnerRecord(service, odoo, event.owner_id, String(invoice.partner_id));
  const projectId = invoice.project_id
    ? await syncProjectRecord(service, odoo, event.owner_id, String(invoice.project_id))
    : null;
  const { data: lines, error: linesError } = await service
    .from(linesTable)
    .select('*')
    .eq('owner_id', event.owner_id)
    .eq('invoice_id', event.entity_id)
    .order('line_no');
  if (linesError) throw linesError;
  if (!lines?.length) throw new Error('Invoice has no lines');

  const invoiceTaxId = await taxId(odoo, Number(invoice.vat_rate ?? 0), isSale ? 'sale' : 'purchase');
  const lineCommands = lines.map((line: Record<string, unknown>) => {
    const values: Record<string, unknown> = {
      name: String(line.description_ar || line.description_en || 'بند'),
      quantity: Number(line.quantity ?? 1),
      price_unit: Number(line.unit_price ?? 0),
    };
    if (invoiceTaxId) values.tax_ids = [[6, 0, [invoiceTaxId]]];
    if (projectId) values.analytic_distribution = { [String(projectId)]: 100 };
    return [0, 0, values];
  });

  const values: Record<string, unknown> = {
    move_type: isSale ? 'out_invoice' : 'in_invoice',
    partner_id: partnerId,
    invoice_date: invoice.issue_date,
    invoice_date_due: invoice.due_date || false,
    currency_id: await currencyId(odoo, String(invoice.currency || 'EGP')),
    ref: isSale
      ? String(invoice.invoice_number)
      : String(invoice.vendor_invoice_number || invoice.invoice_number),
    invoice_origin: `Terranex:${event.entity_id}`,
    invoice_line_ids: lineCommands,
  };
  const companyId = optionalInt('ODOO_COMPANY_ID');
  if (companyId) values.company_id = companyId;

  let recordId: number;
  if (mapping) {
    const states = await odoo.searchRead<{ id: number; state: string }>(
      'account.move',
      [['id', '=', mapping.odoo_record_id]],
      ['id', 'state'],
      1,
    );
    if (states[0]?.state === 'draft') await odoo.write('account.move', mapping.odoo_record_id, values);
    recordId = mapping.odoo_record_id;
  } else {
    recordId = await odoo.create('account.move', values);
  }

  const states = await odoo.searchRead<{ id: number; state: string }>(
    'account.move',
    [['id', '=', recordId]],
    ['id', 'state'],
    1,
  );
  if (states[0]?.state === 'draft') {
    await odoo.callKw('account.move', 'action_post', [[recordId]]);
  }
  return { model: 'account.move', recordId };
}

function paymentIdFromAction(action: OdooAction | boolean): number | null {
  if (typeof action !== 'object' || action === null) return null;
  if (typeof action.res_id === 'number' && action.res_id > 0) return action.res_id;
  if (!Array.isArray(action.domain)) return null;
  for (const item of action.domain) {
    if (!Array.isArray(item) || item[0] !== 'id' || item[1] !== 'in' || !Array.isArray(item[2])) continue;
    const first = item[2][0];
    if (typeof first === 'number' && first > 0) return first;
  }
  return null;
}

async function syncPaymentRecord(
  service: SupabaseClient,
  odoo: OdooServerClient,
  event: OutboxEvent & { entity_type: PaymentEntityType },
): Promise<{ model: string; recordId: number }> {
  const existing = await getMapping(service, event.owner_id, event.entity_type, event.entity_id);
  if (existing) return { model: 'account.payment', recordId: existing.odoo_record_id };

  const isSale = event.entity_type === 'sales_payment';
  const paymentTable = isSale ? 'invoice_payments' : 'purchase_invoice_payments';
  const invoiceType: InvoiceEntityType = isSale ? 'sales_invoice' : 'purchase_invoice';
  const { data: payment, error } = await service
    .from(paymentTable)
    .select('*')
    .eq('owner_id', event.owner_id)
    .eq('id', event.entity_id)
    .single();
  if (error) throw error;
  if (isSale && payment.is_reversed) throw new Error('Reversed Terranex payments are not posted to Odoo');
  if (!payment.bank_account_id) throw new Error('A bank or cash account is required before Odoo payment posting');

  let invoiceMapping = await getMapping(service, event.owner_id, invoiceType, String(payment.invoice_id));
  if (!invoiceMapping) {
    const invoiceResult = await syncInvoiceRecord(service, odoo, {
      ...event,
      entity_type: invoiceType,
      entity_id: String(payment.invoice_id),
      operation: 'upsert',
    });
    invoiceMapping = { odoo_model: invoiceResult.model, odoo_record_id: invoiceResult.recordId };
  }

  const journalId = await syncBankAccountRecord(
    service,
    odoo,
    event.owner_id,
    String(payment.bank_account_id),
  );
  const paymentCurrencyId = await currencyId(odoo, String(payment.currency || 'EGP'));
  const communication = `Terranex:${event.entity_id}`;
  const context = {
    active_model: 'account.move',
    active_id: invoiceMapping.odoo_record_id,
    active_ids: [invoiceMapping.odoo_record_id],
    default_journal_id: journalId,
  };

  const wizardId = await odoo.create('account.payment.register', {
    payment_date: payment.payment_date,
    amount: Number(payment.amount),
    currency_id: paymentCurrencyId,
    journal_id: journalId,
    communication,
    group_payment: true,
    payment_difference_handling: 'open',
  }, context);

  const action = await odoo.callKw<OdooAction | boolean>(
    'account.payment.register',
    'action_create_payments',
    [[wizardId]],
    { context },
  );
  let recordId = paymentIdFromAction(action);
  if (!recordId) {
    const rows = await odoo.searchRead<{ id: number }>(
      'account.payment',
      [['memo', '=', communication]],
      ['id'],
      1,
    );
    recordId = rows[0]?.id ?? null;
  }
  if (!recordId) throw new Error('Odoo created the payment but did not return a stable payment id');
  return { model: 'account.payment', recordId };
}

async function processEvent(
  service: SupabaseClient,
  odoo: OdooServerClient,
  event: OutboxEvent,
): Promise<{ model: string; recordId: number }> {
  if (event.entity_type === 'partner') {
    return { model: 'res.partner', recordId: await syncPartnerRecord(service, odoo, event.owner_id, event.entity_id) };
  }
  if (event.entity_type === 'project') {
    return {
      model: 'account.analytic.account',
      recordId: await syncProjectRecord(service, odoo, event.owner_id, event.entity_id),
    };
  }
  if (event.entity_type === 'bank_account') {
    return {
      model: 'account.journal',
      recordId: await syncBankAccountRecord(service, odoo, event.owner_id, event.entity_id),
    };
  }
  if (event.entity_type === 'sales_payment' || event.entity_type === 'purchase_payment') {
    return syncPaymentRecord(service, odoo, event as OutboxEvent & { entity_type: PaymentEntityType });
  }
  return syncInvoiceRecord(service, odoo, event as OutboxEvent & { entity_type: InvoiceEntityType });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) throw new Error('Missing Authorization header');

    const supabaseUrl = env('SUPABASE_URL');
    const anonKey = env('SUPABASE_ANON_KEY');
    const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY');
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const service = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data: settings, error: settingsError } = await service
      .from('company_settings')
      .select('odoo_enabled,country,base_currency,odoo_localization')
      .eq('owner_id', userData.user.id)
      .maybeSingle();
    if (settingsError) throw settingsError;
    if (!settings?.odoo_enabled) {
      return new Response(JSON.stringify({ processed: 0, skipped: true, reason: 'Odoo is disabled in company settings' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (settings.country !== 'EG' || settings.base_currency !== 'EGP') {
      throw new Error('This bridge phase is configured for Egypt (EG/EGP) first');
    }
    if (settings.odoo_localization !== 'l10n_eg') {
      throw new Error('Company Odoo localization must be l10n_eg');
    }

    let limit = 20;
    try {
      const body = await request.json() as { limit?: number };
      if (body.limit !== undefined) limit = Math.max(1, Math.min(100, Math.trunc(body.limit)));
    } catch {
      // Empty body is valid.
    }

    const workerId = crypto.randomUUID();
    const { data: events, error: claimError } = await service.rpc('claim_odoo_sync_batch', {
      p_owner_id: userData.user.id,
      p_limit: limit,
      p_worker_id: workerId,
    });
    if (claimError) throw claimError;

    const odoo = new OdooServerClient();
    const results: Array<{ eventId: string; status: 'synced' | 'failed'; error?: string }> = [];
    for (const event of (events ?? []) as OutboxEvent[]) {
      try {
        const synced = await processEvent(service, odoo, event);
        const { error: completeError } = await service.rpc('complete_odoo_sync', {
          p_event_id: event.id,
          p_odoo_model: synced.model,
          p_odoo_record_id: synced.recordId,
          p_metadata: { worker_id: workerId, egypt_localization: 'l10n_eg' },
        });
        if (completeError) throw completeError;
        results.push({ eventId: event.id, status: 'synced' });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const retrySeconds = Math.min(3600, 30 * (2 ** Math.min(event.attempt_count, 6)));
        await service.rpc('fail_odoo_sync', {
          p_event_id: event.id,
          p_error: message,
          p_retry_seconds: retrySeconds,
        });
        results.push({ eventId: event.id, status: 'failed', error: message });
      }
    }

    return new Response(JSON.stringify({
      processed: results.length,
      synced: results.filter((item) => item.status === 'synced').length,
      failed: results.filter((item) => item.status === 'failed').length,
      results,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
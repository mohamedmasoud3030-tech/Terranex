/**
 * Odoo sync helpers — best-effort, non-blocking.
 *
 * The OdooClient is constructed at runtime from `company_settings` (URL, DB,
 * username, API key) so users can toggle integration on/off without
 * rebuilding. Calls always swallow errors to guarantee that a misconfigured
 * or offline Odoo instance never blocks local writes.
 */
import { createOdooClient, OdooClient, setOdooClient } from './client';
import { syncPartner } from './sync/partners';
import { syncProjectAsAnalyticAccount } from './sync/projects';
import { syncTransactionAsMove } from './sync/transactions';
import type { Partner, Project, Transaction } from '../types/domain';
import { requireClient } from '../storage/supabaseClientRegistry';

let cachedRuntimeClient: OdooClient | null = null;
let cachedRuntimeKey = '';

export async function getRuntimeOdooClient(): Promise<OdooClient | null> {
  try {
    const supabase = requireClient();
    const { data } = await supabase
      .from('company_settings')
      .select('odoo_enabled, odoo_url, odoo_db, odoo_username, odoo_api_key')
      .maybeSingle();
    if (!data?.odoo_enabled || !data.odoo_url || !data.odoo_db || !data.odoo_username || !data.odoo_api_key) {
      cachedRuntimeClient = null;
      cachedRuntimeKey = '';
      setOdooClient(null);
      return null;
    }
    const key = `${data.odoo_url}|${data.odoo_db}|${data.odoo_username}|${data.odoo_api_key}`;
    if (cachedRuntimeClient && cachedRuntimeKey === key) return cachedRuntimeClient;
    cachedRuntimeClient = createOdooClient({
      url: data.odoo_url,
      db: data.odoo_db,
      username: data.odoo_username,
      apiKey: data.odoo_api_key,
    });
    cachedRuntimeKey = key;
    setOdooClient(cachedRuntimeClient);
    await cachedRuntimeClient.login();
    return cachedRuntimeClient;
  } catch {
    return null;
  }
}

/** Fire-and-forget partner sync. Returns the Odoo res.partner id or null. */
export async function syncPartnerToOdoo(partner: Partner): Promise<number | null> {
  try {
    const client = await getRuntimeOdooClient();
    if (!client) return null;
    const existing = (partner as unknown as { odoo_res_id?: number }).odoo_res_id;
    const res = await syncPartner(client, partner);
    if (res.created && res.odooId && !existing) {
      const supabase = requireClient();
      await supabase.from('partners').update({ odoo_res_id: res.odooId }).eq('id', partner.id);
    }
    return res.odooId;
  } catch {
    return null;
  }
}

/** Fire-and-forget project → analytic account sync. */
export async function syncProjectToOdoo(project: Project): Promise<number | null> {
  try {
    const client = await getRuntimeOdooClient();
    if (!client) return null;
    const existing = (project as unknown as { odoo_res_id?: number }).odoo_res_id;
    const res = await syncProjectAsAnalyticAccount(client, project, existing);
    if (res.created && res.odooId && !existing) {
      const supabase = requireClient();
      await supabase.from('projects').update({ odoo_res_id: res.odooId }).eq('id', project.id);
    }
    return res.odooId;
  } catch {
    return null;
  }
}

/** Fire-and-forget transaction → journal entry sync. */
export async function syncTransactionToOdoo(
  transaction: Transaction,
  ctx?: { partner?: Partner; project?: Project },
): Promise<number | null> {
  try {
    const client = await getRuntimeOdooClient();
    if (!client) return null;
    const moveId = await syncTransactionAsMove(client, transaction, {
      partner: ctx?.partner,
      project: ctx?.project,
      // Sensible defaults for a fresh Odoo chart of accounts; users can
      // configure these later in company settings.
      miscJournalId: 1,
      defaultRevenueAccountId: undefined,
      defaultExpenseAccountId: undefined,
    });
    if (moveId) {
      const supabase = requireClient();
      await supabase.from('transactions').update({ odoo_res_id: moveId }).eq('id', transaction.id);
    }
    return moveId;
  } catch {
    return null;
  }
}

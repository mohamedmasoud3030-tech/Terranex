/**
 * Types for the Terranex → Odoo sync layer.
 *
 * For every Terranex entity that can sync to Odoo we record the Odoo res_id
 * on the source row itself, in an `odoo_res_id` column / field added via
 * a new migration. The sync is one-way for Phase 1 (Terranex → Odoo);
 * reverse sync (Odoo → Terranex) is out of scope until a dedicated
 * terranex_sync Odoo addon exists.
 */

/** Odoo model names used by the sync. */
export const ODOO_MODELS = {
  partner: 'res.partner',
  analyticAccount: 'account.analytic.account',
  account: 'account.account',
  journal: 'account.journal',
  move: 'account.move',
  payment: 'account.payment',
  bankJournal: 'account.journal',
  product: 'product.product',
} as const;

export type OdooModelName = (typeof ODOO_MODELS)[keyof typeof ODOO_MODELS];

/** Direction of a sync job. */
export type SyncDirection = 'terranex_to_odoo' | 'odoo_to_terranex';

/** Sync job status. */
export type SyncStatus = 'pending' | 'ok' | 'error' | 'skipped';

/** A record written to the local sync log for auditing. */
export interface SyncLogEntry {
  id: string;
  owner_id: string;
  direction: SyncDirection;
  source_model: string; // e.g. 'partners'
  source_id: string;
  odoo_model: OdooModelName;
  odoo_res_id?: number;
  status: SyncStatus;
  error_message?: string;
  created_at: string;
}

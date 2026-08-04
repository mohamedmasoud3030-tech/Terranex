/**
 * Browser-safe Odoo synchronization entry point.
 *
 * Business writes enqueue outbox rows inside Postgres triggers. The browser
 * only asks authenticated Supabase Edge Functions to drain this tenant's
 * queues; Odoo credentials remain server-side secrets.
 */
import { requireClient } from '../storage/supabaseClientRegistry';
import type { Partner, Project, Transaction } from '../types/domain';

export interface OdooSyncRunResult {
  processed: number;
  synced?: number;
  failed?: number;
  skipped?: boolean;
  reason?: string;
}

let inFlight: Promise<OdooSyncRunResult | null> | null = null;

export async function getRuntimeOdooClient(): Promise<null> {
  // Direct browser-to-Odoo access is intentionally prohibited.
  return null;
}

async function invokeWorker(name: 'odoo-sync' | 'odoo-investor-sync', limit: number): Promise<OdooSyncRunResult> {
  const supabase = requireClient();
  const { data, error } = await supabase.functions.invoke(name, { body: { limit } });
  if (error) throw new Error(`تعذر تشغيل مزامنة Odoo (${name}): ${error.message}`);
  return (data ?? { processed: 0 }) as OdooSyncRunResult;
}

/**
 * Drain operational dependencies first, then investor accounting. This order
 * ensures partner, project, and bank-journal mappings exist before capital or
 * distribution moves are posted. Concurrent UI calls share one request.
 */
export function requestOdooSync(limit = 20): Promise<OdooSyncRunResult | null> {
  if (inFlight) return inFlight;
  inFlight = (async () => {
    const safeLimit = Math.max(1, Math.min(100, Math.trunc(limit)));
    const general = await invokeWorker('odoo-sync', safeLimit);
    const investor = await invokeWorker('odoo-investor-sync', safeLimit);
    return {
      processed: general.processed + investor.processed,
      synced: (general.synced ?? 0) + (investor.synced ?? 0),
      failed: (general.failed ?? 0) + (investor.failed ?? 0),
      skipped: Boolean(general.skipped && investor.skipped),
      reason: [general.reason, investor.reason].filter(Boolean).join(' | ') || undefined,
    };
  })().finally(() => {
    inFlight = null;
  });
  return inFlight;
}

async function drainWithoutBlockingBusinessWrite(): Promise<null> {
  try {
    await requestOdooSync();
  } catch {
    // Durable outbox rows remain pending/failed and can be retried later.
  }
  return null;
}

/** Partner row is already queued transactionally by its database trigger. */
export async function syncPartnerToOdoo(_partner: Partner): Promise<number | null> {
  return drainWithoutBlockingBusinessWrite();
}

/** Project row is already queued transactionally by its database trigger. */
export async function syncProjectToOdoo(_project: Project): Promise<number | null> {
  return drainWithoutBlockingBusinessWrite();
}

/**
 * Generic operational transactions are still intentionally excluded. Explicit
 * invoices, payments, manual vouchers, capital, and distributions have their
 * own authoritative accounting boundaries.
 */
export async function syncTransactionToOdoo(
  _transaction: Transaction,
  _ctx?: { partner?: Partner; project?: Project },
): Promise<number | null> {
  return null;
}
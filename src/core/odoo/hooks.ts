/**
 * Browser-safe Odoo synchronization entry point.
 *
 * Business writes enqueue outbox rows inside Postgres triggers. The browser
 * only asks the authenticated Supabase Edge Function to drain this tenant's
 * queue; Odoo credentials remain server-side secrets.
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

/**
 * Drain pending Odoo outbox events for the signed-in owner.
 * Concurrent UI calls share one request so form saves cannot start a worker
 * stampede. A failed sync never rolls back the already-committed Terranex row;
 * the outbox retains the failure and retries with backoff.
 */
export function requestOdooSync(limit = 20): Promise<OdooSyncRunResult | null> {
  if (inFlight) return inFlight;
  inFlight = (async () => {
    const supabase = requireClient();
    const { data, error } = await supabase.functions.invoke('odoo-sync', {
      body: { limit: Math.max(1, Math.min(100, Math.trunc(limit))) },
    });
    if (error) throw new Error(`تعذر تشغيل مزامنة Odoo: ${error.message}`);
    return (data ?? null) as OdooSyncRunResult | null;
  })().finally(() => {
    inFlight = null;
  });
  return inFlight;
}

async function drainWithoutBlockingBusinessWrite(): Promise<null> {
  try {
    await requestOdooSync();
  } catch {
    // The durable outbox remains pending/failed and can be retried later.
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
 * Transaction accounting is the next bridge slice. Keep this call browser-safe
 * without claiming that operational transactions are already posted to Odoo.
 */
export async function syncTransactionToOdoo(
  _transaction: Transaction,
  _ctx?: { partner?: Partner; project?: Project },
): Promise<number | null> {
  return null;
}

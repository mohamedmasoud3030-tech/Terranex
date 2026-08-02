/**
 * Odoo sync helpers — DISABLED on the browser for security.
 *
 * SECURITY POLICY:
 * The Odoo API key is a privileged secret and MUST NOT be bundled in the
 * browser or read from client-accessible storage. All Odoo synchronization
 * must run through a server-side boundary (Supabase Edge Function) that
 * holds the API key as a server-side secret and performs per-owner RLS
 * validation before forwarding calls to Odoo's JSON-RPC.
 *
 * The functions below are intentionally stubbed to no-op (return null) so
 * that existing call sites keep compiling while not leaking any secret.
 * When the Edge Function is deployed these will invoke supabase.functions.invoke().
 */
import type { Partner, Project, Transaction } from '../types/domain';

export async function getRuntimeOdooClient(): Promise<null> {
  // Intentionally returns null — client holds no credentials.
  return null;
}

/** Fire-and-forget partner sync → server (currently no-op until Edge Function lands). */
export async function syncPartnerToOdoo(_partner: Partner): Promise<number | null> {
  // TODO: invoke supabase.functions.invoke('odoo-sync', { body: { kind: 'partner', id } })
  return null;
}

/** Fire-and-forget project → analytic account sync. */
export async function syncProjectToOdoo(_project: Project): Promise<number | null> {
  return null;
}

/** Fire-and-forget transaction → journal entry sync. */
export async function syncTransactionToOdoo(
  _transaction: Transaction,
  _ctx?: { partner?: Partner; project?: Project },
): Promise<number | null> {
  return null;
}

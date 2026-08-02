/**
 * Project sync: Terranex Project → Odoo account.analytic.account
 *
 * Odoo's Analytic Accounting gives us project-level profitability, which
 * maps 1:1 to Terranex Projects. Every financial movement posted to Odoo is
 * tagged with the matching analytic account so that the accountant can run
 * per-project P&L reports inside Odoo as well as in Terranex.
 */
import type { Project } from '../../types/domain';
import type { OdooClient } from '../client';

function mapProjectToAnalyticAccount(project: Project) {
  return {
    name: project.name_ar,
    // Plan 1 is the default "Projects" analytic plan in Odoo accounting
    plan_id: 1,
    active: project.status !== 'cancelled' && project.status !== 'completed',
    company_id: 1, // default company; refine when multi-company is needed
    note: [
      project.name_en ? `EN: ${project.name_en}` : '',
      project.description_ar || '',
    ].filter(Boolean).join('\n'),
    // store terranex id for cross-reference
    ref: project.id,
  };
}

export async function syncProjectAsAnalyticAccount(
  client: OdooClient,
  project: Project,
  existingOdooId?: number,
): Promise<{ odooId: number; created: boolean }> {
  const values = mapProjectToAnalyticAccount(project);
  if (existingOdooId) {
    await client.write('account.analytic.account', [existingOdooId], values);
    return { odooId: existingOdooId, created: false };
  }
  const odooId = await client.create('account.analytic.account', values);
  return { odooId, created: true };
}

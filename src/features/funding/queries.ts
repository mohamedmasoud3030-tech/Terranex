import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type Party = { id: string; legal_name: string; party_type: 'PERSON' | 'ORGANIZATION' };
export type Participant = {
  id: string;
  party_id: string;
  role: 'INVESTOR';
  parties: { legal_name: string };
};
export type AgreementVersion = {
  id: string;
  version_no: number;
  status: 'DRAFT' | 'ACTIVE' | 'SUPERSEDED';
  effective_date: string;
  activated_at: string | null;
  terms_hash: string;
};
export type CommitmentTerm = {
  id: string;
  participant_id: string;
  commitment_minor_units: string;
  currency: string;
};
export type CapitalCall = {
  id: string;
  status: 'ISSUED' | 'CANCELLED';
  reference: string | null;
  due_date: string;
  issued_at: string;
  agreement_version_id: string;
};
export type CapitalCallLine = {
  id: string;
  capital_call_id: string;
  participant_id: string;
  amount_minor_units: string;
  currency: string;
};
export type Contribution = {
  id: string;
  capital_call_id: string;
  participant_id: string;
  agreement_version_id: string;
  contribution_minor_units: string;
  currency: string;
  occurred_on: string;
  created_at: string;
};
// `ProjectCapitalPosition` and its reader `getProjectCapitalPosition` were
// removed here. The view they read, `project_capital_position_read`, is derived
// from `project_capital_position`, which sums `partner_capital_position` rows
// with no `currency` in the GROUP BY and then labels the total with
// `investment_projects.reporting_currency`. A project whose capital is
// committed in two currencies therefore read back as one figure in a currency
// the underlying facts may never have used — the defect ADR 0034 exists to
// prevent.
//
// `getProjectCapitalByCurrency` (in `features/finance/queries.ts`) plus
// `features/funding/project-capital.ts` are the authoritative capital read
// path, and every surface now uses them. The database object is NOT dropped:
// the S6 `PARTNER_CAPITAL_ROLLFORWARD` gate still calls it, so removing it
// needs a migration and a real PostgreSQL run (see the residual-risk note in
// the recovery report). Removing the TypeScript accessor means no
// server-rendered surface can reach it in the meantime.
export type PartnerCapitalPosition = {
  participant_id: string;
  agreement_version_id: string;
  commitment_minor_units: string;
  called_minor_units: string;
  contributed_minor_units: string;
  receivable_minor_units: string;
  currency: string;
};

export async function getParties(organizationId: string): Promise<Party[]> {
  const s = await createClient();
  const { data, error } = await s.from('parties').select('id,legal_name,party_type')
    .eq('organization_id', organizationId).order('legal_name');
  if (error) throwOperatorQuery(error);
  return data as Party[];
}

export async function getParticipants(projectId: string): Promise<Participant[]> {
  const s = await createClient();
  const { data, error } = await s.from('project_participants')
    .select('id,party_id,role,parties(legal_name)').eq('project_id', projectId).order('created_at');
  if (error) throwOperatorQuery(error);
  return data as unknown as Participant[];
}

export async function getActiveVersion(projectId: string): Promise<AgreementVersion | null> {
  const s = await createClient();
  const { data, error } = await s.from('agreement_versions')
    .select('id,version_no,status,effective_date,activated_at,terms_hash')
    .eq('project_id', projectId).eq('status', 'ACTIVE').maybeSingle();
  if (error) throwOperatorQuery(error);
  return data as AgreementVersion | null;
}

export async function getVersions(projectId: string): Promise<AgreementVersion[]> {
  const s = await createClient();
  const { data, error } = await s.from('agreement_versions')
    .select('id,version_no,status,effective_date,activated_at,terms_hash')
    .eq('project_id', projectId).order('version_no', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as AgreementVersion[];
}

export async function getCommitments(versionId: string): Promise<CommitmentTerm[]> {
  const s = await createClient();
  const { data, error } = await s.from('commitment_terms_read')
    .select('id,participant_id,commitment_minor_units,currency')
    .eq('agreement_version_id', versionId);
  if (error) throwOperatorQuery(error);
  return data as CommitmentTerm[];
}

export async function getCapitalCalls(projectId: string): Promise<CapitalCall[]> {
  const s = await createClient();
  const { data, error } = await s.from('capital_calls')
    .select('id,status,reference,due_date,issued_at,agreement_version_id')
    .eq('project_id', projectId).order('issued_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as CapitalCall[];
}

export async function getCapitalCallLines(callIds: string[]): Promise<CapitalCallLine[]> {
  if (callIds.length === 0) return [];
  const s = await createClient();
  const { data, error } = await s.from('capital_call_lines_read')
    .select('id,capital_call_id,participant_id,amount_minor_units,currency')
    .in('capital_call_id', callIds);
  if (error) throwOperatorQuery(error);
  return data as CapitalCallLine[];
}

export async function getContributions(projectId: string): Promise<Contribution[]> {
  const s = await createClient();
  const { data, error } = await s.from('contributions_read')
    .select('id,capital_call_id,participant_id,agreement_version_id,contribution_minor_units,currency,occurred_on,created_at')
    .eq('project_id', projectId).order('occurred_on', { ascending: false });
  if (error) throwOperatorQuery(error);
  return data as Contribution[];
}

export async function getPartnerCapitalPositions(versionId: string): Promise<PartnerCapitalPosition[]> {
  const s = await createClient();
  const { data, error } = await s.from('partner_capital_position_read')
    .select('participant_id,agreement_version_id,commitment_minor_units,called_minor_units,contributed_minor_units,receivable_minor_units,currency')
    .eq('agreement_version_id', versionId);
  if (error) throwOperatorQuery(error);
  return data as PartnerCapitalPosition[];
}

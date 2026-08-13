import { createClient } from '@/shared/supabase/server';
import type { ConditionalSectionCode } from './schema';
import {
  emptyIntakeSnapshot,
  evaluateIntakeReadiness,
  type IntakeSnapshot,
} from './readiness';

export type IntakeDeclaration = {
  declaration_id: string;
  organization_id: string;
  project_id: string;
  freeze_date: string | null;
  freeze_evidence_reference: string | null;
  freeze_recorded_by: string | null;
  freeze_recorded_at: string | null;
  declared_debit_total_minor_units: string | null;
  declared_credit_total_minor_units: string | null;
  control_totals_evidence_reference: string | null;
  control_totals_declared_by: string | null;
  control_totals_declared_at: string | null;
  agreement_title_or_reference: string | null;
  organization_evidence_reference: string | null;
  project_evidence_reference: string | null;
};

export type IntakeApplicability = {
  applicability_id: string;
  section_code: ConditionalSectionCode;
  applicable: boolean;
  reason: string;
  evidence_reference: string | null;
};

export type IntakeModellingGap = {
  gap_id: string;
  source_reference: string;
  description: string;
  amount_minor_units: string | null;
  currency: string;
  why_unmappable: string;
  status: 'OPEN' | 'COMMERCIALLY_ACCEPTED';
  recorded_at: string;
  resolution_evidence_reference: string | null;
};

export type IntakeEvidenceItem = {
  evidence_item_id: string;
  evidence_identifier: string;
  linked_fact: string;
  customer_storage_location: string;
  recorded_at: string;
};

export async function getIntakeDeclaration(projectId: string): Promise<IntakeDeclaration | null> {
  const s = await createClient();
  const { data, error } = await s.from('project_intake_declarations_read')
    .select('declaration_id,organization_id,project_id,freeze_date,freeze_evidence_reference,freeze_recorded_by,freeze_recorded_at,declared_debit_total_minor_units,declared_credit_total_minor_units,control_totals_evidence_reference,control_totals_declared_by,control_totals_declared_at,agreement_title_or_reference,organization_evidence_reference,project_evidence_reference')
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throw error;
  return data as IntakeDeclaration | null;
}

export async function getIntakeApplicability(projectId: string): Promise<IntakeApplicability[]> {
  const s = await createClient();
  const { data, error } = await s.from('project_intake_section_applicability_read')
    .select('applicability_id,section_code,applicable,reason,evidence_reference')
    .eq('project_id', projectId)
    .order('section_code');
  if (error) throw error;
  return data as IntakeApplicability[];
}

export async function getIntakeModellingGaps(projectId: string): Promise<IntakeModellingGap[]> {
  const s = await createClient();
  const { data, error } = await s.from('project_intake_modelling_gaps_read')
    .select('gap_id,source_reference,description,amount_minor_units,currency,why_unmappable,status,recorded_at,resolution_evidence_reference')
    .eq('project_id', projectId)
    .order('recorded_at', { ascending: false });
  if (error) throw error;
  return data as IntakeModellingGap[];
}

export async function getIntakeEvidenceItems(projectId: string): Promise<IntakeEvidenceItem[]> {
  const s = await createClient();
  const { data, error } = await s.from('project_intake_evidence_items_read')
    .select('evidence_item_id,evidence_identifier,linked_fact,customer_storage_location,recorded_at')
    .eq('project_id', projectId)
    .order('recorded_at', { ascending: false });
  if (error) throw error;
  return data as IntakeEvidenceItem[];
}

export async function getAllocationRuleLines(ruleSetId: string): Promise<Array<{
  participant_party_id: string;
  weight_numerator: string;
  weight_denominator: string;
}>> {
  const s = await createClient();
  const { data, error } = await s.from('s5_allocation_rules')
    .select('participant_party_id,weight_numerator,weight_denominator')
    .eq('rule_set_id', ruleSetId);
  if (error) throw error;
  return (data ?? []).map((row) => ({
    participant_party_id: row.participant_party_id as string,
    weight_numerator: String(row.weight_numerator),
    weight_denominator: String(row.weight_denominator),
  }));
}

export function applicabilityMap(
  rows: IntakeApplicability[],
): Partial<Record<ConditionalSectionCode, boolean>> {
  const map: Partial<Record<ConditionalSectionCode, boolean>> = {};
  for (const row of rows) map[row.section_code] = row.applicable;
  return map;
}

export function buildIntakeSnapshot(input: {
  organizationName: string | null;
  projectName: string | null;
  reportingCurrency: string | null;
  declaration: IntakeDeclaration | null;
  applicability: IntakeApplicability[];
  gaps: IntakeModellingGap[];
  evidenceItems: IntakeEvidenceItem[];
  investorCount: number;
  activeAgreement: boolean;
  agreementEffectiveDate: string | null;
  commitmentCount: number;
  allocationRulesConfigured: boolean;
  issuedCallCount: number;
  contributionCount: number;
  contributionCashAttributedCount: number;
  cashAccountCount: number;
  bankStatementLineCount: number;
  openPeriodExists: boolean;
  openPeriodCoversFreeze: boolean;
  realEstateProfile: boolean;
  realEstateStrategy: string | null;
  assetCount: number;
  parcelCount: number;
  acquisitionCount: number;
  approvedBudgetCount: number;
  openingImportStatus: IntakeSnapshot['openingImportStatus'];
  openingRejectedRowCount: number;
  openingControlTotalsMatch: boolean | null;
  openingIsReversed: boolean;
  openingMappingCodes: string[];
  openingDebitVariance: string | null;
  openingCreditVariance: string | null;
  matchedZeroVarianceCheckpoints: number;
  nonZeroVarianceCheckpoints: number;
  openCriticalExceptions: number;
}): IntakeSnapshot {
  return {
    ...emptyIntakeSnapshot(),
    organizationName: input.organizationName,
    projectName: input.projectName,
    reportingCurrency: input.reportingCurrency,
    freezeDate: input.declaration?.freeze_date ?? null,
    freezeEvidenceReference: input.declaration?.freeze_evidence_reference ?? null,
    organizationEvidenceReference: input.declaration?.organization_evidence_reference ?? null,
    projectEvidenceReference: input.declaration?.project_evidence_reference ?? null,
    agreementTitleOrReference: input.declaration?.agreement_title_or_reference ?? null,
    declaredDebitTotal: input.declaration?.declared_debit_total_minor_units ?? null,
    declaredCreditTotal: input.declaration?.declared_credit_total_minor_units ?? null,
    investorCount: input.investorCount,
    activeAgreement: input.activeAgreement,
    agreementEffectiveDate: input.agreementEffectiveDate,
    commitmentCount: input.commitmentCount,
    allocationRulesConfigured: input.allocationRulesConfigured,
    issuedCallCount: input.issuedCallCount,
    contributionCount: input.contributionCount,
    contributionCashAttributedCount: input.contributionCashAttributedCount,
    cashAccountCount: input.cashAccountCount,
    bankStatementLineCount: input.bankStatementLineCount,
    openPeriodExists: input.openPeriodExists,
    openPeriodCoversFreeze: input.openPeriodCoversFreeze,
    realEstateProfile: input.realEstateProfile,
    realEstateStrategy: input.realEstateStrategy,
    assetCount: input.assetCount,
    parcelCount: input.parcelCount,
    acquisitionCount: input.acquisitionCount,
    approvedBudgetCount: input.approvedBudgetCount,
    openingImportStatus: input.openingImportStatus,
    openingRejectedRowCount: input.openingRejectedRowCount,
    openingControlTotalsMatch: input.openingControlTotalsMatch,
    openingIsReversed: input.openingIsReversed,
    openingMappingCodes: input.openingMappingCodes,
    openingDebitVariance: input.openingDebitVariance,
    openingCreditVariance: input.openingCreditVariance,
    matchedZeroVarianceCheckpoints: input.matchedZeroVarianceCheckpoints,
    nonZeroVarianceCheckpoints: input.nonZeroVarianceCheckpoints,
    openCriticalExceptions: input.openCriticalExceptions,
    evidenceItemCount: input.evidenceItems.length,
    openModellingGapCount: input.gaps.filter((gap) => gap.status === 'OPEN').length,
    applicability: applicabilityMap(input.applicability),
  };
}

export { evaluateIntakeReadiness };

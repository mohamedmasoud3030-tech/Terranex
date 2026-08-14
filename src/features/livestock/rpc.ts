import type {
  LivestockCohortInput,
  LivestockHerdInput,
  LivestockProfileInput,
  LivestockSiteInput,
  LivestockTransitionInput,
} from './schema';

function commandContext(input: {
  organizationId: string;
  projectId: string;
  idempotencyKey: string;
}) {
  return {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_idempotency_key: input.idempotencyKey,
  };
}

export const profileRpcArguments = (input: LivestockProfileInput) => ({
  ...commandContext(input),
  p_notes: input.notes ?? null,
});

export const siteRpcArguments = (input: LivestockSiteInput) => ({
  ...commandContext(input),
  p_name: input.name,
  p_internal_reference: input.internalReference,
  p_site_type: input.siteType,
  p_location_description: input.locationDescription ?? null,
  p_notes: input.notes ?? null,
});

export const herdRpcArguments = (input: LivestockHerdInput) => ({
  ...commandContext(input),
  p_name: input.name,
  p_internal_reference: input.internalReference,
  p_species: input.species,
  p_purpose: input.purpose,
  p_breed_descriptor: input.breedDescriptor ?? null,
});

export const cohortRpcArguments = (input: LivestockCohortInput) => ({
  ...commandContext(input),
  p_herd_id: input.herdId,
  p_site_id: input.initialSiteId,
  p_cohort_reference: input.cohortReference,
  p_origin_type: input.originType,
  p_origin_date: input.originDate,
  p_opening_headcount: Number(input.openingHeadcount),
  p_sex_composition: input.sexComposition ?? null,
  p_breed_descriptor: input.breedDescriptor ?? null,
  p_opening_weight_value: input.openingWeightValue ?? null,
  p_opening_weight_unit: input.openingWeightUnit ?? null,
  p_opening_weight_basis: input.openingWeightBasis ?? null,
  p_origin_evidence_reference: input.originEvidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const transitionRpcArguments = (input: LivestockTransitionInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_expected_state: input.expectedState,
  p_new_state: input.newState,
  p_reason: input.reason,
  p_evidence_reference: input.evidenceReference ?? null,
});

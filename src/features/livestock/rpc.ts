import { parseMajorUnitsToMinor } from '@/shared/money';
import type {
  LivestockBirthInput,
  LivestockCloseoutInput,
  LivestockCohortInput,
  LivestockCostAttributionInput,
  LivestockCostAttributionReversalInput,
  LivestockHerdInput,
  LivestockMergeInput,
  LivestockMortalityInput,
  LivestockMovementInput,
  LivestockProfileInput,
  LivestockPurchaseInput,
  LivestockSaleApprovalInput,
  LivestockSaleCollectionInput,
  LivestockSaleInput,
  LivestockSaleRecognitionInput,
  LivestockSiteInput,
  LivestockSplitInput,
  LivestockTransitionInput,
  LivestockWeightEventInput,
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

export const movementRpcArguments = (input: LivestockMovementInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_source_site_id: input.sourceSiteId,
  p_source_herd_id: input.sourceHerdId,
  p_destination_site_id: input.destinationSiteId,
  p_destination_herd_id: input.destinationHerdId,
  p_effective_at: input.effectiveAt,
  p_reason: input.reason,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const weightEventRpcArguments = (input: LivestockWeightEventInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_effective_at: input.effectiveAt,
  p_method: input.method,
  p_weight_value: input.weightValue,
  p_weight_unit: input.weightUnit,
  p_measured_animal_count: input.measuredAnimalCount
    ? Number(input.measuredAnimalCount)
    : null,
  p_sample_size: input.sampleSize ? Number(input.sampleSize) : null,
  p_confidence_level: input.confidenceLevel ?? null,
  p_evidence_reference: input.evidenceReference ?? null,
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

export const birthRpcArguments = (input: LivestockBirthInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_quantity: Number(input.quantity),
  p_effective_at: input.effectiveAt,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const mortalityRpcArguments = (input: LivestockMortalityInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_quantity: Number(input.quantity),
  p_effective_at: input.effectiveAt,
  p_cause_category: input.causeCategory,
  p_cause_detail: input.causeDetail ?? null,
  p_disposal_method: input.disposalMethod ?? null,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const splitRpcArguments = (input: LivestockSplitInput) => ({
  ...commandContext(input),
  p_source_cohort_id: input.sourceCohortId,
  p_quantity: Number(input.quantity),
  p_effective_at: input.effectiveAt,
  p_destination_cohort_reference: input.destinationCohortReference,
  p_destination_herd_id: input.destinationHerdId,
  p_destination_site_id: input.destinationSiteId,
  p_destination_sex_composition: input.destinationSexComposition ?? null,
  p_destination_breed_descriptor: input.destinationBreedDescriptor ?? null,
  p_reason: input.reason,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const mergeRpcArguments = (input: LivestockMergeInput) => ({
  ...commandContext(input),
  p_source_cohort_ids: input.sourceCohortIds,
  p_quantities: input.quantities.map(Number),
  p_effective_at: input.effectiveAt,
  p_destination_cohort_reference: input.destinationCohortReference,
  p_destination_herd_id: input.destinationHerdId,
  p_destination_site_id: input.destinationSiteId,
  p_destination_sex_composition: input.destinationSexComposition ?? null,
  p_destination_breed_descriptor: input.destinationBreedDescriptor ?? null,
  p_reason: input.reason,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

// ---------------------------------------------------------------------------
// GF-024 — Livestock commercial, profitability & closeout RPC arguments.
// ---------------------------------------------------------------------------
export const purchaseRpcArguments = (input: LivestockPurchaseInput) => ({
  ...commandContext(input),
  p_supplier_party_id: input.supplierPartyId,
  p_purchase_reference: input.purchaseReference,
  p_agreement_reference: input.agreementReference ?? null,
  p_effective_at: input.effectiveAt,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
  p_cohort_ids: input.linesJson.map((line) => line.cohortId),
  p_quantities: input.linesJson.map((line) => Number(line.quantity)),
  p_agreed_unit_price_minor_units: input.linesJson.every((line) => line.agreedUnitPrice == null)
    ? null
    : input.linesJson.map((line) => (line.agreedUnitPrice == null ? null : parseMajorUnitsToMinor(line.agreedUnitPrice, 'EGP'))),
});

export const saleRpcArguments = (input: LivestockSaleInput) => ({
  ...commandContext(input),
  p_buyer_party_id: input.buyerPartyId,
  p_sale_reference: input.saleReference,
  p_agreement_reference: input.agreementReference ?? null,
  p_sale_date: input.saleDate,
  p_currency: input.currency,
  p_terms: input.terms ?? null,
  p_evidence_reference: input.evidenceReference ?? null,
  p_cohort_ids: input.linesJson.map((line) => line.cohortId),
  p_quantities: input.linesJson.map((line) => Number(line.quantity)),
  p_unit_price_minor_units: input.linesJson.map((line) => parseMajorUnitsToMinor(line.unitPrice, input.currency)),
});

export const saleApprovalRpcArguments = (input: LivestockSaleApprovalInput) => ({
  ...commandContext(input),
  p_sale_id: input.saleId,
});

export const saleRecognitionRpcArguments = (input: LivestockSaleRecognitionInput) => ({
  ...commandContext(input),
  p_sale_id: input.saleId,
  p_control_transfer_date: input.controlTransferDate,
  p_evidence_reference: input.evidenceReference,
});

export const saleCollectionRpcArguments = (input: LivestockSaleCollectionInput) => ({
  ...commandContext(input),
  p_recognition_id: input.recognitionId,
  p_cash_account_id: input.cashAccountId,
  p_amount_minor_units: parseMajorUnitsToMinor(input.amount, input.currency),
  p_collection_date: input.collectionDate,
  p_evidence_reference: input.evidenceReference,
});

export const costAttributionRpcArguments = (input: LivestockCostAttributionInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_source_journal_line_id: input.sourceJournalLineId,
  p_amount_minor_units: parseMajorUnitsToMinor(input.amount, input.currency),
  p_cost_category: input.costCategory,
  p_policy_reference: input.policyReference,
  p_evidence_reference: input.evidenceReference,
});

export const costAttributionReversalRpcArguments = (
  input: LivestockCostAttributionReversalInput,
) => ({
  ...commandContext(input),
  p_attribution_id: input.attributionId,
  p_reason: input.reason,
  p_evidence_reference: input.evidenceReference,
});

export const closeoutRpcArguments = (input: LivestockCloseoutInput) => ({
  ...commandContext(input),
  p_cohort_id: input.cohortId,
  p_close_reason: input.closeReason,
  p_evidence_reference: input.evidenceReference,
});

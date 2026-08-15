import type {
  FeedIssueInput,
  FeedItemInput,
  HealthEventInput,
  IdentifyAnimalInput,
  MedicineProductInput,
  ReproductionEventInput,
} from './operations-schema';

function context(input: { organizationId: string; projectId: string; idempotencyKey: string }) {
  return {
    p_organization_id: input.organizationId,
    p_project_id: input.projectId,
    p_idempotency_key: input.idempotencyKey,
  };
}

export const medicineProductRpcArguments = (input: MedicineProductInput) => ({
  ...context(input),
  p_product_reference: input.productReference,
  p_name: input.name,
  p_product_kind: input.productKind,
  p_active_ingredient: input.activeIngredient ?? null,
  p_default_withdrawal_days: Number(input.defaultWithdrawalDays),
  p_notes: input.notes ?? null,
});

export const identifyAnimalRpcArguments = (input: IdentifyAnimalInput) => ({
  ...context(input),
  p_cohort_id: input.cohortId,
  p_identifier_type: input.identifierType,
  p_identifier_value: input.identifierValue,
  p_sex: input.sex,
  p_birth_date: input.birthDate ?? null,
  p_breed_descriptor: input.breedDescriptor ?? null,
  p_identified_at: input.identifiedAt,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const healthEventRpcArguments = (input: HealthEventInput) => ({
  ...context(input),
  p_cohort_id: input.cohortId,
  p_animal_id: input.animalId ?? null,
  p_event_type: input.eventType,
  p_condition_classification: input.conditionClassification ?? null,
  p_condition_name: input.conditionName ?? null,
  p_medicine_product_id: input.medicineProductId ?? null,
  p_dose_quantity: input.doseQuantity ?? null,
  p_dose_unit: input.doseUnit ?? null,
  p_administration_route: input.administrationRoute ?? null,
  p_effective_at: input.effectiveAt,
  p_practitioner_name: input.practitionerName,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const reproductionEventRpcArguments = (input: ReproductionEventInput) => ({
  ...context(input),
  p_cohort_id: input.cohortId,
  p_subject_animal_id: input.subjectAnimalId ?? null,
  p_event_type: input.eventType,
  p_subject_count: Number(input.subjectCount),
  p_service_method: input.serviceMethod ?? null,
  p_pregnancy_status: input.pregnancyStatus ?? null,
  p_expected_birth_date: input.expectedBirthDate ?? null,
  p_observed_live_birth_count: input.observedLiveBirthCount == null
    ? null
    : Number(input.observedLiveBirthCount),
  p_stillbirth_count: input.stillbirthCount == null ? null : Number(input.stillbirthCount),
  p_birth_quantity_effect: input.birthQuantityEffect ?? null,
  p_weaned_count: input.weanedCount == null ? null : Number(input.weanedCount),
  p_dam_animal_id: input.damAnimalId ?? null,
  p_sire_animal_id: input.sireAnimalId ?? null,
  p_effective_at: input.effectiveAt,
  p_performed_by_name: input.performedByName,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

export const feedItemRpcArguments = (input: FeedItemInput) => ({
  ...context(input),
  p_item_reference: input.itemReference,
  p_name: input.name,
  p_feed_category: input.feedCategory,
  p_issue_unit: input.issueUnit,
  p_notes: input.notes ?? null,
});

export const feedIssueRpcArguments = (input: FeedIssueInput) => ({
  ...context(input),
  p_cohort_id: input.cohortId,
  p_feed_item_id: input.feedItemId,
  p_quantity: input.quantity,
  p_unit: input.unit,
  p_effective_at: input.effectiveAt,
  p_feeding_period_start: input.feedingPeriodStart ?? null,
  p_feeding_period_end: input.feedingPeriodEnd ?? null,
  p_issued_by_name: input.issuedByName,
  p_evidence_reference: input.evidenceReference ?? null,
  p_notes: input.notes ?? null,
});

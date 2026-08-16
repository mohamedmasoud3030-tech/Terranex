import { describe, expect, it } from 'vitest';
import {
  declareControlTotalsSchema,
  recordFreezeDateSchema,
  recordSetupReferencesSchema,
  reportModellingGapSchema,
} from '@/features/intake/schema';
import {
  emptyIntakeSnapshot,
  evaluateIntakeReadiness,
  type IntakeSnapshot,
} from '@/features/intake/readiness';

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';

function snapshot(over: Partial<IntakeSnapshot> = {}): IntakeSnapshot {
  return { ...emptyIntakeSnapshot(), ...over };
}

describe('intake declaration schemas', () => {
  it('accepts a freeze date with evidence', () => {
    expect(recordFreezeDateSchema.safeParse({
      organizationId, projectId, freezeDate: '2026-03-31', evidenceReference: 'FREEZE-PACK-01',
    }).success).toBe(true);
  });

  it('rejects a freeze date that is not ISO', () => {
    expect(recordFreezeDateSchema.safeParse({
      organizationId, projectId, freezeDate: '31/03/2026', evidenceReference: 'FREEZE-PACK-01',
    }).success).toBe(false);
  });

  it('rejects unbalanced declared control totals before they reach PostgreSQL', () => {
    const parsed = declareControlTotalsSchema.safeParse({
      organizationId, projectId, declaredDebitTotal: '1000', declaredCreditTotal: '900', evidenceReference: 'TB-1',
    });
    expect(parsed.success).toBe(false);
  });

  it('accepts balanced integer minor-unit totals and refuses decimals', () => {
    expect(declareControlTotalsSchema.safeParse({
      organizationId, projectId, declaredDebitTotal: '125000', declaredCreditTotal: '125000', evidenceReference: 'TB-1',
    }).success).toBe(true);
    expect(declareControlTotalsSchema.safeParse({
      organizationId, projectId, declaredDebitTotal: '1250.00', declaredCreditTotal: '1250.00', evidenceReference: 'TB-1',
    }).success).toBe(false);
  });

  it('requires at least one setup reference', () => {
    expect(recordSetupReferencesSchema.safeParse({
      organizationId, projectId, agreementTitleOrReference: '', organizationEvidenceReference: '', projectEvidenceReference: '',
    }).success).toBe(false);
    expect(recordSetupReferencesSchema.safeParse({
      organizationId, projectId, agreementTitleOrReference: 'اتفاقية الشركاء', organizationEvidenceReference: '', projectEvidenceReference: '',
    }).success).toBe(true);
  });

  it('does not invent an opening mapping code for an unmappable balance', () => {
    const parsed = reportModellingGapSchema.safeParse({
      organizationId,
      projectId,
      sourceReference: 'TB-LINE-240',
      description: 'قرض شريك',
      amountMinorUnits: '500000',
      whyUnmappable: 'لا يوجد ترميز افتتاحي لالتزامات القروض',
    });
    expect(parsed.success).toBe(true);
  });
});

describe('intake readiness derivation', () => {
  it('starts empty as not ready and never marks Phase 2 passed', () => {
    const result = evaluateIntakeReadiness(snapshot());
    expect(result.phase2Passed).toBe(false);
    expect(result.verdict).toBe('INTAKE_IN_PROGRESS');
    expect(result.sections.find((section) => section.code === 'DS01_ORGANIZATION')?.status).toBe('MISSING');
    expect(result.sections.find((section) => section.code === 'DS09_OPENING_BALANCES')?.status).toBe('BLOCKED');
  });

  it('treats organization, project and freeze date as the setup group', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'شركة النخيل',
      projectName: 'أرض الطريق الدائري',
      reportingCurrency: 'EGP',
      freezeDate: '2026-03-31',
      freezeEvidenceReference: 'FREEZE-1',
    }));
    expect(result.sections.find((section) => section.code === 'DS01_ORGANIZATION')?.status).toBe('COMPLETE');
    expect(result.sections.find((section) => section.code === 'DS02_PROJECT')?.status).toBe('COMPLETE');
    expect(result.sections.find((section) => section.code === 'FREEZE_DATE')?.status).toBe('COMPLETE');
  });

  it('does not require an investor, agreement, or commitment while the funding mechanism is unresolved', () => {
    // BD-002/003/005 are OPEN: investor/agreement/commitment setup is CONDITIONAL,
    // not MANDATORY. With no investors and no agreement the sections are
    // policy-blocked (NOT_APPLICABLE), never a readiness gate, and never instruct
    // the operator to "add an investor first".
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 0,
      activeAgreement: false,
    }));
    const parties = result.sections.find((section) => section.code === 'DS03_PARTIES')!;
    expect(parties.kind).toBe('CONDITIONAL');
    expect(parties.status).toBe('NOT_APPLICABLE');
    expect(result.sections.find((section) => section.code === 'DS04_AGREEMENT')?.status).toBe('NOT_APPLICABLE');
    expect(result.sections.find((section) => section.code === 'DS05_COMMITMENTS')?.status).toBe('NOT_APPLICABLE');
    expect(result.mandatoryMissing).not.toContain('DS03_PARTIES');
    expect(result.mandatoryMissing).not.toContain('DS04_AGREEMENT');
    expect(result.mandatoryMissing).not.toContain('DS05_COMMITMENTS');
    expect(parties.blockingReasons.join(' ')).not.toMatch(/أضف مستثمر|مستثمرين/);
  });

  it('reaches operational readiness without fabricating investors', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      reportingCurrency: 'EGP',
      freezeDate: '2026-03-31',
      freezeEvidenceReference: 'F',
      organizationEvidenceReference: 'CR-1',
      projectEvidenceReference: 'SCOPE-1',
      declaredDebitTotal: '1000',
      declaredCreditTotal: '1000',
      cashAccountCount: 1,
      openPeriodExists: true,
      openPeriodCoversFreeze: true,
      realEstateProfile: true,
      realEstateStrategy: 'ACQUIRE_HOLD',
      assetCount: 1,
      parcelCount: 1,
      acquisitionCount: 1,
      evidenceItemCount: 1,
      applicability: {
        HISTORICAL_CALLS: false,
        HISTORICAL_CONTRIBUTIONS: false,
        DEVELOPMENT_BASELINE: false,
        UNPAID_SUPPLIERS: false,
        SALES_DISPOSITIONS: false,
        HISTORICAL_DISTRIBUTIONS: false,
        BANK_STATEMENTS: false,
      },
    }));
    expect(result.sections.find((section) => section.code === 'DS09_OPENING_BALANCES')?.status).toBe('MISSING');
    expect(result.verdict).toBe('OPENING_READY_TO_STAGE');
    expect(result.phase2Passed).toBe(false);
  });

  it('does not require ownership or allocation weights after activation (Scenario A)', () => {
    // Active governing agreement with an agreement title, but NO allocation rule set
    // and no ownership/allocation weights anywhere in the snapshot.
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 2,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 2,
      agreementTitleOrReference: 'اتفاقية الشركاء',
    }));
    const agreement = result.sections.find((section) => section.code === 'DS04_AGREEMENT')!;
    expect(agreement.status).toBe('COMPLETE');
    expect(agreement.blockingReasons).toHaveLength(0);
    expect(result.sections.find((section) => section.code === 'DS05_COMMITMENTS')?.status).toBe('COMPLETE');
  });

  it('treats a missing agreement title as the only remaining DS04 gap, never ownership weights', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 2,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 2,
      agreementTitleOrReference: null,
    }));
    const agreement = result.sections.find((section) => section.code === 'DS04_AGREEMENT')!;
    expect(agreement.status).toBe('IN_PROGRESS');
    expect(agreement.blockingReasons).toEqual(['عنوان الاتفاقية أو مرجعها غير مسجّل.']);
  });

  it('keeps ownership/allocation economics policy-blocked without degrading DS04 readiness', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 1,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 1,
      agreementTitleOrReference: 'اتفاقية',
    }));
    const agreement = result.sections.find((section) => section.code === 'DS04_AGREEMENT')!;
    // Requirements (blocking reasons) must never mention ownership/allocation weights or a 100% total.
    expect(agreement.blockingReasons.join(' ')).not.toMatch(/100|أوزان|وزن|ملكية|تخصيص/);
    expect(agreement.summaryAr).not.toMatch(/100|أوزان/);
    // The blocked policy is stated explicitly as unresolved, not silently passed.
    expect(agreement.warnings.join(' ')).toContain('غير محددة بسياسة معتمدة');
    expect(agreement.status).toBe('COMPLETE');
  });

  it('keeps commitments distinct from ownership/entitlement and never derives ownership from them (Scenario B)', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 2,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 2,
      agreementTitleOrReference: 'اتفاقية الشركاء',
    }));
    const commitments = result.sections.find((section) => section.code === 'DS05_COMMITMENTS')!;
    expect(commitments.status).toBe('COMPLETE');
    expect(commitments.summaryAr).toContain('الالتزام ≠ المطلوب ≠ المساهمة');
    expect(commitments.summaryAr).not.toMatch(/ملكية|حصة|استحقاق/);
    // Commitment ratios never contribute ownership; DS04 completes on agreement facts alone.
    expect(result.sections.find((section) => section.code === 'DS04_AGREEMENT')?.status).toBe('COMPLETE');
  });

  it('does not consult dormant S5 allocation rule data for readiness (Scenario C)', () => {
    // There is no allocation-rule input on the snapshot anymore: historically recorded
    // S5 rule data cannot reach the readiness model, so it stays dormant.
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 1,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 1,
      agreementTitleOrReference: 'اتفاقية',
    }));
    expect(result.sections.find((section) => section.code === 'DS04_AGREEMENT')?.status).toBe('COMPLETE');
  });

  it('honours an explicit not-applicable declaration for historical calls', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 1,
      activeAgreement: true,
      commitmentCount: 1,
      applicability: { HISTORICAL_CALLS: false },
    }));
    expect(result.sections.find((section) => section.code === 'DS06_HISTORICAL_CALLS')?.status).toBe('NOT_APPLICABLE');
  });

  it('fails when a contribution is also expressed as opening contributed capital', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 1,
      activeAgreement: true,
      commitmentCount: 1,
      contributionCount: 1,
      openingMappingCodes: ['OPENING_CONTRIBUTED_CAPITAL'],
      openingImportStatus: 'DRAFT',
    }));
    expect(result.sections.find((section) => section.code === 'DS07_HISTORICAL_CONTRIBUTIONS')?.status).toBe('FAILED');
  });

  it('refuses unbalanced declared totals and rejected opening rows', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      freezeDate: '2026-03-31',
      declaredDebitTotal: '100',
      declaredCreditTotal: '90',
      cashAccountCount: 1,
      openingImportStatus: 'REJECTED',
      openingRejectedRowCount: 2,
    }));
    expect(result.sections.find((section) => section.code === 'CONTROL_TOTALS')?.status).toBe('FAILED');
    expect(result.sections.find((section) => section.code === 'DS09_OPENING_BALANCES')?.status).toBe('FAILED');
    expect(result.verdict).toBe('OPENING_BLOCKED');
  });

  it('is ready to stage when freeze, totals, cash and an open period exist', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      reportingCurrency: 'EGP',
      freezeDate: '2026-03-31',
      freezeEvidenceReference: 'F',
      organizationEvidenceReference: 'CR-1',
      projectEvidenceReference: 'SCOPE-1',
      agreementTitleOrReference: 'اتفاقية',
      declaredDebitTotal: '1000',
      declaredCreditTotal: '1000',
      investorCount: 1,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 1,
      cashAccountCount: 1,
      openPeriodExists: true,
      openPeriodCoversFreeze: true,
      realEstateProfile: true,
      realEstateStrategy: 'ACQUIRE_HOLD',
      assetCount: 1,
      parcelCount: 1,
      acquisitionCount: 1,
      evidenceItemCount: 1,
      applicability: {
        HISTORICAL_CALLS: false,
        HISTORICAL_CONTRIBUTIONS: false,
        DEVELOPMENT_BASELINE: false,
        UNPAID_SUPPLIERS: false,
        SALES_DISPOSITIONS: false,
        HISTORICAL_DISTRIBUTIONS: false,
        BANK_STATEMENTS: false,
      },
    }));
    expect(result.sections.find((section) => section.code === 'DS09_OPENING_BALANCES')?.status).toBe('MISSING');
    expect(result.verdict).toBe('OPENING_READY_TO_STAGE');
    expect(result.phase2Passed).toBe(false);
  });

  it('treats exact-zero posted reconciliation as pending real evidence, never Phase 2', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      freezeDate: '2026-03-31',
      declaredDebitTotal: '1000',
      declaredCreditTotal: '1000',
      investorCount: 1,
      activeAgreement: true,
      commitmentCount: 1,
      agreementTitleOrReference: 'اتفاقية',
      cashAccountCount: 1,
      openPeriodExists: true,
      openPeriodCoversFreeze: true,
      realEstateProfile: true,
      assetCount: 1,
      parcelCount: 1,
      openingImportStatus: 'POSTED',
      openingControlTotalsMatch: true,
      openingDebitVariance: '0',
      openingCreditVariance: '0',
      matchedZeroVarianceCheckpoints: 6,
      evidenceItemCount: 3,
    }));
    expect(result.sections.find((section) => section.code === 'OPENING_RECONCILIATION')?.status).toBe('COMPLETE');
    expect(result.verdict).toBe('OPENING_RECONCILED_PENDING_REAL_EVIDENCE');
    expect(result.phase2Passed).toBe(false);
  });

  it('keeps a develop-sell project missing until an approved budget or N/A exists', () => {
    const result = evaluateIntakeReadiness(snapshot({
      organizationName: 'أ',
      projectName: 'ب',
      realEstateProfile: true,
      realEstateStrategy: 'DEVELOP_SELL',
      assetCount: 1,
      parcelCount: 1,
      approvedBudgetCount: 0,
    }));
    expect(result.sections.find((section) => section.code === 'DS13_DEVELOPMENT')?.status).toBe('MISSING');
  });
});

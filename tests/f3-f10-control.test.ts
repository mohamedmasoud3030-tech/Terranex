import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  approvalPolicySchema,
  budgetCreateSchema,
  budgetLinesFromInput,
  fxConversionSchema,
  fxSnapshotSchema,
  milestoneSchema,
  obligationTermsSchema,
  openDisputeSchema,
  openExceptionSchema,
  retentionReleaseSchema,
  taxTreatmentSchema,
} from '../src/features/control/schema';

const org = '10000000-0000-4000-8000-000000000001';
const project = '20000000-0000-4000-8000-000000000002';
const id = '30000000-0000-4000-8000-000000000003';

const f3 = readFileSync('supabase/migrations/20260816050000_f3_contract_finance.sql', 'utf8');
const f4 = readFileSync('supabase/migrations/20260816051000_f4_budget_control.sql', 'utf8');
const f5 = readFileSync('supabase/migrations/20260816052000_f5_approval_exception_engine.sql', 'utf8');
const f6 = readFileSync('supabase/migrations/20260816053000_f6_currency_tax_contract.sql', 'utf8');
const f8 = readFileSync('supabase/migrations/20260816055000_f8_financial_integrity_center.sql', 'utf8');
const f9 = readFileSync('supabase/migrations/20260816056000_f9_project_performance.sql', 'utf8');
const f10 = readFileSync('supabase/migrations/20260816057000_f10_portfolio_rollup.sql', 'utf8');
const fixes = readFileSync('supabase/migrations/20260816058000_f3_f10_review_correctness.sql', 'utf8');
const scope = readFileSync('supabase/migrations/20260816058100_f4_fac_f10_scope.sql', 'utf8');

describe('F3 contract finance schema contracts', () => {
  it('validates milestone input and rejects bad codes', () => {
    expect(milestoneSchema.safeParse({
      organizationId: org, projectId: project, code: 'MS-01',
      labelAr: 'تسليم المرحلة الأولى', plannedDate: '2026-09-01',
      idempotencyKey: 'ms-00000001',
    }).success).toBe(true);
    expect(milestoneSchema.safeParse({
      organizationId: org, projectId: project, code: 'x',
      labelAr: 'تسليم المرحلة الأولى', plannedDate: '2026-09-01',
      idempotencyKey: 'ms-00000002',
    }).success).toBe(false);
  });

  it('validates payment terms by type (FIXED_DATE / NET_DAYS / MILESTONE_SCHEDULE)', () => {
    const base = { organizationId: org, obligationId: id, currency: 'EGP', retention: '0', idempotencyKey: 'terms-0000001' };
    expect(obligationTermsSchema.safeParse({ ...base, termsType: 'FIXED_DATE', dueDate: '2026-09-10' }).success).toBe(true);
    expect(obligationTermsSchema.safeParse({ ...base, termsType: 'NET_DAYS', netDays: '30' }).success).toBe(true);
    expect(obligationTermsSchema.safeParse({ ...base, termsType: 'MILESTONE_SCHEDULE' }).success).toBe(true);
    expect(obligationTermsSchema.safeParse({ ...base, termsType: 'BROKEN' }).success).toBe(false);
  });

  it('validates dispute and retention release inputs', () => {
    expect(openDisputeSchema.safeParse({
      organizationId: org, obligationId: id, reason: 'خلاف على الكمية المنفذة',
      idempotencyKey: 'dispute-000001',
    }).success).toBe(true);
    expect(retentionReleaseSchema.safeParse({
      organizationId: org, obligationId: id, currency: 'EGP', amount: '100.00',
      releaseDate: '2026-09-01', reason: 'اكتمال فترة الضمان',
      milestoneId: '', idempotencyKey: 'release-000001',
    }).success).toBe(true);
  });

  it('keeps the F3 invariants in the migration text', () => {
    expect(f3).toContain('retention must be strictly less than the obligation amount');
    expect(f3).toContain('payment blocked: obligation is under an open dispute');
    expect(f3).toContain('payment exceeds releasable payable (retention withheld)');
    expect(f3).toContain('an achieved milestone is immutable');
    expect(f3).toContain('cost_obligation_due_read');
    expect(f3).toContain('OVERDUE_90_PLUS');
    expect(f3).toContain('releasable_outstanding_minor_units');
  });
});

describe('F4 budget control schema contracts', () => {
  it('validates budget creation with structured lines', () => {
    const lines = JSON.stringify([
      { cost_treatment: 'EXPENSE', amount_minor_units: '20000000' },
      { cost_treatment: 'CAPITALIZABLE_WIP', amount_minor_units: '10000000' },
    ]);
    expect(budgetCreateSchema.safeParse({
      organizationId: org, projectId: project, periodStart: '2026-01-01', periodEnd: '2026-12-31',
      budgetType: 'ORIGINAL', currency: 'EGP', description: 'موازنة سنوية',
      linesJson: lines, idempotencyKey: 'budget-00000001',
    }).success).toBe(true);
    expect(budgetLinesFromInput(lines)).toHaveLength(2);
    expect(budgetLinesFromInput('[{"cost_treatment":"BROKEN","amount_minor_units":"1"}]')).toHaveLength(0);
  });

  it('keeps the F4 invariants in the migration text', () => {
    expect(f4).toContain('approved budget periods must not overlap for the same project');
    expect(f4).toContain('budget ceiling exceeded for cost treatment');
    expect(f4).toContain('maker/checker: the budget preparer cannot approve it');
    expect(f4).toContain('UNALLOCATED_PURCHASE_COMMITMENT');
    expect(f4).not.toContain('sum(ob.obligations_minor_units) where b2.status');
  });
});

describe('F5 approval & exception engine schema contracts', () => {
  it('validates policies, exceptions and decisions', () => {
    expect(approvalPolicySchema.safeParse({
      organizationId: org, policyDomain: 'OBLIGATION_AUTHORIZATION',
      thresholdMinorUnits: '500000', currency: '', evidenceRequired: 'true',
      active: 'true', minApprovers: '1', idempotencyKey: 'policy-0000001',
    }).success).toBe(true);
    expect(openExceptionSchema.safeParse({
      organizationId: org, projectId: project, exceptionDomain: 'BUDGET_CEILING',
      subjectType: 'project_budget_line', subjectId: id, amountMinorUnits: '100000',
      currency: 'EGP', reason: 'اعتماد تجاوز السقف', severity: 'HIGH',
      idempotencyKey: 'exc-000000001',
    }).success).toBe(true);
    expect(openExceptionSchema.safeParse({
      organizationId: org, projectId: project, exceptionDomain: 'BUDGET_CEILING',
      subjectType: 'project_budget_line', subjectId: '', reason: 'بدون موضوع',
      severity: 'MEDIUM', idempotencyKey: 'exc-000000002',
    }).success).toBe(false);
  });

  it('keeps the F5 invariants in the migration text', () => {
    expect(f5).toContain('approval exceptions are append-only');
    expect(f5).toContain('maker/checker: the exception opener cannot approve it');
    expect(f5).toContain('approval policy requires evidence');
    expect(f5).toContain('approval_exception_registry_read');
    expect(f5).toContain('project_budget_consumption_read');
    expect(f5).toContain('greatest');
  });
});

describe('F6 currency & tax contract schema contracts', () => {
  it('validates exact rational FX snapshots and conversions', () => {
    expect(fxSnapshotSchema.safeParse({
      organizationId: org, baseCurrency: 'EGP', quoteCurrency: 'USD',
      rateNumerator: '1', rateDenominator: '100', rateDate: '2026-08-01',
      rateSource: 'EXTERNAL_PROVIDER_STATEMENT', providerReference: 'ref-1',
      idempotencyKey: 'fx-snap-000001',
    }).success).toBe(true);
    expect(fxSnapshotSchema.safeParse({
      organizationId: org, baseCurrency: 'EGP', quoteCurrency: 'EGP',
      rateNumerator: '1', rateDenominator: '100', rateDate: '2026-08-01',
      rateSource: 'MANUAL_ENTRY', idempotencyKey: 'fx-snap-000002',
    }).success).toBe(false);
    expect(fxConversionSchema.safeParse({
      organizationId: org, projectId: '', sourceAmountMinorUnits: '250000',
      rateSnapshotId: id,
      conversionDate: '2026-08-10', purpose: 'REPORTING_ROLLUP',
      idempotencyKey: 'fx-conv-000001',
    }).success).toBe(true);
  });

  it('keeps the F6 invariants in the migration text', () => {
    expect(f6).toContain('an FX rate snapshot is an immutable captured fact');
    expect(f6).toContain('an FX conversion log row is an immutable recorded fact');
    expect(f6).toContain('rate snapshot currencies do not match the conversion');
    expect(f6).toContain('DEFERRED_PENDING_TAX_ADVISORY');
    expect(f6).not.toContain('calc_tax');
  });
});

describe('F8/F9/F10 read model invariants', () => {
  it('keeps no invented profit number anywhere', () => {
    expect(f9).toContain('project_financial_position_read');
    expect(f9).not.toMatch(/as\s+profit\b/i);
    expect(f8).toContain('financial_integrity_signals_read');
    expect(f8).toContain('UNBALANCED_BATCHES');
    expect(f8).toContain('ORG_FX_GAP');
  });

  it('never sums across currencies in roll-ups', () => {
    expect(f10).toContain('portfolio_financial_rollup_read');
    expect(f10).toContain('organization_financial_consolidation_read');
    expect(f10).toContain('NO_RATE_SNAPSHOT');
    expect(f10).toContain('CONSOLIDATION_INCOMPLETE_NO_RATE_SNAPSHOT');
    expect(scope).toContain('portfolio_financial_rollup_asof');
    expect(scope).toContain('open_commitment_minor_units');
    expect(scope).toContain('cash_concentration_ratio');
    expect(scope).toContain('sector_exposure');
  });

  it('nets reversals to zero and separates FAC components', () => {
    expect(fixes).toContain('jb.reversal_of_batch_id is null');
    expect(fixes).toContain('OPEN_APPROVAL_EXCEPTIONS');
    expect(fixes).toContain('approval_signoffs');
    expect(fixes).toContain('min_approvers between 1 and 3');
    expect(scope).toContain('project_budget_fac_read');
    expect(scope).toContain('approved_forecast_remainder_minor_units');
    expect(scope).toContain('actual_minor_units');
    expect(fixes).not.toContain('RETENTION_DUE_FOR_RELEASE');
  });

  it('keeps the tax registry explicit-contract (no computation)', () => {
    expect(taxTreatmentSchema.safeParse({
      organizationId: org, taxDomain: 'VALUE_ADDED', taxName: 'ضريبة القيمة المضافة',
      appliesTo: 'PROCUREMENT_SPEND', treatmentStatus: 'DEFERRED_PENDING_TAX_ADVISORY',
      effectiveFrom: '2026-08-01', notes: 'تتطلب اعتماد مستشار ضريبي قبل أي ترحيل',
      idempotencyKey: 'tax-000000001',
    }).success).toBe(true);
  });
});

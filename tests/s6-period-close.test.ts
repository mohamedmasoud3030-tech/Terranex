import { describe, expect, it } from 'vitest';
import {
  approveCloseSchema,
  approveCorrectionSchema,
  approveExceptionSchema,
  createAccountingPeriodSchema,
  executeCorrectionSchema,
  prepareCloseSchema,
  reopenSchema,
  requestCorrectionSchema,
  requestExceptionSchema,
} from '@/features/close/schema';

const base = {
  organizationId: '00000000-0000-4000-8000-000000000001',
  projectId: '00000000-0000-4000-8000-000000000002',
  periodId: '00000000-0000-4000-8000-000000000003',
  idempotencyKey: 'abcdefgh-1234',
};

describe('close schema', () => {
  it('accepts a valid open-period payload and rejects inverted dates', () => {
    expect(createAccountingPeriodSchema.safeParse({
      organizationId: base.organizationId,
      projectId: base.projectId,
      startDate: '2026-03-01',
      endDate: '2026-03-31',
      idempotencyKey: base.idempotencyKey,
    }).success).toBe(true);
    expect(createAccountingPeriodSchema.safeParse({
      organizationId: base.organizationId,
      projectId: base.projectId,
      startDate: '2026-03-31',
      endDate: '2026-03-01',
      idempotencyKey: base.idempotencyKey,
    }).success).toBe(false);
  });

  it('rejects open-period creation without an idempotency key', () => {
    expect(createAccountingPeriodSchema.safeParse({
      organizationId: base.organizationId,
      projectId: base.projectId,
      startDate: '2026-03-01',
      endDate: '2026-03-31',
    }).success).toBe(false);
  });

  it('accepts a valid prepare-close payload', () => {
    const parsed = prepareCloseSchema.safeParse(base);
    expect(parsed.success).toBe(true);
  });

  it('rejects a prepare-close with a short idempotency key', () => {
    const parsed = prepareCloseSchema.safeParse({ ...base, idempotencyKey: 'short' });
    expect(parsed.success).toBe(false);
  });

  it('accepts a valid approve-close payload', () => {
    const parsed = approveCloseSchema.safeParse({ ...base, closeRunId: '00000000-0000-4000-8000-000000000004' });
    expect(parsed.success).toBe(true);
  });

  it('rejects an exception with an empty reason', () => {
    const parsed = requestExceptionSchema.safeParse({
      ...base,
      closeRunId: '00000000-0000-4000-8000-000000000004',
      gateCode: 'BANK_RECONCILIATION_COVERAGE',
      reason: '',
      evidenceReference: 'BANK-OLD-001',
    });
    expect(parsed.success).toBe(false);
  });

  it('accepts a valid exception payload', () => {
    const parsed = requestExceptionSchema.safeParse({
      ...base,
      closeRunId: '00000000-0000-4000-8000-000000000004',
      gateCode: 'BANK_RECONCILIATION_COVERAGE',
      reason: 'سطر بنكي قديم لم يصل بعد',
      evidenceReference: 'BANK-OLD-001',
      materialityComment: 'غير جوهري',
    });
    expect(parsed.success).toBe(true);
  });

  it('rejects a reopen with a short reason', () => {
    const parsed = reopenSchema.safeParse({ ...base, reason: 'hi', evidenceReference: 'EV-1' });
    expect(parsed.success).toBe(false);
  });

  it('accepts a valid reopen payload', () => {
    const parsed = reopenSchema.safeParse({ ...base, reason: 'reopen for correction', evidenceReference: 'EV-1' });
    expect(parsed.success).toBe(true);
  });

  it('rejects a correction request without a target batch', () => {
    const parsed = requestCorrectionSchema.safeParse({
      ...base,
      targetBatchId: '',
      sourcePeriodId: '00000000-0000-4000-8000-000000000010',
      correctionPeriodId: '00000000-0000-4000-8000-000000000011',
      reason: 'تصحيح سعر البيع',
      evidenceReference: 'دليل-1',
    });
    expect(parsed.success).toBe(false);
  });

  it('accepts a valid correction request', () => {
    const parsed = requestCorrectionSchema.safeParse({
      ...base,
      targetBatchId: '00000000-0000-4000-8000-000000000020',
      sourcePeriodId: '00000000-0000-4000-8000-000000000010',
      correctionPeriodId: '00000000-0000-4000-8000-000000000011',
      reason: 'تصحيح سعر البيع',
      evidenceReference: 'دليل-1',
    });
    expect(parsed.success).toBe(true);
  });

  it('accepts approve-correction and execute-correction payloads', () => {
    expect(approveCorrectionSchema.safeParse({
      ...base,
      correctionRequestId: '00000000-0000-4000-8000-000000000030',
    }).success).toBe(true);
    expect(executeCorrectionSchema.safeParse({
      ...base,
      correctionRequestId: '00000000-0000-4000-8000-000000000030',
      correctionDate: '2026-08-12',
    }).success).toBe(true);
  });

  it('rejects execute-correction without a date', () => {
    const parsed = executeCorrectionSchema.safeParse({
      ...base,
      correctionRequestId: '00000000-0000-4000-8000-000000000030',
      correctionDate: '',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects approve-exception without a valid uuid', () => {
    const parsed = approveExceptionSchema.safeParse({ ...base, exceptionId: 'not-a-uuid' });
    expect(parsed.success).toBe(false);
  });

  it('rejects approve-close without a project id (used for UI refresh only)', () => {
    const { projectId, ...rest } = base;
    void projectId;
    const parsed = approveCloseSchema.safeParse({ ...rest, closeRunId: '00000000-0000-4000-8000-000000000004' });
    expect(parsed.success).toBe(false);
  });

  it('rejects request-exception without a project id', () => {
    const { projectId, periodId, ...rest } = base;
    void projectId;
    void periodId;
    const parsed = requestExceptionSchema.safeParse({
      ...rest,
      closeRunId: '00000000-0000-4000-8000-000000000004',
      gateCode: 'BANK_RECONCILIATION_COVERAGE',
      reason: 'سطر بنكي قديم لم يصل بعد',
      evidenceReference: 'BANK-OLD-001',
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects approve-correction without a project id', () => {
    const { projectId, periodId, ...rest } = base;
    void projectId;
    void periodId;
    const parsed = approveCorrectionSchema.safeParse({
      ...rest,
      correctionRequestId: '00000000-0000-4000-8000-000000000030',
    });
    expect(parsed.success).toBe(false);
  });
});

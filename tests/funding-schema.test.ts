import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  agreementDraftSchema,
  capitalCallSchema,
  contributionSchema,
} from '../src/features/funding/schema';
import {
  formatMinorUnits,
  parseMajorUnitsToMinor,
} from '../src/shared/money';

const migration = readFileSync('supabase/migrations/20260810000200_s1_terms_and_funding.sql', 'utf8');
const hardening = readFileSync('supabase/migrations/20260811000100_s1_hardening.sql', 'utf8');
const governing = readFileSync('supabase/migrations/20260811000200_s1_governing_boundary.sql', 'utf8');
const concurrency = readFileSync('supabase/tests/03_s1_concurrency.sh', 'utf8');

const orgId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const versionId = '00000000-0000-4000-8000-000000000003';
const participantId = '00000000-0000-4000-8000-000000000004';
const callId = '00000000-0000-4000-8000-000000000005';

describe('S1 exact money', () => {
  it('parses user-facing decimal text to bigint minor-unit text without Number arithmetic', () => {
    expect(parseMajorUnitsToMinor('10,000.25', 'EGP')).toBe('1000025');
    expect(parseMajorUnitsToMinor('١٠٠٠٠٫٢٥', 'EGP')).toBe('1000025');
    expect(parseMajorUnitsToMinor('92233720368547758.07', 'EGP')).toBe('9223372036854775807');
    expect(() => parseMajorUnitsToMinor('92233720368547758.08', 'EGP')).toThrow();
  });

  it('formats full int64 values without rejecting them as unsafe JavaScript numbers', () => {
    expect(formatMinorUnits('9223372036854775807', 'EGP')).not.toBe('—');
    expect(formatMinorUnits(Number.MAX_SAFE_INTEGER + 1, 'EGP')).toBe('—');
  });
});

describe('S1 funding validation', () => {
  it('requires a retry key, participant, and positive user-facing commitment', () => {
    expect(agreementDraftSchema.safeParse({
      organizationId: orgId,
      projectId,
      effectiveDate: '2026-08-10',
      idempotencyKey: 'agreement-0001',
      participants: [{ participantId, commitmentAmount: '0' }],
    }).success).toBe(false);

    expect(agreementDraftSchema.safeParse({
      organizationId: orgId,
      projectId,
      effectiveDate: '2026-08-10',
      idempotencyKey: 'agreement-0001',
      participants: [{ participantId, commitmentAmount: '10000.25' }],
    }).success).toBe(true);
  });

  it('filters blank investors from a capital call and rejects over-precision', () => {
    const parsed = capitalCallSchema.safeParse({
      organizationId: orgId,
      projectId,
      agreementVersionId: versionId,
      dueDate: '2026-09-15',
      reference: 'CALL-1',
      idempotencyKey: 'call-00000001',
      lines: [
        { participantId, amount: '' },
        { participantId: callId, amount: '5000.50' },
      ],
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.lines).toHaveLength(1);

    expect(capitalCallSchema.safeParse({
      organizationId: orgId,
      projectId,
      agreementVersionId: versionId,
      dueDate: '2026-09-15',
      idempotencyKey: 'call-00000002',
      lines: [{ participantId, amount: '1.005' }],
    }).success).toBe(false);
  });

  it('requires ISO currency, exact amount text, and an idempotency key for contributions', () => {
    expect(contributionSchema.safeParse({
      organizationId: orgId,
      projectId,
      participantId,
      agreementVersionId: versionId,
      capitalCallId: callId,
      amount: '500.00',
      currency: 'egp',
      occurredOn: '2026-09-12',
      idempotencyKey: 'short',
    }).success).toBe(false);
  });
});

describe('S1 database contract', () => {
  it('keeps browser writes behind locked SECURITY DEFINER commands', () => {
    expect(migration).toContain('security definer set search_path=pg_catalog,public');
    expect(migration).not.toContain('grant insert on public.contributions to authenticated');
    expect(migration).not.toContain('grant update on public.agreement_versions to authenticated');
  });

  it('binds retries to payloads and serializes economic ceilings', () => {
    expect(hardening).toContain("pg_advisory_xact_lock");
    expect(hardening).toContain("idempotency key payload mismatch");
    expect(hardening).toContain('order by participant_id\n  for update');
    expect(hardening).toContain('from public.capital_call_lines\n  where capital_call_id = p_capital_call_id and participant_id = p_participant_id\n  for update');
  });

  it('transports bigint money to JavaScript as text and keeps derived balances read-only', () => {
    expect(hardening).toContain('commitment_minor_units::text');
    expect(hardening).toContain('project_capital_position_read');
    expect(migration).toContain('create or replace view public.project_capital_position');
    expect(migration).not.toMatch(/contributed_capital\s+(bigint|numeric|integer)/i);
  });

  it('freezes the S1 governing boundary after first activation', () => {
    expect(governing).toContain('project participants are frozen after agreement activation');
    expect(governing).toContain('agreement amendments are deferred while an active version governs the project');
  });

  it('contains a real two-session PostgreSQL concurrency gate', () => {
    expect(concurrency).toContain('run_session "$SQL_CONTRIB_A"');
    expect(concurrency).toContain('run_session "$SQL_CONTRIB_B"');
    expect(concurrency).toContain('run_session "$SQL_CALL_A"');
    expect(concurrency).toContain('run_session "$SQL_CALL_B"');
    expect(concurrency).toContain('assert_one_success');
  });
});

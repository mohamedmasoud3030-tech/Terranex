import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  agreementDraftSchema,
  capitalCallSchema,
  contributionSchema,
} from '../src/features/funding/schema';

const migration = readFileSync(
  'supabase/migrations/20260810000200_s1_terms_and_funding.sql',
  'utf8',
);

describe('S1 funding validation', () => {
  it('requires positive integer minor-unit commitments and at least one participant', () => {
    expect(
      agreementDraftSchema.safeParse({
        organizationId: '00000000-0000-4000-8000-000000000001',
        projectId: '00000000-0000-4000-8000-000000000002',
        effectiveDate: '2026-08-10',
        participants: [{ participantId: '00000000-0000-4000-8000-000000000003', commitmentMinorUnits: 0 }],
      }).success,
    ).toBe(false);
    expect(
      agreementDraftSchema.safeParse({
        organizationId: '00000000-0000-4000-8000-000000000001',
        projectId: '00000000-0000-4000-8000-000000000002',
        effectiveDate: '2026-08-10',
        participants: [{ participantId: '00000000-0000-4000-8000-000000000003', commitmentMinorUnits: 1000 }],
      }).success,
    ).toBe(true);
  });

  it('rejects zero or fractional capital call amounts', () => {
    expect(
      capitalCallSchema.safeParse({
        organizationId: '00000000-0000-4000-8000-000000000001',
        projectId: '00000000-0000-4000-8000-000000000002',
        agreementVersionId: '00000000-0000-4000-8000-000000000003',
        dueDate: '2026-09-15',
        lines: [{ participantId: '00000000-0000-4000-8000-000000000004', amountMinorUnits: 1.5 }],
      }).success,
    ).toBe(false);
  });

  it('requires an ISO currency and an idempotency key for contributions', () => {
    expect(
      contributionSchema.safeParse({
        organizationId: '00000000-0000-4000-8000-000000000001',
        projectId: '00000000-0000-4000-8000-000000000002',
        participantId: '00000000-0000-4000-8000-000000000004',
        agreementVersionId: '00000000-0000-4000-8000-000000000003',
        capitalCallId: '00000000-0000-4000-8000-000000000005',
        contributionMinorUnits: 500,
        currency: 'egp',
        occurredOn: '2026-09-12',
        idempotencyKey: 'short',
      }).success,
    ).toBe(false);
  });
});

describe('S1 database authorization contract', () => {
  it('keeps material writes inside atomic, idempotent SECURITY DEFINER RPCs', () => {
    expect(migration).toContain('create or replace function public.activate_agreement_version');
    expect(migration).toContain('create or replace function public.create_capital_call');
    expect(migration).toContain('create or replace function public.record_contribution');
    expect(migration).toContain('idempotency_key');
    expect(migration).toContain('security definer set search_path=pg_catalog,public');
  });

  it('never grants browser write access to tenant-owned funding tables', () => {
    expect(migration).toContain('enable row level security');
    expect(migration).not.toContain('grant insert on public.contributions to authenticated');
    expect(migration).not.toContain('grant update on public.agreement_versions to authenticated');
    expect(migration).toContain(
      'grant select on public.parties, public.project_participants, public.investment_agreements,',
    );
  });

  it('derives capital positions from authoritative records rather than editable balances', () => {
    expect(migration).toContain('create or replace view public.partner_capital_position');
    expect(migration).toContain('create or replace view public.project_capital_position');
    expect(migration).not.toMatch(/contributed_capital\s+(bigint|numeric|integer)/i);
  });
});

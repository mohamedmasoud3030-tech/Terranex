import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  bankImportSchema,
  cashAccountSchema,
  obligationSchema,
  paymentSchema,
  reconcileSchema,
  reversalSchema,
  voidReconciliationSchema,
} from '../src/features/finance/schema';

const migration = readFileSync('supabase/migrations/20260811000300_s2_cost_and_cash.sql', 'utf8');

const orgId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const partyId = '00000000-0000-4000-8000-000000000003';
const obligationId = '00000000-0000-4000-8000-000000000004';
const accountId = '00000000-0000-4000-8000-000000000005';
const paymentId = '00000000-0000-4000-8000-000000000006';
const lineId = '00000000-0000-4000-8000-000000000007';
const matchId = '00000000-0000-4000-8000-000000000008';

describe('S2 obligation validation', () => {
  it('requires explicit cost treatment, exact money text, and a retry key', () => {
    const base = {
      organizationId: orgId,
      projectId,
      partyId,
      description: 'أعمال حفر',
      amount: '400000.00',
      currency: 'EGP',
      transactionDate: '2026-08-15',
      idempotencyKey: 'obl-00000001',
    };
    expect(obligationSchema.safeParse({ ...base, costTreatment: 'EXPENSE' }).success).toBe(true);
    expect(obligationSchema.safeParse({ ...base, costTreatment: 'CAPITALIZABLE_WIP' }).success).toBe(true);
    expect(obligationSchema.safeParse({ ...base, costTreatment: 'SOMETHING_ELSE' }).success).toBe(false);
    expect(obligationSchema.safeParse({ ...base, costTreatment: 'EXPENSE', amount: '0' }).success).toBe(false);
    expect(obligationSchema.safeParse({ ...base, costTreatment: 'EXPENSE', amount: '1.005' }).success).toBe(false);
    expect(obligationSchema.safeParse({ ...base, costTreatment: 'EXPENSE', idempotencyKey: 'short' }).success).toBe(false);
  });

  it('requires a positive payment amount and a date', () => {
    expect(paymentSchema.safeParse({
      organizationId: orgId,
      obligationId,
      cashAccountId: accountId,
      amount: '150000',
      paymentDate: '2026-08-25',
      idempotencyKey: 'pay-00000001',
    }).success).toBe(true);
    expect(paymentSchema.safeParse({
      organizationId: orgId,
      obligationId,
      cashAccountId: accountId,
      amount: '-5',
      paymentDate: '2026-08-25',
      idempotencyKey: 'pay-00000002',
    }).success).toBe(false);
  });

  it('validates cash accounts and contribution attribution', () => {
    expect(cashAccountSchema.safeParse({
      organizationId: orgId, projectId, name: 'حساب البنك', currency: 'EGP',
    }).success).toBe(true);
    expect(cashAccountSchema.safeParse({
      organizationId: orgId, projectId, name: 'حساب البنك', currency: 'egp',
    }).success).toBe(false);
  });
});

describe('S2 bank CSV contract', () => {
  it('accepts signed amounts, optional reference, and rejects bad rows', () => {
    const lines = [
      { transactionDate: '2026-08-25', amount: '-150000', currency: 'EGP', description: 'دفعة للمورد', providerReference: 'TXN-1' },
      { transactionDate: '2026-08-26', amount: '+250000', currency: 'EGP', description: 'إيداع', providerReference: '' },
    ];
    expect(bankImportSchema.safeParse({
      organizationId: orgId, cashAccountId: accountId, idempotencyKey: 'import-00001', lines,
    }).success).toBe(true);
    expect(bankImportSchema.safeParse({
      organizationId: orgId, cashAccountId: accountId, idempotencyKey: 'import-00002',
      lines: [{ ...lines[0], amount: '0' }],
    }).success).toBe(false);
    expect(bankImportSchema.safeParse({
      organizationId: orgId, cashAccountId: accountId, idempotencyKey: 'import-00003',
      lines: [{ ...lines[0], amount: '-1.005' }],
    }).success).toBe(false);
  });
});

describe('S2 reconciliation and reversal validation', () => {
  it('requires reasons and retry keys for material corrections', () => {
    expect(reconcileSchema.safeParse({
      organizationId: orgId, paymentId, statementLineId: lineId, idempotencyKey: 'recon-000001',
    }).success).toBe(true);
    expect(voidReconciliationSchema.safeParse({
      organizationId: orgId, matchId, reason: 'مطابقة خاطئة', idempotencyKey: 'void-0000001',
    }).success).toBe(true);
    expect(voidReconciliationSchema.safeParse({
      organizationId: orgId, matchId, reason: 'x', idempotencyKey: 'void-0000002',
    }).success).toBe(false);
    expect(reversalSchema.safeParse({
      organizationId: orgId, batchId: matchId, reason: 'قيد خاطئ', idempotencyKey: 'rev-00000001',
    }).success).toBe(true);
    expect(reversalSchema.safeParse({
      organizationId: orgId, batchId: matchId, reason: 'قيد خاطئ', idempotencyKey: 'short',
    }).success).toBe(false);
  });
});

describe('S2 migration contract', () => {
  it('keeps balanced-posting enforcement in the database', () => {
    expect(migration).toContain('journal_lines_balance_guard');
    expect(migration).toContain('journal batch is unbalanced');
    expect(migration).toContain('s2_guard_batch_balanced');
  });

  it('makes posted batches and lines immutable', () => {
    expect(migration).toContain('journal_batches_immutable');
    expect(migration).toContain('journal_lines_immutable');
    expect(migration).toContain('journal batches and lines are immutable once posted');
  });

  it('uses server-authoritative transactional commands with locked search paths', () => {
    for (const rpc of [
      'attach_contribution_cash',
      'authorize_cost_obligation',
      'pay_cost_obligation',
      'import_bank_statement_lines',
      'reconcile_payment',
      'reverse_journal_batch',
    ]) {
      const fn = migration.split(`create or replace function public.${rpc}(`)[1];
      expect(fn, rpc).toBeDefined();
      expect(fn.slice(0, 400), rpc).toContain('security definer set search_path=pg_catalog,public');
      expect(fn.slice(0, 400), rpc).toContain('auth.uid()');
    }
  });

  it('keeps browser table writes default-deny on material S2 tables', () => {
    const revokeSection = migration.split('revoke all on public.project_cash_accounts')[1].split('from anon')[0];
    const grantSection = migration.split('grant select on public.project_cash_accounts')[1].split('to authenticated')[0];
    expect(migration).toContain('revoke all on public.project_cash_accounts');
    expect(migration).toContain('grant select on public.project_cash_accounts');
    for (const table of [
      'journal_batches',
      'journal_lines',
      'cost_obligations',
      'project_payments',
      'bank_statement_lines',
      'reconciliation_matches',
    ]) {
      expect(revokeSection).toContain(`public.${table}`);
      expect(grantSection).toContain(`public.${table}`);
    }
    expect(migration).not.toContain('grant insert on public.journal_lines');
    expect(migration).not.toContain('grant update on public.cost_obligations');
    expect(migration).not.toContain('grant delete on public.journal_batches');
  });

  it('exposes money to the browser as text only', () => {
    for (const view of [
      'project_cash_position_read',
      'cost_obligation_position_read',
      'payment_status_read',
      'bank_statement_line_status_read',
    ]) {
      expect(migration).toContain(`create or replace view public.${view}`);
      expect(migration).toContain('::text');
    }
  });

  it('uses locked semantic account roles, not hard-coded account numbers', () => {
    expect(migration).toContain("role in (\n    'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP'");
    expect(migration).toContain('semantic_accounts_locked');
  });

  it('keeps a deterministic CSV fingerprint contract and no-import-economics rule', () => {
    expect(migration).toContain('unique (organization_id, cash_account_id, fingerprint)');
    expect(migration).toContain('bank statement line already imported');
    const importFn = migration.split('create or replace function public.import_bank_statement_lines(')[1];
    expect(importFn).toBeDefined();
    expect(importFn.slice(0, importFn.indexOf('end $$'))).not.toContain('insert into public.journal_lines');
    expect(importFn.slice(0, importFn.indexOf('end $$'))).not.toContain('insert into public.journal_batches');
  });
});

import { describe, expect, it } from 'vitest'; import { readFileSync } from 'node:fs';
const migration=readFileSync('supabase/migrations/20260810000100_s0_foundation.sql','utf8');
describe('S0 server authorization contract',()=>{it('derives actors and checks active membership in transactional commands',()=>{expect(migration).toContain('v_actor uuid:=auth.uid()'); expect(migration).toContain('if not public.is_active_member(p_organization_id) then raise exception \'forbidden\'; end if'); expect(migration).toContain('security definer set search_path=pg_catalog,public');});it('makes browser table writes default-deny',()=>{expect(migration).toContain('enable row level security'); expect(migration).toContain('grant select on public.organizations,public.memberships,public.investment_projects,public.audit_events to authenticated'); expect(migration).not.toContain('grant insert on public.investment_projects to authenticated');});});

const s2Migration=readFileSync('supabase/migrations/20260811000300_s2_cost_and_cash.sql','utf8');
describe('S2 server authorization contract',()=>{
  it('reserves posting, payment, reconciliation, and reversal for the organization owner',()=>{
    expect(s2Migration).toContain('forbidden: organization owner required');
    expect(s2Migration).toContain('perform public.s2_require_owner(p_organization_id)');
    const ownerOnly=['attach_contribution_cash','authorize_cost_obligation','pay_cost_obligation','reconcile_payment','void_reconciliation','reverse_journal_batch'];
    for(const rpc of ownerOnly){
      const fn=s2Migration.split(`create or replace function public.${rpc}(`)[1];
      expect(fn, rpc).toBeDefined();
      expect(fn.slice(0,1200), rpc).toContain('perform public.s2_require_owner(p_organization_id)');
    }
    const memberOk=['create_cost_obligation','import_bank_statement_lines','create_project_cash_account'];
    for(const rpc of memberOk){
      const fn=s2Migration.split(`create or replace function public.${rpc}(`)[1];
      expect(fn, rpc).toBeDefined();
      expect(fn.slice(0,900), rpc).not.toContain('perform public.s2_require_owner(p_organization_id)');
    }
  });
  it('enables RLS and denies browser writes on every S2 tenant table',()=>{
    const revokeSection=s2Migration.split('revoke all on public.project_cash_accounts')[1].split('from anon')[0];
    expect(s2Migration).toContain('revoke all on public.project_cash_accounts');
    for(const table of ['semantic_accounts','journal_batches','journal_lines','cost_obligations','project_payments','bank_statement_imports','bank_statement_lines','reconciliation_matches']){
      expect(s2Migration).toContain(`alter table public.${table} enable row level security`);
      expect(s2Migration).toContain(`alter table public.${table} force row level security`);
      expect(revokeSection).toContain(`public.${table}`);
    }
  });
});

const s6AuthMigration=readFileSync('supabase/migrations/20260812000300_s6_evaluate_gate_authorization.sql','utf8');
describe('S6 evaluate gate authorization contract',()=>{
  it('isolates s6_evaluate_gate_core from browser roles',()=>{
    expect(s6AuthMigration).toContain('revoke all on function public.s6_evaluate_gate_core(uuid, uuid, uuid, text)');
    expect(s6AuthMigration).toContain('from public, anon, authenticated');
  });
  it('enforces owner authorization and scope validation on s6_evaluate_gate',()=>{
    expect(s6AuthMigration).toContain('perform public.s2_require_owner(p_organization_id)');
    expect(s6AuthMigration).toContain('project not found in organization');
    expect(s6AuthMigration).toContain('period not found for this project');
    expect(s6AuthMigration).toContain('grant execute on function public.s6_evaluate_gate(uuid, uuid, uuid, text)');
  });
});


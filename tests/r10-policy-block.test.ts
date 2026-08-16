import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { emptyIntakeSnapshot, evaluateIntakeReadiness } from '@/features/intake/readiness';

const investorPage = readFileSync('src/app/(app)/projects/[projectId]/investors/page.tsx', 'utf8');
const statementsPage = readFileSync('src/app/(app)/projects/[projectId]/statements/page.tsx', 'utf8');
const overviewPage = readFileSync('src/app/(app)/projects/[projectId]/overview/page.tsx', 'utf8');
const intakePage = readFileSync('src/app/(app)/projects/[projectId]/intake/page.tsx', 'utf8');
const intakeReadiness = readFileSync('src/features/intake/readiness.ts', 'utf8');
const termsForms = readFileSync('src/app/(app)/projects/[projectId]/terms/forms.tsx', 'utf8');
const investorsForms = readFileSync('src/app/(app)/projects/[projectId]/investors/forms.tsx', 'utf8');
const decisions = readFileSync('docs/OPEN_BUSINESS_DECISIONS.md', 'utf8');
const preOwnerPolicyMigration = readFileSync('supabase/migrations/20260816062000_pre_owner_policy_safety.sql', 'utf8');
const pilotPage = readFileSync('src/app/(app)/projects/[projectId]/pilot/page.tsx', 'utf8');
const controlsPage = readFileSync('src/app/(app)/projects/[projectId]/controls/page.tsx', 'utf8');
const closePage = readFileSync('src/app/(app)/projects/[projectId]/close/page.tsx', 'utf8');

const S5_FORM_NAMES = /ConfigureRulesForm|PrepareAllocationForm|ApproveAllocationForm|PrepareDistributionForm|ApproveDistributionForm|PayDistributionForm/;
const S5_READ_NAMES = /getAllocationRuleSets|getAllocationRuns|getAllocationLines|getDistributions|getDistributionCapacity|getPartnerCapitalStatement/;
const S5_IMPORT_PATHS = /features\/allocation|investors\/forms/;

// Explicit allowlist: the dormant S5 allocation/distribution implementation itself.
// Only these exact runtime files may reference the policy-dependent S5 surface;
// every other runtime source under src/ must stay free of it, so a newly created
// live component that transitively imports the dormant machinery fails the guard.
const DORMANT_S5_ALLOWLIST: ReadonlySet<string> = new Set([
  'src/features/allocation/actions.ts',
  'src/features/allocation/queries.ts',
  'src/features/allocation/schema.ts',
  'src/app/(app)/projects/[projectId]/investors/forms.tsx',
]);

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

// Every runtime TypeScript source under src/, normalised to forward slashes.
function runtimeSourceFiles(): string[] {
  return walk('src')
    .map((file) => file.replaceAll('\\', '/'))
    .filter((file) => file.endsWith('.ts') || file.endsWith('.tsx'));
}

describe('R10 keeps unresolved investor economics inert until R14', () => {
  it('keeps the canonical business decisions open', () => {
    for (const id of ['BD-003', 'BD-004', 'BD-006', 'BD-008']) {
      expect(decisions).toMatch(new RegExp(`\\| ${id} \\| OPEN \\|`));
    }
  });

  it('does not import entitlement runtime from the investor surface', () => {
    expect(investorPage).not.toMatch(/features\/allocation/);
    expect(investorPage).not.toMatch(/ConfigureRulesForm|PrepareAllocationForm|ApproveAllocationForm/);
    expect(investorPage).not.toMatch(/PrepareDistributionForm|ApproveDistributionForm|PayDistributionForm/);
    expect(investorPage).not.toMatch(/getDistributionCapacity|getPartnerCapitalStatement|getAllocation/);
  });

  it('states the policy block explicitly instead of silently showing zeros', () => {
    expect(investorPage).toContain('Policy Blocked — BD-003 / BD-004 / BD-006 / BD-008');
    expect(investorPage).toContain('لا يعرض Terranex حاليًا نسبة ملكية');
    expect(investorPage).toContain('أي حقل entitlement أو allocation أو distribution يظل غير فعال حتى R14');
  });

  it('allows identity and agreement transparency without inferring economics', () => {
    expect(investorPage).toContain('getParticipants');
    expect(investorPage).toContain('getActiveVersion');
    expect(investorPage).toContain('الهوية المسجلة لا تعني تلقائيًا ملكية أو entitlement أو حصة في الربح');
  });

  it('redirects the legacy partner statement surface to the safe R10 page', () => {
    expect(statementsPage).toMatch(/redirect\(`\/projects\/\$\{projectId\}\/investors`\)/);
    expect(statementsPage).not.toMatch(/getPartnerCapitalStatement|formatMinorUnits|features\/allocation/);
  });

  it('keeps distribution economics out of the project overview', () => {
    expect(overviewPage).not.toMatch(/getDistributions|approvedDistributions|paidDistributions/);
    expect(overviewPage).toContain('BD-006 وBD-008');
    expect(overviewPage).toContain('ليست حصة مستثمر');
  });
});

describe('post-R14 policy-safety hotfix: the intake policy leak is closed while BD-004/BD-006 remain OPEN', () => {
  it('Proof 1 — the intake route does not import or render ConfigureRulesForm', () => {
    expect(intakePage).not.toMatch(/ConfigureRulesForm/);
    expect(intakePage).not.toMatch(/investors\/forms/);
  });

  it('Proof 2 — the intake route does not query allocation rules for readiness', () => {
    expect(intakePage).not.toMatch(/getAllocationRuleSets|features\/allocation/);
    expect(intakePage).not.toMatch(/allocationRulesConfigured|activeRuleSet/);
  });

  it('Proof 3 — readiness does not require ownership weights', () => {
    const result = evaluateIntakeReadiness({
      ...emptyIntakeSnapshot(),
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 1,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 1,
      agreementTitleOrReference: 'اتفاقية',
    });
    const agreement = result.sections.find((section) => section.code === 'DS04_AGREEMENT')!;
    expect(agreement.status).toBe('COMPLETE');
    expect(agreement.blockingReasons).toHaveLength(0);
  });

  it('Proof 4 — readiness does not require allocation weights', () => {
    expect(intakeReadiness).not.toMatch(/allocationRulesConfigured/);
    expect(intakeReadiness).not.toMatch(/أوزان الملكية\/التخصيص|أوزان ملكية|أوزان التخصيص/);
    expect(Object.hasOwn(emptyIntakeSnapshot(), 'allocationRulesConfigured')).toBe(false);
  });

  it('Proof 5 — no live readiness/intake requirement states or implies ownership/allocation must total 100%', () => {
    expect(intakeReadiness).not.toMatch(/100٪|مجموعها 100|100%/);
    expect(intakePage).not.toMatch(/100٪/);
    const result = evaluateIntakeReadiness({
      ...emptyIntakeSnapshot(),
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 1,
      activeAgreement: true,
      agreementEffectiveDate: '2025-01-01',
      commitmentCount: 1,
    });
    const agreement = result.sections.find((section) => section.code === 'DS04_AGREEMENT')!;
    expect(agreement.blockingReasons.join(' ')).not.toMatch(/100|أوزان/);
  });

  it('Proof 6 — commitments remain distinguishable from ownership/entitlement (DS05 separation preserved)', () => {
    // AgreementDraftForm still records the explicit commitmentAmount fact.
    expect(termsForms).toContain('commitmentAmount');
    // DS05 wording keeps the load-bearing concept separation.
    expect(intakeReadiness).toContain('الالتزام ≠ المطلوب ≠ المساهمة');
    // The dormant S5 rules form keeps the "commitment does not define ownership" guard.
    expect(investorsForms).toContain('مبالغ الالتزام أو المساهمات لا تحدد الملكية ولا حصة الربح');
  });

  it('Proof 7 — dormant S5 allocation mechanics are unreachable from live runtime outside the dormant allowlist', () => {
    const sources = runtimeSourceFiles();
    expect(sources.length).toBeGreaterThan(0);
    for (const file of sources) {
      if (DORMANT_S5_ALLOWLIST.has(file)) continue;
      const content = readFileSync(file, 'utf8');
      expect(content, `${file} must not import the dormant S5 allocation/distribution surface`)
        .not.toMatch(S5_IMPORT_PATHS);
      expect(content, `${file} must not render dormant S5 allocation/distribution forms`)
        .not.toMatch(S5_FORM_NAMES);
      expect(content, `${file} must not read dormant S5 allocation/distribution state`)
        .not.toMatch(S5_READ_NAMES);
    }
  });
});

describe('pre-owner policy-safety boundary: policy-dependent writes fail closed', () => {
  it('gates every S5 write table behind an approved INVESTOR_ECONOMICS policy', () => {
    expect(preOwnerPolicyMigration).toContain('target-company investor policy is not activated');
    for (const gate of [
      's5_allocation_rule_sets_policy_gate',
      's5_allocation_rules_policy_gate',
      's5_allocation_runs_policy_gate',
      's5_allocation_lines_policy_gate',
      's5_distributions_policy_gate',
      's5_distribution_payments_policy_gate',
    ]) {
      expect(preOwnerPolicyMigration, gate).toContain(gate);
    }
    // The policy registry ships empty: no fake approved row exists.
    expect(preOwnerPolicyMigration).not.toMatch(/insert into public\.policy_authority/);
  });

  it('stops the contributed-capital posting from being a universal funding command', () => {
    // attach_contribution_cash requires an approved CAPITAL_CONTRIBUTION policy
    // (BD-002/005 OPEN), so CASH RECEIPT is never CONTRIBUTED CAPITAL by implication.
    const attach = preOwnerPolicyMigration.split('create or replace function public.attach_contribution_cash(')[1];
    expect(attach).toBeDefined();
    expect(attach).toContain("require_policy_activated(p_organization_id, 'CAPITAL_CONTRIBUTION')");
    // Historical idempotent replay must succeed BEFORE the policy gate: the
    // replay `return v_existing.id` must precede the policy activation check,
    // so only NEW postings fail closed.
    const gateIndex = attach.indexOf("require_policy_activated(p_organization_id, 'CAPITAL_CONTRIBUTION')");
    const replayReturnIndex = attach.indexOf('return v_existing.id');
    expect(gateIndex).toBeGreaterThan(-1);
    expect(replayReturnIndex).toBeGreaterThan(-1);
    expect(replayReturnIndex).toBeLessThan(gateIndex);
  });

  it('makes distribution-payment reconciliation idempotency NULL-safe', () => {
    const reconcile = preOwnerPolicyMigration.split('create or replace function public.s5_reconcile_distribution_payment(')[1];
    expect(reconcile).toBeDefined();
    expect(reconcile).toContain('distribution payment and statement line are required');
    expect(reconcile).toContain('is distinct from');
  });

  it('raises S1 agreement activation and capital-call issuance to OWNER authority', () => {
    for (const rpc of ['activate_agreement_version', 'create_capital_call']) {
      const fn = preOwnerPolicyMigration.split(`create or replace function public.${rpc}(`)[1];
      expect(fn, rpc).toBeDefined();
      expect(fn, rpc).toContain('perform public.s2_require_owner(p_organization_id)');
    }
  });

  it('read-labels the stale S5 source as Real Estate sale only (never universal realized result)', () => {
    expect(preOwnerPolicyMigration).toContain('comment on function public.s5_realized_result_as_of_snapshot');
    expect(preOwnerPolicyMigration).toContain('NOT a universal Project realized result');
    expect(preOwnerPolicyMigration).toContain('comment on column public.s5_allocation_runs.source_category');
  });

  it('stops the pilot/controls surfaces from exposing investor-statement and partner-capital values', () => {
    expect(pilotPage).not.toMatch(/investor_statement_total|partner_capital_rollforward_breaks/);
    expect(controlsPage).not.toMatch(/investor_statement_total|partner_capital_rollforward_breaks|تطابق رأس مال الشركاء/);
    expect(controlsPage).toContain('تبقى آليات التخصيص والتوزيع محجوبة');
  });

  it('stops the close page from instructing operators to allocate/distribute', () => {
    expect(closePage).not.toMatch(/لإصدار قرار التخصيص/);
    expect(closePage).not.toContain('الإغلاق والتوزيع');
  });

  it('no longer requires an investor, agreement, or commitment for intake readiness', () => {
    const result = evaluateIntakeReadiness({
      ...emptyIntakeSnapshot(),
      organizationName: 'أ',
      projectName: 'ب',
      investorCount: 0,
      activeAgreement: false,
    });
    expect(result.sections.find((s) => s.code === 'DS03_PARTIES')?.status).toBe('NOT_APPLICABLE');
    expect(result.sections.find((s) => s.code === 'DS04_AGREEMENT')?.status).toBe('NOT_APPLICABLE');
    expect(result.sections.find((s) => s.code === 'DS05_COMMITMENTS')?.status).toBe('NOT_APPLICABLE');
    expect(result.mandatoryMissing).not.toContain('DS03_PARTIES');
    expect(result.mandatoryMissing).not.toContain('DS04_AGREEMENT');
    expect(result.mandatoryMissing).not.toContain('DS05_COMMITMENTS');
  });
});

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const seed = readFileSync('scripts/demo/seed_real_estate_showcase.sql', 'utf8');
const policyMigration = readFileSync('supabase/migrations/20260816062000_pre_owner_policy_safety.sql', 'utf8');

describe('demo showcase seed stays compatible with the pre-owner policy boundary', () => {
  it('activates both policy scopes for the demo organization inside the seed', () => {
    expect(seed).toContain("'CAPITAL_CONTRIBUTION'");
    expect(seed).toContain("'INVESTOR_ECONOMICS'");
    expect(seed).toContain('DEMO-SHOWCASE-POLICY-2026-01');
    expect(seed).toMatch(/insert into public\.policy_authority/);
    expect(seed).toContain('on conflict (organization_id, scope) do nothing');
  });

  it('activates the demo policy before any policy-gated command runs', () => {
    const insertIdx = seed.indexOf('insert into public.policy_authority');
    const attachIdx = seed.indexOf('attach_contribution_cash');
    const s5Idx = seed.indexOf('s5_configure_allocation_rules');
    expect(insertIdx).toBeGreaterThan(-1);
    expect(insertIdx).toBeLessThan(attachIdx);
    expect(insertIdx).toBeLessThan(s5Idx);
  });

  it('keeps the policy registry empty in the corrective migration itself', () => {
    // The migration ships an EMPTY registry; only the synthetic demo seed
    // activates policy for its own demo organization.
    expect(policyMigration).not.toMatch(/insert into public\.policy_authority/);
  });

  it('labels the demo policy as synthetic, never a real company policy', () => {
    const activation = seed.split('insert into public.policy_authority')[1];
    expect(activation).toContain('DEMO-SHOWCASE-POLICY-2026-01');
    expect(activation).toContain('synthetic demo fixture');
  });
});

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  ABSENCE_REASON_LABEL,
  ASSET_CLASSIFICATION_LABEL,
  ASSET_KIND_LABEL,
  ASSET_STATE_LABEL,
  BASIS_LABEL,
  FX_STATUS_LABEL,
  SECTOR_LABEL,
  isAbsence,
  statusLabel,
} from '../src/features/assets/labels';

const migration = readFileSync(
  'supabase/migrations/20260816059000_r8_cross_sector_asset_and_performance.sql',
  'utf8',
);
const gate = readFileSync(
  'supabase/tests/92_r8_cross_sector_asset_and_performance.sql',
  'utf8',
);
const queries = readFileSync('src/features/assets/queries.ts', 'utf8');
const page = readFileSync('src/app/(app)/assets/page.tsx', 'utf8');
const layout = readFileSync('src/app/(app)/layout.tsx', 'utf8');

describe('R8 stays a read projection and never becomes a universal asset table', () => {
  it('creates only views — no base table, no new FK target', () => {
    expect(migration).toMatch(/create or replace view public\.cross_sector_asset_register_read/);
    expect(migration).toMatch(/create or replace view public\.sector_performance_read/);
    expect(migration).not.toMatch(/create table/i);
    expect(migration).not.toMatch(/alter table/i);
    expect(migration).not.toMatch(/references\s+public\.cross_sector_asset_register_read/i);
  });

  it('adds no write command and no new domain fact', () => {
    // The canonical rule is that sector roots own their own writes. A
    // function here would mean R8 had quietly taken ownership of them.
    expect(migration).not.toMatch(/create (or replace )?function/i);
    expect(migration).not.toMatch(/security definer/i);
    expect(migration).not.toMatch(/\binsert into\b/i);
    expect(migration).not.toMatch(/\bupdate\b\s+public\./i);
    expect(migration).not.toMatch(/\bdelete from\b/i);
  });

  it('ships no server action or RPC builder in the feature', () => {
    // Read-only means read-only at every layer, not just in SQL.
    expect(() => readFileSync('src/features/assets/actions.ts', 'utf8')).toThrow();
    expect(() => readFileSync('src/features/assets/rpc.ts', 'utf8')).toThrow();
    expect(queries).not.toMatch(/use server/);
    expect(queries).not.toMatch(/\.rpc\(/);
    expect(queries).not.toMatch(/\.insert\(|\.update\(|\.delete\(|\.upsert\(/);
  });

  it('keeps both views security_invoker so tenancy is inherited from RLS', () => {
    const invokerViews = migration.match(/with \(security_invoker=on\) as/g) ?? [];
    expect(invokerViews).toHaveLength(2);
  });

  it('grants select to authenticated only and closes public/anon', () => {
    expect(migration).toMatch(
      /revoke all on public\.cross_sector_asset_register_read from public, anon;/,
    );
    expect(migration).toMatch(/revoke all on public\.sector_performance_read from public, anon;/);
    expect(migration).toMatch(
      /grant select on public\.cross_sector_asset_register_read to authenticated;/,
    );
    expect(migration).toMatch(/grant select on public\.sector_performance_read to authenticated;/);
    // Only SELECT is ever granted.
    expect(migration).not.toMatch(/grant (insert|update|delete|all)/i);
  });
});

describe('R8 reports facts or reasons, never guessed numbers', () => {
  it('reads every sector root rather than inventing a shared one', () => {
    for (const root of [
      'public.property_assets',
      'public.agricultural_land_assets',
      'public.farms',
      'public.livestock_sites',
    ]) {
      expect(migration).toContain(root);
    }
  });

  it('only surfaces APPROVED valuations', () => {
    expect(migration).toMatch(/v\.status = 'APPROVED'/);
  });

  it('marks sectors with no valuation policy as explicitly unavailable', () => {
    const unavailable =
      migration.match(/UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY/g) ?? [];
    // Three non-real-estate kinds, each with a valuation and a result status.
    expect(unavailable.length).toBeGreaterThanOrEqual(6);
  });

  it('distinguishes "not entered yet" from "does not apply"', () => {
    expect(migration).toContain('NOT_RECORDED');
    expect(migration).toContain('NOT_APPLICABLE_NO_ACQUISITION_FACT');
    expect(migration).toContain('NOT_MODELLED_FOR_THIS_ASSET_KIND');
    expect(ABSENCE_REASON_LABEL.NOT_RECORDED).not.toBe(
      ABSENCE_REASON_LABEL.NOT_APPLICABLE_NO_ACQUISITION_FACT,
    );
  });

  it('reuses the existing honesty vocabulary instead of inventing a dialect', () => {
    // livestock_cohort_results_read already says
    // UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY for the same idea.
    expect(migration).toContain('UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY');
  });
});

describe('R8 sector roll-up follows the established roll-up canon', () => {
  it('groups by currency so totals never mix currencies', () => {
    expect(migration).toMatch(/group by pc\.organization_id, pc\.sector, pc\.currency/);
  });

  it('uses the exact signed conversion helper, never floating point', () => {
    expect(migration).toMatch(/public\.fx_convert_exact\(/);
    expect(migration).not.toMatch(/::float|::double precision/i);
  });

  it('carries the full fx_status ladder', () => {
    for (const status of [
      'NO_REPORTING_CURRENCY',
      'SAME_CURRENCY',
      'NO_RATE_SNAPSHOT',
      'CONVERTED_AT_RATE',
    ]) {
      expect(migration).toContain(status);
      expect(FX_STATUS_LABEL[status]).toBeTruthy();
    }
  });

  it('refuses a partial converted total rather than under-reporting', () => {
    const guards = migration.match(/count\(\*\) filter \(where pc\.converted_\w+ is null\) > 0 then null/g) ?? [];
    expect(guards).toHaveLength(4);
  });

  it('is driven off the project register, not the finance spine', () => {
    // project_financial_position_read excludes projects with no financial
    // activity; an inner join would silently drop a real project and its
    // assets from its own sector total.
    expect(migration).toMatch(
      /left join public\.project_financial_position_read pp on pp\.project_id = p\.id/,
    );
    expect(migration).not.toMatch(
      /\n\s*join public\.project_financial_position_read/,
    );
  });

  it('never writes a ledger entry — it is reporting only', () => {
    expect(migration).not.toMatch(/journal_lines|journal_batches/);
  });
});

describe('R8 database gate proves the behaviour, not just the shape', () => {
  it('asserts conservation of both assets and projects', () => {
    expect(gate).toContain('register must conserve assets exactly');
    expect(gate).toContain('sector performance must conserve projects');
    expect(gate).toContain('sector asset counts must reconcile to the register');
  });

  it('asserts an absent figure carries no amount and no currency', () => {
    expect(gate).toContain('an absent acquisition cost must carry no amount and no currency');
    expect(gate).toContain('an absent valuation must carry no amount, currency or date');
    expect(gate).toContain('an absent realized result must carry no amount and no currency');
  });

  it('asserts the converse — a figure is always explained by a status', () => {
    expect(gate).toContain('a reported amount must always be explained by a matching status');
    expect(gate).toContain('every register amount must carry its own currency');
  });

  it('proves tenancy as a real authenticated caller, not as superuser', () => {
    // RLS is bypassed for the owning superuser, so a tenancy assertion made
    // as postgres would prove nothing.
    expect(gate).toMatch(/set_config\('role', 'authenticated', false\)/);
    expect(gate).toContain('the register must not leak assets across organizations');
    expect(gate).toContain('sector performance must not leak across organizations');
  });

  it('proves a proposed valuation never reaches the register', () => {
    expect(gate).toContain('a proposed (unapproved) valuation must never reach the register');
  });

  it('proves a missing FX snapshot yields null rather than zero', () => {
    expect(gate).toContain('a missing FX snapshot must yield NULL, never a guessed converted total');
    expect(gate).toContain('fx_status must be uniform within every (organization, sector, currency) group');
  });

  it('forbids a universal asset base table from ever appearing', () => {
    expect(gate).toContain('a universal asset base table is not authorized');
  });
});

describe('R8 labels keep the honesty distinction in Arabic', () => {
  it('labels every asset kind and sector', () => {
    for (const kind of [
      'PROPERTY_ASSET',
      'AGRICULTURAL_LAND_ASSET',
      'FARM',
      'LIVESTOCK_SITE',
    ]) {
      expect(ASSET_KIND_LABEL[kind]).toBeTruthy();
    }
    for (const sector of ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK']) {
      expect(SECTOR_LABEL[sector]).toBeTruthy();
    }
  });

  it('keeps each sector vocabulary distinct rather than flattening it', () => {
    // Real-estate strategies and agricultural control bases share one
    // column but must not share one meaning.
    expect(ASSET_CLASSIFICATION_LABEL.DEVELOP_SELL).not.toBe(
      ASSET_CLASSIFICATION_LABEL.CONTRIBUTED_IN_KIND,
    );
    expect(ASSET_CLASSIFICATION_LABEL.PURCHASED).toBeTruthy();
    expect(ASSET_STATE_LABEL.DISPOSED).toBeTruthy();
  });

  it('classifies absence reasons apart from presence bases', () => {
    expect(isAbsence('NOT_RECORDED')).toBe(true);
    expect(isAbsence('NO_APPROVED_VALUATION')).toBe(true);
    expect(isAbsence('APPROVED_VALUATION')).toBe(false);
    expect(isAbsence('REALIZED_ON_RECOGNIZED_SALE')).toBe(false);
  });

  it('falls back to the raw token instead of a silent blank', () => {
    expect(statusLabel('SOME_FUTURE_STATUS')).toBe('SOME_FUTURE_STATUS');
    expect(statusLabel('NOT_RECORDED')).toBe(ABSENCE_REASON_LABEL.NOT_RECORDED);
    expect(statusLabel('APPROVED_VALUATION')).toBe(BASIS_LABEL.APPROVED_VALUATION);
  });

  it('translates every status the migration can emit', () => {
    const emitted = [
      'NOT_RECORDED',
      'NOT_APPLICABLE_NO_ACQUISITION_FACT',
      'NOT_MODELLED_FOR_THIS_ASSET_KIND',
      'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY',
      'NO_APPROVED_VALUATION',
      'NO_RECOGNIZED_SALE',
      'CONTRACTED_CONSIDERATION_AND_CLOSING_COSTS',
      'AGREED_CONSIDERATION',
      'APPROVED_VALUATION',
      'REALIZED_ON_RECOGNIZED_SALE',
      'PROPERTY_STATE_HISTORY',
    ];
    for (const status of emitted) {
      expect(migration).toContain(status);
      expect(statusLabel(status)).not.toBe(status);
    }
  });
});

describe('R8 page renders reasons, not fabricated zeros', () => {
  it('routes money through the exact formatter only', () => {
    expect(page).toMatch(/formatMinorUnits/);
    expect(page).not.toMatch(/Number\(|parseFloat|parseInt|toFixed/);
  });

  it('shows the absence reason instead of an amount when there is no fact', () => {
    expect(page).toMatch(/isAbsence\(status\)/);
    expect(page).toMatch(/statusLabel\(status\)/);
  });

  it('explains a withheld converted total rather than printing zero', () => {
    expect(page).toContain('لا نعرض مبلغًا محوّلًا');
  });

  it('states plainly that the page owns nothing and writes nothing', () => {
    expect(page).toContain('للقراءة فقط');
    expect(page).not.toMatch(/<form|action=\{/);
  });

  it('offers honest empty states for both sections', () => {
    expect(page).toContain('لا توجد أصول مُسجَّلة بعد');
    expect(page).toContain('لا توجد قطاعات لعرضها بعد');
  });

  it('is force-dynamic so figures are never served stale', () => {
    expect(page).toMatch(/export const dynamic = 'force-dynamic'/);
  });

  it('is reachable from the main navigation', () => {
    // Primary navigation lives in the shared AppNav rendered by the app layout.
    const nav = readFileSync('src/shared/ui/app-nav.tsx', 'utf8');
    expect(layout).toContain('<AppNav');
    expect(nav).toMatch(/href: '\/assets', label: 'الأصول'/);
  });
});

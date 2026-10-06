import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

/**
 * Every single-row financial read must be justified by the database, not by
 * hope.
 *
 * `.maybeSingle()` tells PostgREST "there is at most one row and I want it as an
 * object". When the underlying relation can legitimately return more than one
 * row, PostgREST answers `406 PGRST116` instead of returning data, so the page
 * shows nothing at all. That is how the project position summary failed on any
 * multi-currency project, and how the membership lookup would have failed on any
 * organization with more than one member.
 *
 * Each assertion below pins one of the two things that make a singleton valid:
 *   * the reader filters on a key the database has declared UNIQUE, or
 *   * the reader explicitly partitions a multi-row relation into rows.
 *
 * The comments record WHERE the uniqueness comes from, so a reader cannot
 * inherit this file's blessing without the corresponding constraint existing.
 */

function source(path: string): string {
  return readFileSync(path, 'utf8');
}

const finance = source('src/features/finance/queries.ts');
const control = source('src/features/control/queries.ts');
const allocation = source('src/features/allocation/queries.ts');
const intake = source('src/features/intake/queries.ts');
const pilot = source('src/features/pilot/queries.ts');
const realEstate = source('src/features/real-estate/queries.ts');
const funding = source('src/features/funding/queries.ts');
const portfolios = source('src/features/portfolios/queries.ts');
const projects = source('src/features/projects/queries.ts');

describe('financial readers whose relation is multi-row are partitioned, not singleton', () => {
  it('project position is a genuine singleton, and says why', () => {
    // `project_financial_position_read` is driven by `investment_projects p`
    // (primary key) and joins every CTE with
    // `on <cte>.project_id = p.id and <cte>.currency = p.reporting_currency`, so
    // filtering by project_id yields exactly one row. The singleton is correct
    // and is deliberately NOT an array.
    expect(control).toMatch(/export async function getProjectPosition\(projectId: string\): Promise<ProjectPosition \| null>/);
    expect(control).toMatch(/from\('project_financial_position_read'\)[\s\S]{0,200}maybeSingle\(\)/);
    // The reader must keep disclosing that the view is reporting-currency
    // scoped and silently excludes other-currency facts.
    expect(control).toMatch(/REPORTING-CURRENCY SLICE/);
  });

  it('distribution capacity returns one row per project+currency', () => {
    // `s5_distribution_capacity_read` groups journal lines by
    // (organization_id, project_id, currency).
    expect(allocation).toMatch(/export async function getDistributionCapacity\(projectId: string\): Promise<DistributionCapacity\[\]>/);
    expect(allocation).not.toMatch(/s5_distribution_capacity_read'\)[\s\S]{0,300}maybeSingle/);
  });

  it('membership is filtered to the caller, which is what makes it unique', () => {
    // `memberships` is `unique(organization_id, user_id)`. The RLS policy
    // `membership_read` is `is_active_member(organization_id)`, so without the
    // user filter the query returns EVERY active member of the organization.
    expect(finance).toMatch(
      /from\('memberships'\)[\s\S]{0,400}\.eq\('user_id', user\.id\)[\s\S]{0,120}maybeSingle\(\)/,
    );
    // The collection reader for the same table must stay a collection.
    expect(portfolios).toMatch(/getOrganizationMembers[\s\S]{0,400}return \(data \?\? \[\]\)/);
  });
});

describe('singleton financial readers are backed by a declared unique key', () => {
  it('the project reader keys on the primary key', () => {
    expect(projects).toMatch(/from\('investment_projects'\)[\s\S]{0,300}\.eq\('id', id\)[\s\S]{0,80}maybeSingle\(\)/);
  });

  it('the portfolio reader keys on the primary key', () => {
    expect(portfolios).toMatch(/from\('investment_portfolios_read'\)[\s\S]{0,200}\.eq\('id', id\)[\s\S]{0,80}maybeSingle\(\)/);
  });

  it('the organization reporting currency reader keys on the primary key', () => {
    expect(control).toMatch(/from\('organizations'\)[\s\S]{0,200}\.eq\('id', organizationId\)[\s\S]{0,80}maybeSingle\(\)/);
  });

  it('the active agreement version reader relies on the partial unique index', () => {
    // `agreement_versions_one_active` is unique(project_id) WHERE status='ACTIVE'.
    expect(funding).toMatch(/from\('agreement_versions'\)[\s\S]{0,300}eq\('status', 'ACTIVE'\)[\s\S]{0,40}maybeSingle\(\)/);
  });

  it('the intake declaration reader relies on unique(project_id)', () => {
    expect(intake).toMatch(/from\('project_intake_declarations_read'\)[\s\S]{0,600}\.eq\('project_id', projectId\)[\s\S]{0,60}maybeSingle\(\)/);
  });

  it('the real-estate profile reader relies on unique(project_id)', () => {
    // The real-estate queries module is written minified, so the separator
    // after the comma is not significant here.
    expect(realEstate).toMatch(/from\('real_estate_project_profiles'\)[\s\S]{0,400}\.eq\('project_id',\s*projectId\)[\s\S]{0,60}maybeSingle\(\)/);
  });

  it('the pilot acceptance report is one row per project by construction', () => {
    // The view selects from `investment_projects p` with scalar subqueries only,
    // so `p.id` (primary key) yields exactly one row.
    expect(pilot).toMatch(/from\('s7_pilot_acceptance_report_read'\)[\s\S]{0,1200}\.eq\('project_id', projectId\)[\s\S]{0,60}maybeSingle\(\)/);
  });
});

describe('no financial reader selects an unpartitioned money column into one row', () => {
  it('no reader calls .single() on a read model', () => {
    for (const [name, text] of Object.entries({
      control,
      allocation,
      intake,
      pilot,
      realEstate,
      funding,
      portfolios,
      projects,
      finance,
    })) {
      // `.single()` is only valid when a missing row is an error. No financial
      // reader in this repository is in that position.
      expect(text, `${name} must not use .single() for a read model`).not.toMatch(/_read'\)[\s\S]{0,400}?\.single\(\)/);
    }
  });
});

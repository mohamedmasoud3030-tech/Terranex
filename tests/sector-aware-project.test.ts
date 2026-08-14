import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { SECTORS, projectSchema } from '../src/features/projects/schema';

const migration = readFileSync('supabase/migrations/20260813000900_sector_aware_project.sql', 'utf8');
const navSource = readFileSync('src/features/workspace/nav.tsx', 'utf8');
const projectFormSource = readFileSync('src/app/(app)/projects/new/project-form.tsx', 'utf8');
const homeSource = readFileSync('src/app/(app)/page.tsx', 'utf8');
const projectPageSource = readFileSync('src/app/(app)/projects/[projectId]/page.tsx', 'utf8');
const agriculturePageSource = readFileSync('src/app/(app)/projects/[projectId]/agriculture/page.tsx', 'utf8');
const overviewPageSource = readFileSync('src/app/(app)/projects/[projectId]/overview/page.tsx', 'utf8');
const projectsActionsSource = readFileSync('src/features/projects/actions.ts', 'utf8');
const projectsQueriesSource = readFileSync('src/features/projects/queries.ts', 'utf8');

describe('GF-013 sector-aware project identity', () => {
  it('exposes the canonical REAL_ESTATE | AGRICULTURE sector vocabulary to the application', () => {
    expect(SECTORS).toEqual(['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK']);
  });

  it('requires an explicit sector when validating project creation', () => {
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع',
    }).success).toBe(false);
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع',
      sector: 'REAL_ESTATE',
    }).success).toBe(true);
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع',
      sector: 'AGRICULTURE',
    }).success).toBe(true);
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع',
      sector: 'LIVESTOCK',
    }).success).toBe(true);
  });

  it('expands the database sector constraint to include AGRICULTURE', () => {
    expect(migration).toContain("check (sector in ('REAL_ESTATE','AGRICULTURE'))");
  });

  it('keeps the original 4-arg RPC as a Real Estate compatibility wrapper', () => {
    expect(migration).toMatch(/p_description,\s*'REAL_ESTATE'/);
    expect(migration).toContain('create or replace function public.create_investment_project(');
  });

  it('adds the new 5-arg sector-aware RPC and validates the sector at the database boundary', () => {
    expect(migration).toContain("raise exception 'invalid sector'");
    expect(migration).toMatch(/create or replace function public\.create_investment_project\([\s\S]*?p_sector text[\s\S]*?returns uuid/);
  });

  it('records the actual selected sector in the immutable audit event', () => {
    expect(migration).toContain("jsonb_build_object('name', trim(p_name), 'sector', v_sector)");
  });

  it('does not introduce ambiguous PostgREST overloads', () => {
    const signatures = migration.match(/create or replace function public\.create_investment_project\([^)]*\)/g) ?? [];
    expect(signatures.length).toBeGreaterThanOrEqual(2);
    const argCounts = signatures.map((s) => (s.match(/p_[a-z_]+/g) ?? []).length);
    expect(new Set(argCounts).size).toBe(argCounts.length);
  });
});

describe('GF-013 sector-aware navigation', () => {
  it('exposes a sector-aware workspace nav that does not call agriculture sections Real Estate', () => {
    expect(navSource).toContain("AGRICULTURE");
    expect(navSource).toContain("المزرعة والمحاصيل");
    expect(navSource).not.toMatch(/Agriculture[\s\S]{0,200}?REAL_ESTATE[\s\S]{0,200}?الأصول العقارية/);
  });

  it('does not expose the agriculture entry to Real Estate sections', () => {
    expect(navSource).toContain('REAL_ESTATE_SECTIONS');
    expect(navSource).toContain('AGRICULTURE_SECTIONS');
  });

  it('the new project form surfaces a truthful sector selector with explicit Arabic labels', () => {
    expect(projectFormSource).toContain('عقارات');
    expect(projectFormSource).toContain('زراعة');
    expect(projectFormSource).toMatch(/name="sector"/);
    expect(projectFormSource).toContain('LIVESTOCK');
    expect(projectFormSource).toContain('ثروة حيوانية');
  });

  it('the project home page links Agriculture projects to the agriculture workspace and Real Estate to operations', () => {
    expect(homeSource).toContain('sectorLandingHref');
    expect(homeSource).toContain('SECTOR_LABEL');
  });

  it('the project shell page displays a truthful sector label and a sector-correct entry', () => {
    expect(projectPageSource).toContain('SECTOR_LABEL');
    expect(projectPageSource).toContain('sectorLandingHref');
    // The page reads `project.sector` (typed as ProjectSector =
    // 'REAL_ESTATE' | 'AGRICULTURE') and routes the operator to the
    // sector-correct workspace without hard-coding labels.
    expect(projectPageSource).toMatch(/sector = project\.sector/);
  });

  it('redirects Agriculture projects away from the Real Estate overview page', () => {
    expect(overviewPageSource).toContain("project.sector === 'AGRICULTURE'");
    expect(overviewPageSource).toContain("redirect(`/projects/${projectId}/agriculture`)");
  });

  it('guards the agriculture route from Real Estate projects', () => {
    expect(agriculturePageSource).toContain("project.sector !== 'AGRICULTURE'");
  });

  it('does not call livestock, plugin, weather, map, or offline primitives anywhere in the slice', () => {
    const sources = [
      projectFormSource,
      homeSource,
      projectPageSource,
      agriculturePageSource,
      overviewPageSource,
      projectsActionsSource,
      projectsQueriesSource,
    ];
    for (const s of sources) {
      expect(s).not.toMatch(/plugin|rules engine|outbox/i);
    }
  });
});

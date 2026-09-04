import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

/**
 * Workspace contract.
 *
 * 1. Business pages share the canonical project chrome; the legacy partner
 *    statement route is intentionally a redirect while R14 policy is open.
 * 2. No synthetic demo financial figure is hard-coded in active financial UI.
 * 3. Synthetic rehearsal data never satisfies real-world evidence gates.
 */

const workspaceNav = readFileSync('src/features/workspace/nav.tsx', 'utf8');

describe('project business workspaces share chrome', () => {
  const pages = [
    'src/app/(app)/projects/[projectId]/overview/page.tsx',
    'src/app/(app)/projects/[projectId]/funding/page.tsx',
    'src/app/(app)/projects/[projectId]/operations/page.tsx',
    'src/app/(app)/projects/[projectId]/costs/page.tsx',
    'src/app/(app)/projects/[projectId]/revenue/page.tsx',
    'src/app/(app)/projects/[projectId]/close/page.tsx',
    'src/app/(app)/projects/[projectId]/pilot/page.tsx',
    'src/app/(app)/projects/[projectId]/controls/page.tsx',
    'src/app/(app)/projects/[projectId]/governance/page.tsx',
  ];
  for (const page of pages) {
    it(`${page} mounts WorkspaceChrome`, () => {
      expect(readFileSync(page, 'utf8')).toMatch(/WorkspaceChrome/);
    });
  }

  it('keeps the legacy statements route policy-blocked instead of mounting economic UI', () => {
    const statements = readFileSync('src/app/(app)/projects/[projectId]/statements/page.tsx', 'utf8');
    expect(statements).toMatch(/redirect\(`\/projects\/\$\{projectId\}\/investors`\)/);
    expect(statements).not.toMatch(/WorkspaceChrome|getPartnerCapitalStatement/);
  });
});

describe('workspace navigation contract', () => {
  it('keeps the nine Real Estate base sections while mapping statements to safe transparency', () => {
    const realEstateBlock = workspaceNav.match(/REAL_ESTATE_SECTIONS[\s\S]*?\]\s*;/);
    expect(realEstateBlock).not.toBeNull();
    const ids = Array.from(realEstateBlock![0].matchAll(/id: '([a-z-]+)'/g), (match) => match[1]);
    expect(ids).toEqual([
      'overview',
      'capital',
      'property',
      'costs-cash',
      'revenue',
      'close',
      'statements',
      'opening',
      'controls',
    ]);
    expect(realEstateBlock![0]).toContain('شفافية المشاركين');
    expect(realEstateBlock![0]).toContain(`/investors`);
    expect(realEstateBlock![0]).not.toContain('كشوف الشركاء');
  });

  it('exposes Agriculture business sections that are not Real Estate ones', () => {
    const agriBlock = workspaceNav.match(/AGRICULTURE_SECTIONS[\s\S]*?\]\s*;/);
    expect(agriBlock).not.toBeNull();
    const ids = Array.from(agriBlock![0].matchAll(/id: '([a-z-]+)'/g), (match) => match[1]);
    expect(ids).toEqual(['agriculture', 'land-assets', 'field-activities', 'field-inputs', 'harvest-inventory', 'agriculture-sales', 'agriculture-results']);
    expect(agriBlock![0]).not.toMatch(/الأصول العقارية/);
  });

  it('includes shared procurement, financial control and governance without sector duplication', () => {
    expect(workspaceNav).toContain("id: 'procurement'");
    expect(workspaceNav).toContain("id: 'budget'");
    expect(workspaceNav).toContain("id: 'integrity'");
    expect(workspaceNav).toContain("id: 'governance'");
  });

  it('does not expose engineering slice names to operators', () => {
    expect(workspaceNav).not.toMatch(/S0|S1|S2|S3|S4|S5|S6|S7/);
    expect(workspaceNav).not.toMatch(/slice|vertical|engineering/);
  });
});

describe('frontend never hard-codes the demo financial truth', () => {
  const demoMinorUnits = [
    '4100000000',
    '750000000',
    '3950000000',
    '150000000',
    '500000000',
  ];
  const pages = [
    'src/app/(app)/projects/[projectId]/page.tsx',
    'src/app/(app)/projects/[projectId]/overview/page.tsx',
    'src/app/(app)/projects/[projectId]/revenue/page.tsx',
    'src/app/(app)/projects/[projectId]/controls/page.tsx',
  ];
  for (const page of pages) {
    const source = readFileSync(page, 'utf8');
    it(`${page} derives figures from canonical read models`, () => {
      // Canonical read-model readers. The per-currency contracts added by the
      // Project Brief slices belong here: they are the authoritative read path,
      // and the older project-grain readers remain for the surfaces that still
      // legitimately consume them.
      expect(source).toMatch(
        /getProjectCapitalPosition|getCashAccountPositions|getRealizedResults|getPilotAcceptanceReport|getProjectCashByCurrency|getProjectCapitalByCurrency|getProjectResultByCurrency/,
      );
    });
    for (const minor of demoMinorUnits) {
      it(`${page} does not embed the demo minor-unit literal ${minor}`, () => {
        expect(source).not.toMatch(new RegExp(`\\b${minor}\\b`));
      });
    }
  }
});

describe('readiness distinguishes technical from real-world evidence', () => {
  const controls = readFileSync('src/app/(app)/projects/[projectId]/controls/page.tsx', 'utf8');
  it('marks the real-world evidence gates as gated and truthful', () => {
    expect(controls).toMatch(/بيانات اصطناعية للمعاينة/);
    expect(controls).toMatch(/لا تُحتسب/);
    expect(controls).toMatch(/أدلة العالم الحقيقي/);
    expect(controls).toMatch(/بيانات مصدر حقيقية/);
  });
  it('labels the synthetic demo banner truthfully on the shell page', () => {
    const shell = readFileSync('src/app/(app)/projects/[projectId]/page.tsx', 'utf8');
    expect(shell).toMatch(/بيانات توضيحية اصطناعية ثابتة/);
    expect(shell).toMatch(/لا تُحتسب كدليل عميل حقيقي/);
  });
  it('does not let rehearsal success imply buyer acceptance', () => {
    expect(controls).toMatch(/human_uat_status === 'ACCEPTED'/);
  });
  it('keeps the controls workspace free of engineering slice names', () => {
    expect(controls).not.toMatch(/S0|S1|S2|S3|S4|S5|S6|S7/);
  });
});

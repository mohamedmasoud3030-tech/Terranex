import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

/**
 * GF-010 workspace contract.
 *
 * 1. The project workspace is organised around nine business sections, not
 *    around internal S0–S7 engineering slices.
 * 2. No synthetic demo financial figure is ever hard-coded in the frontend:
 *    every displayed number must come from a canonical read model / RPC.
 * 3. The permanent demo (DEMO-RE-2026-001) must never satisfy the real-world
 *    evidence gates on its own (synthetic rehearsal data is not evidence).
 */

const workspaceNav = readFileSync('src/features/workspace/nav.tsx', 'utf8');

describe('GF-011 nine workspace sections share chrome', () => {
  const pages = [
    'src/app/(app)/projects/[projectId]/overview/page.tsx',
    'src/app/(app)/projects/[projectId]/funding/page.tsx',
    'src/app/(app)/projects/[projectId]/operations/page.tsx',
    'src/app/(app)/projects/[projectId]/costs/page.tsx',
    'src/app/(app)/projects/[projectId]/revenue/page.tsx',
    'src/app/(app)/projects/[projectId]/close/page.tsx',
    'src/app/(app)/projects/[projectId]/statements/page.tsx',
    'src/app/(app)/projects/[projectId]/pilot/page.tsx',
    'src/app/(app)/projects/[projectId]/controls/page.tsx',
  ];
  for (const page of pages) {
    it(`${page} mounts WorkspaceChrome`, () => {
      expect(readFileSync(page, 'utf8')).toMatch(/WorkspaceChrome/);
    });
  }
});

describe('GF-010 workspace navigation contract', () => {
  it('exposes exactly the nine business sections', () => {
    const ids = Array.from(
      workspaceNav.matchAll(/id: '([a-z-]+)'/g),
      (match) => match[1],
    );
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
  });

  it('does not expose engineering slice names to operators', () => {
    expect(workspaceNav).not.toMatch(/S0|S1|S2|S3|S4|S5|S6|S7/);
    expect(workspaceNav).not.toMatch(/slice|vertical|engineering/);
  });
});

describe('GF-010 frontend never hard-codes the demo financial truth', () => {
  const demoMinorUnits = [
    '4100000000', // EGP 41,000,000 cash
    '750000000', // EGP 7,500,000 realized result
    '3950000000', // EGP 39,500,000 partner capital
    '150000000', // EGP 1,500,000 supplier payable
    '500000000', // EGP 5,000,000 opening import
  ];
  const pages = [
    'src/app/(app)/projects/[projectId]/page.tsx',
    'src/app/(app)/projects/[projectId]/overview/page.tsx',
    'src/app/(app)/projects/[projectId]/revenue/page.tsx',
    'src/app/(app)/projects/[projectId]/statements/page.tsx',
    'src/app/(app)/projects/[projectId]/controls/page.tsx',
  ];
  for (const page of pages) {
    const source = readFileSync(page, 'utf8');
    it(`${page} derives figures from canonical read models`, () => {
      expect(source).toMatch(/getProjectCapitalPosition|getCashAccountPositions|getRealizedResults|getPartnerCapitalStatement|getPilotAcceptanceReport/);
    });
    for (const minor of demoMinorUnits) {
      it(`${page} does not embed the demo minor-unit literal ${minor}`, () => {
        expect(source).not.toMatch(new RegExp(`\\b${minor}\\b`));
      });
    }
  }
});

describe('GF-010 readiness distinguishes technical from real-world evidence', () => {
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
    // UAT acceptance derives only from documented human acceptance.
    expect(controls).toMatch(/human_uat_status === 'ACCEPTED'/);
  });
  it('keeps the controls workspace free of engineering slice names', () => {
    expect(controls).not.toMatch(/S0|S1|S2|S3|S4|S5|S6|S7/);
  });
});

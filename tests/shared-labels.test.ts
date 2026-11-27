import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { SECTOR_LABEL as SECTOR_FROM_AGRICULTURE } from '@/features/agriculture/labels';
import { SECTOR_LABEL as SECTOR_FROM_ASSETS } from '@/features/assets/labels';
import { SECTOR_LABEL as SECTOR_FROM_PROJECTS } from '@/features/projects/labels';
import {
  COST_TREATMENT_LABEL,
  DISPOSITION_STATUS_LABEL,
  SECTOR_LABEL,
  UAT_STATUS_LABEL,
} from '@/shared/labels';

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) yield* walk(full);
    else if (/\.(ts|tsx)$/.test(entry)) yield full;
  }
}

describe('shared labels', () => {
  it('keeps the sector vocabulary identical across every importing surface', () => {
    expect(SECTOR_LABEL).toEqual({
      REAL_ESTATE: 'عقارات',
      AGRICULTURE: 'زراعة',
      LIVESTOCK: 'ثروة حيوانية',
    });
    expect(SECTOR_FROM_AGRICULTURE).toBe(SECTOR_LABEL);
    expect(SECTOR_FROM_ASSETS).toBe(SECTOR_LABEL);
    expect(SECTOR_FROM_PROJECTS).toBe(SECTOR_LABEL);
  });

  it('covers the consolidated lifecycles', () => {
    expect(Object.keys(UAT_STATUS_LABEL)).toEqual(
      expect.arrayContaining(['NOT_STARTED', 'PENDING', 'ACCEPTED', 'REJECTED']),
    );
    expect(Object.keys(DISPOSITION_STATUS_LABEL)).toEqual(
      expect.arrayContaining(['DRAFT', 'APPROVED', 'CONTROL_TRANSFERRED']),
    );
    expect(Object.keys(COST_TREATMENT_LABEL)).toEqual(
      expect.arrayContaining(['EXPENSE', 'CAPITALIZABLE_WIP']),
    );
  });

  it('defines the sector wording in exactly one module', () => {
    const defining = [...walk('src')].filter((file) =>
      readFileSync(file, 'utf8').includes("REAL_ESTATE: 'عقارات'"),
    );
    expect(defining).toEqual(['src/shared/labels.ts']);
  });

  it('leaves no local copies of the consolidated maps in the pages that used to own them', () => {
    const forbidden: Array<[string, string]> = [
      ['src/app/(app)/projects/[projectId]/controls/page.tsx', 'const UAT_AR'],
      ['src/app/(app)/projects/[projectId]/pilot/page.tsx', 'const HUMAN_UAT_AR'],
      ['src/app/(app)/projects/[projectId]/revenue/page.tsx', 'const DISPOSITION_STATUS'],
      ['src/app/(app)/projects/[projectId]/operations/page.tsx', 'const DISPOSITION_STATUS'],
      ['src/app/(app)/projects/[projectId]/operations/page.tsx', 'const STRATEGY'],
      ['src/app/(app)/projects/[projectId]/costs/page.tsx', 'const TREATMENT_LABEL'],
      ['src/app/(app)/projects/[projectId]/budget/forms.tsx', 'const TREATMENT_LABEL'],
      ['src/app/(app)/projects/new/project-form.tsx', 'const SECTOR_LABEL'],
    ];
    for (const [file, marker] of forbidden) {
      expect(readFileSync(file, 'utf8'), `${file} still defines ${marker}`).not.toContain(marker);
    }
  });
});

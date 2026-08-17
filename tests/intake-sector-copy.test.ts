import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const intakeStart = readFileSync('src/app/(app)/intake/page.tsx', 'utf8');
const intakeReadiness = readFileSync('src/features/intake/readiness.ts', 'utf8');

describe('intake start page copy is sector-honest', () => {
  it('describes the three supported sectors instead of a real-estate-only narrative', () => {
    expect(intakeStart).toContain('عقارات، زراعة، ثروة حيوانية');
    expect(intakeStart).not.toContain('القطاع الأول: عقاري');
    expect(intakeStart).not.toContain('مشروعًا عقاريًا واحدًا');
  });

  it('labels project cards with their sector', () => {
    expect(intakeStart).toContain('SECTOR_LABEL[project.sector]');
  });
});

describe('intake readiness keeps sector guards', () => {
  it('gates property sections behind the real-estate sector check', () => {
    expect(intakeReadiness).toContain("snapshot.sector !== 'AGRICULTURE' && snapshot.sector !== 'LIVESTOCK'");
  });

  it('omits empty sector groups from the readiness navigation', () => {
    expect(intakeReadiness).toContain("if (members.length === 0) return [];");
  });
});

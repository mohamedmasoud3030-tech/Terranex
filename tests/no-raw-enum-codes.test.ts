import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';

/**
 * No raw schema codes rendered as JSX text.
 *
 * The design pass found seven screens printing PENDING, OWNER, SUPERSEDED and
 * DRAFT verbatim into an Arabic interface. recordStatusLabel() and roleLabel()
 * now cover the CHECK-permitted values, and this guard keeps them covered: a
 * text node that is exactly a schema code is a defect, whatever route renders
 * it.
 *
 * The match is deliberately narrow — a text node whose entire content is one
 * code. Codes inside prose ("أنشئ فترة OPEN") are a copy judgement and once
 * drove two real fixes, but guarding free prose against English words would
 * make the test uninforcable; the full-node form is the regression that
 * actually recurs.
 */

/** Every value the labels module can translate — see src/features/projects/labels.ts. */
const CODES = [
  // PROJECT_LIFECYCLE_LABEL
  'DRAFT',
  'FUNDING',
  // SECTOR_LABEL
  'REAL_ESTATE',
  'AGRICULTURE',
  'LIVESTOCK',
  // SEVERITY_LABEL
  'CRITICAL',
  'WARNING',
  'INFO',
  // RECORD_STATUS_LABEL
  'OPEN',
  'RESOLVED',
  'REQUESTED',
  'APPROVED',
  'REJECTED',
  'EXECUTED',
  'VOID',
  'PENDING',
  'ACTIVE',
  'INACTIVE',
  'POSTED',
  'REVERSED',
  'PASSED',
  'FAILED',
  'EXPIRED',
  'SUPERSEDED',
  'PREPARED',
  'VALIDATED',
  'READY_FOR_APPROVAL',
  // ROLE_LABEL
  'OWNER',
  'MEMBER',
];

const files = execSync("find src -name '*.tsx'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

describe('raw enum codes never render as text', () => {
  it('no JSX text node is exactly a schema code', () => {
    const offenders: string[] = [];
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      for (const m of source.matchAll(/>\s*([A-Z][A-Z_0-9]{2,})\s*</g)) {
        if (CODES.includes(m[1])) offenders.push(`${file}: ${m[1]}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('the guard list stays in step with the labels module', () => {
    // A key added to a labels map without being added here would silently
    // narrow the guard. Every map key in labels.ts must be a guarded code.
    const labels = readFileSync('src/features/projects/labels.ts', 'utf8');
    const keys = [...labels.matchAll(/^\s{2}([A-Z][A-Z_0-9]{2,}):/gm)].map((m) => m[1]);
    expect(keys.length).toBeGreaterThanOrEqual(20);
    for (const key of keys) {
      expect(CODES).toContain(key);
    }
  });
});

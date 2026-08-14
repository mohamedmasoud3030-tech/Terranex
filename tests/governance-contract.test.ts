import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');

describe('GF-012 canonical governance contract', () => {
  it('makes main the only active delivery branch in agent policy', () => {
    const policy = read('AGENTS.md');
    expect(policy).toMatch(/Canonical for `main`/);
    expect(policy).toMatch(/exact current `origin\/main`/);
    expect(policy).not.toMatch(/exact current `origin\/greenfield\/foundation`/);
  });

  it('runs the full Greenfield CI on pull requests and pushes to main', () => {
    const workflow = read('.github/workflows/greenfield-ci.yml');
    expect(workflow).toMatch(/pull_request:\n\s+branches:\n\s+- main/);
    expect(workflow).toMatch(/push:\n\s+branches:\n\s+- main/);
    expect(workflow).toMatch(/workflow_dispatch:/);
    expect(workflow).not.toMatch(/- greenfield\/foundation/);
  });

  it('records the explicit sector sequence without fabricating validation', () => {
    const charter = read('docs/greenfield/01_PRODUCT_CHARTER_AND_MARKET.md');
    const decision = read('docs/decisions/0012_SECTOR_EXPANSION_SEQUENCE.md');
    expect(charter).toMatch(/P-007/);
    expect(decision).toMatch(/Real Estate first, Agriculture second, Livestock third/);
    expect(decision).toMatch(/never count as customer acceptance/);
  });

  it('sets the next bounded batch to the Agriculture foundation', () => {
    const roadmap = read('docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md');
    const execution = read('GREENFIELD_EXECUTION.md');
    expect(roadmap).toMatch(/GF-013 — Agriculture Sector Foundation/);
    expect(roadmap).toMatch(/Farm → Field → CropCycle/);
    expect(execution).toMatch(/GF-013 — Agriculture Sector Foundation/);
  });

  it('states the Agriculture delivery state truthfully across canonical docs', () => {
    const policy = read('AGENTS.md');
    const roadmap = read('docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md');
    const execution = read('GREENFIELD_EXECUTION.md');

    // GF-014 is merged, not upcoming; GF-015 is the active slice.
    expect(policy).toMatch(/GF-014 Field Activity are merged and technically complete/);
    expect(policy).toMatch(/GF-015 Field Input Application is the active bounded Agriculture slice/);
    expect(policy).not.toMatch(/Agriculture is next\b/);
    expect(execution).toMatch(/GF-014 — Field Activity Foundation\n\nStatus: \*\*MERGED — TECHNICALLY COMPLETE\*\*/);
    expect(execution).toMatch(/GF-015 — Field Input Application Foundation/);
    expect(execution).not.toMatch(/`GF-015 — next bounded Agriculture slice`/);
    expect(roadmap).toMatch(/Execute `GF-015 — Field Input Application Foundation`/);
    expect(roadmap).toMatch(/Previous batch \(complete and merged on `main`\): `GF-014/);
  });

  it('keeps the deferred Agriculture scope honest after GF-015', () => {
    const execution = read('GREENFIELD_EXECUTION.md');
    const roadmap = read('docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md');
    // Inputs are delivered, so they must no longer be listed as deferred.
    expect(execution).toMatch(/deferred after GF-015/);
    expect(execution).not.toMatch(/deferred after GF-014: `InputItem`/);
    // Harvest and inventory remain deferred and GF-016 is named, not built.
    expect(execution).toMatch(/`HarvestEvent`, `HarvestLot`/);
    expect(execution).toMatch(/GF-016 — Harvest Event & Harvest Lot Foundation/);
    expect(roadmap).toMatch(/must not be started inside GF-015/);
  });

  it('keeps implementation, deployment, and customer evidence separate', () => {
    const execution = read('GREENFIELD_EXECUTION.md');
    const readme = read('README.md');
    expect(execution).toMatch(/LATEST PRODUCTION ALIAS VERIFICATION PENDING/);
    expect(execution).toMatch(/real-customer validation, buyer UAT, and commercial Phase 2\/3 evidence: not started\/not passed/);
    expect(readme).toMatch(/synthetic demo is never customer evidence/);
  });
});

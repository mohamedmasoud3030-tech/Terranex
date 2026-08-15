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

  it('sets the remaining Agriculture phases in their authorized order', () => {
    const roadmap = read('docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md');
    const execution = read('GREENFIELD_EXECUTION.md');
    expect(roadmap).toMatch(/GF-017 — Agricultural Land Asset, Acquisition & Control \(merged\)/);
    expect(roadmap).toMatch(/GF-018 — Agriculture Sale, Dispatch & Revenue \(merged\)/);
    expect(roadmap).toMatch(/GF-019 — Agriculture Profitability, Cycle Closeout & Technical Gate/);
    expect(execution).toMatch(/GF-013 — Agriculture Sector Foundation/);
    expect(execution).toMatch(/Livestock \(GF-020–GF-024/);
    expect(execution).toMatch(/GF-020 →\nGF-024 Livestock\) is \*\*closed\*\*/);
  });

  it('states the Agriculture delivery state truthfully across canonical docs', () => {
    const policy = read('AGENTS.md');
    const roadmap = read('docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md');
    const execution = read('GREENFIELD_EXECUTION.md');

    // Real Estate, Agriculture, and Livestock are all technically implemented;
    // R0 is merged and the active roadmap is R0–R17 with the hard stop at R13.
    expect(policy).toMatch(/Agriculture \(GF-013 through GF-019\), and Livestock \(GF-020 through GF-024\) are technically implemented/);
    expect(policy).toMatch(/R0 — Canonical Portfolio Realignment & Anti-Hallucination Governance — is \*\*merged\*\*/);
    expect(policy).toMatch(/hard stop at R13/);
    expect(policy).not.toMatch(/Agriculture is next\b/);
    expect(execution).toMatch(/GF-014 — Field Activity Foundation\n\nStatus: \*\*MERGED — TECHNICALLY COMPLETE\*\*/);
    expect(execution).toMatch(/GF-015 — Field Input Application Foundation\n\nStatus: \*\*MERGED — TECHNICALLY COMPLETE\*\*/);
    expect(execution).toMatch(/GF-016 — Harvest & Inventory Flow Foundation\n\nStatus: \*\*MERGED — TECHNICALLY COMPLETE\*\*/);
    expect(execution).toMatch(/GF-017 — Agricultural Land Asset, Acquisition & Control\n\nStatus: \*\*MERGED — TECHNICALLY COMPLETE\*\*/);
    expect(execution).toMatch(/GF-018 — Agriculture Sale, Dispatch & Revenue\n\nStatus: \*\*MERGED — TECHNICALLY COMPLETE\*\*/);
    expect(execution).toMatch(/GF-019 — Agriculture Profitability, Cycle Closeout & Technical Gate\n\nStatus: \*\*TECHNICALLY IMPLEMENTED\*\*/);
    expect(roadmap).toMatch(/GF-018 — Agriculture Sale, Dispatch & Revenue \(merged\)/);
    expect(roadmap).toMatch(/GF-013 through GF-019 are technically implemented/);
  });

  it('keeps the deferred Agriculture scope honest during GF-019', () => {
    const execution = read('GREENFIELD_EXECUTION.md');
    const roadmap = read('docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md');
    // Result/closeout is delivered in GF-019, while input stock remains explicitly deferred.
    expect(execution).toMatch(/deferred beyond GF-019/);
    expect(execution).not.toMatch(/deferred after GF-015: `HarvestEvent`/);
    expect(execution).not.toMatch(/deferred after GF-014: `InputItem`/);
    expect(execution).toMatch(/input-stock receiving\/balance/);
    // Land, sale/revenue, and final profitability/closeout are separate phases.
    expect(execution).toMatch(/GF-017 — Agricultural Land Asset, Acquisition & Control/);
    expect(execution).toMatch(/GF-018 — Agriculture Sale, Dispatch & Revenue/);
    expect(execution).toMatch(/GF-019 — Agriculture Profitability, Cycle Closeout & Technical Gate/);
    expect(roadmap).toMatch(/three independently reviewed major phases/);
  });

  it('keeps implementation, deployment, and customer evidence separate', () => {
    const execution = read('GREENFIELD_EXECUTION.md');
    const readme = read('README.md');
    expect(execution).toMatch(/LATEST PRODUCTION ALIAS VERIFICATION PENDING/);
    expect(execution).toMatch(/real-customer validation, buyer UAT, and commercial Phase 2\/3 evidence: not started\/not passed/);
    expect(readme).toMatch(/synthetic demo is never customer evidence/);
  });
});

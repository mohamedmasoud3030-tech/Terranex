---
name: terranex-implementation
description: Use when implementing or fixing Terranex runtime code, tests, migrations, dependencies, or framework integrations. Do not use for planning-only, architecture-only, code-review-only, threat-model-only, or documentation-only work.
---

# Terranex Implementation

Implement bounded Terranex changes using repository evidence, official technical sources, and proof-first verification.

## Non-negotiable precedence

1. AGENTS.md and canonical Terranex decisions govern product behavior.
2. Current code, migrations, and tests prove what the system does today.
3. Official external documentation governs version-specific framework mechanics.
4. Memory and generic patterns are not authority.

External documentation can validate how Next.js, React, Supabase, PostgreSQL, Vitest, Zod, or TypeScript work. It cannot authorize Terranex business policy.

## Workflow

### 1. Establish a clean scope

- Read AGENTS.md and the relevant canonical decision(s).
- Inspect the complete requested surface before editing.
- Search for the canonical existing implementation before creating anything.
- Identify unrelated work and preserve it.
- State any OPEN business decision that blocks part of the scope.

### 2. Detect the exact stack

Read package.json and relevant configuration. Do not assume a framework or library that is not present.

For volatile framework behavior, follow references/source-policy.md before choosing an API or pattern.

### 3. Prove the requirement

For a bug:
1. Add a test or database gate that reproduces the defect.
2. Confirm the proof fails against the defective behavior when feasible.
3. Implement the smallest correction.
4. Confirm the same proof passes.

For a new behavior:
- establish the contract or invariant in a test/gate before or alongside implementation;
- prefer observable behavior over implementation-detail assertions;
- use a negative control when it materially proves a dangerous old behavior.

Do not force ceremonial TDD where the repository cannot truthfully execute the pre-change state; document the limitation and still add regression evidence.

### 4. Implement the bounded slice

Follow current Terranex conventions:
- one deployable application and one canonical data/authorization path unless an approved ADR says otherwise;
- feature ownership before generic shared abstractions;
- no duplicate finance, authorization, identity, status, formatting, or UI cores;
- no floating-point money;
- no cross-currency arithmetic without an explicit approved FX contract;
- no browser-authoritative financial or approval state;
- no invented investor economics;
- forward-only database migrations;
- default-deny tenant isolation for tenant-owned data.

Keep code, schema, tests, and UI changes only if the slice actually uses them.

### 5. Verify continuously

Run the smallest relevant test while editing, then complete the changed-layer gate before delivery. Use references/verification-matrix.md.

Never report a gate as passed unless it ran against the delivered commit/environment.

### 6. Inspect and clean the diff

Before delivery:
- inspect the complete diff;
- remove temporary files, obsolete experiments, superseded tests, dead compatibility paths, unused code, and duplicate contracts introduced by the task;
- keep a legacy path only when a current consumer or migration/recovery requirement proves it is still needed;
- ensure no secrets or customer data were added.

Do not leave "temporary" fallback logic with no removal owner.

### 7. Handoff

Report:
- canonical authority used;
- external official sources used for volatile mechanics;
- changed behavior;
- proof added;
- commands/gates run;
- known residual risk;
- unresolved business dependencies;
- intentionally excluded scope.

## Exit criteria

Implementation is complete only when the requested outcome exists, proof is committed, relevant verification passes, the diff is bounded and clean, no duplicate implementation remains, and unresolved decisions are explicit.

---
name: terranex-architecture-decision
description: Use when a Terranex task requires an ADR, system-design evaluation, technology choice, data-model boundary, API boundary, or a material architecture trade-off. Do not use for routine implementation when the governing architecture is already settled.
---

# Terranex Architecture Decision

Use this skill to make one evidence-backed architecture decision without reopening settled project boundaries.

## Authority order

1. Read AGENTS.md completely.
2. Read the canonical Terranex documents relevant to the decision.
3. Read existing ADRs that touch the same boundary.
4. Inspect the current implementation and tests to understand what exists.
5. For volatile technology behavior, verify the exact installed version against official documentation.
6. Treat external architecture patterns as evidence, never as Terranex business authority.

If a proposal conflicts with an explicit canonical decision, do not silently override it. Record the conflict and either reject the proposal or create a replacement ADR only when the user has authorized reopening that decision.

## Workflow

### 1. Frame the decision

State:
- the decision to make;
- why it is material now;
- in-scope and out-of-scope behavior;
- hard constraints from canonical Terranex sources;
- unresolved business decisions that could block only part of the scope.

Separate implementation facts from product/business rules.

### 2. Gather evidence

Search before designing. Identify:
- current components and data ownership;
- existing primitives that would be duplicated by the proposal;
- security and tenant-isolation boundaries;
- money, currency, accounting, audit, or lifecycle invariants;
- operational constraints and migration costs;
- version-specific framework constraints from official sources.

Do not invent scale, traffic, legal structure, investor economics, or compliance requirements.

### 3. Evaluate real options

Compare the smallest viable set of options, including "keep the current design" when credible.

Evaluate:
- correctness and domain fit;
- simplicity and reversibility;
- tenant isolation and security;
- data integrity and migration risk;
- operability and observability;
- testability;
- coupling and future lock-in;
- cost of introducing a second implementation of an existing concern.

Prefer the simplest design that satisfies the current bounded slice.

### 4. Decide

Choose one option and state:
- why it wins now;
- what is deliberately not solved;
- consequences and risks;
- explicit triggers that would justify revisiting the decision.

### 5. Record

For a material architecture, accounting, authorization, or scope decision, create or update an ADR using references/adr-template.md.

Never create an ADR merely to restate AGENTS.md or an existing decision.

## Exit criteria

The decision is complete only when:
- canonical authority is cited by repository path;
- current implementation evidence is identified;
- external framework claims are source-verified when relevant;
- trade-offs are explicit;
- no OPEN business decision has been silently converted into a rule;
- duplicate architecture is avoided;
- follow-up implementation can proceed without guessing.

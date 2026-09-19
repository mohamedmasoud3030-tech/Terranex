---
name: terranex-implementation-planning
description: Use when a Terranex feature, bug fix, refactor, migration, dependency change, or infrastructure change needs a deterministic implementation plan before execution or an AI-to-AI handoff. Do not execute the plan while this skill is active.
---

# Terranex Implementation Planning

Create an implementation-ready plan that another agent or engineer can execute without inventing requirements.

## Grounding

Before planning:
1. Read AGENTS.md.
2. Read the canonical documents and ADRs relevant to the requested scope.
3. Inspect the current code, migrations, tests, and commands that own the behavior.
4. Detect the exact installed stack and versions.
5. Verify volatile framework behavior from official sources when the plan depends on it.

Do not plan from memory when the repository can answer the question.

## Planning rules

- Plan one bounded vertical slice at a time.
- Search before creating new modules, tables, money helpers, authorization paths, status models, or UI primitives.
- Preserve the distinction between product/business authority, current implementation facts, and external technical evidence.
- A dashboard or reporting request does not authorize a new ledger or business rule.
- An unresolved business decision blocks only the dependent implementation unit.
- Do not use human-hour estimates. Use dependency ordering and implementation units.
- Do not create speculative abstractions, generic rules engines, placeholder enums, or unused scaffolding.
- Every implementation unit must name its verification evidence and cleanup obligations.
- Plans must distinguish review from fix.

## Workflow

### 1. Define intent

State the user-visible or operator-visible outcome in one paragraph.

### 2. Establish authority and current state

List:
- canonical repository sources;
- existing implementation owners;
- relevant tests and database gates;
- exact external sources required for version-specific behavior;
- unresolved business-decision IDs, if any.

### 3. Define invariants and non-goals

Write the facts that must remain true after implementation. Include tenant isolation, money/currency grain, idempotency, auditability, and lifecycle rules when they are in scope.

### 4. Create implementation units

Use stable IDs such as IU-01, IU-02.

Each unit must include:
- purpose;
- dependencies;
- exact files or bounded locations likely to change;
- behavior or contract to introduce/change;
- migration/data impact;
- tests or gates that prove the unit;
- cleanup/removals required;
- rollback or recovery consideration where applicable.

Prefer units that can be verified independently.

### 5. Define review routing

Identify which review lenses are required by the touched surfaces, such as:
- database/RLS;
- financial semantics;
- authentication/authorization;
- UI/RTL/accessibility;
- migration/upgrade;
- architecture/canonical consistency.

### 6. Define delivery gate

State the exact commands/evidence required before delivery. Use the smallest truthful gates for changed layers and the repository's canonical database runner for database work.

## Output

Use references/plan-template.md.

Return the plan in the conversation unless the user asks for a durable file. If persistence is requested and no project convention exists, use docs/plans/YYYY-MM-DD-short-slug.md.

## Exit criteria

The plan is ready only when another executor can answer all of these without guessing:
- What changes?
- Why is it authorized?
- Where does it change?
- In what order?
- What proves each step?
- What must not change?
- What gets deleted or retired?
- Which risks remain?

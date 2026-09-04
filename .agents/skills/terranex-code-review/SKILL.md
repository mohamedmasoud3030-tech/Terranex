---
name: terranex-code-review
description: Use when reviewing a Terranex diff, branch, commit, or PR, and before delivery of any non-mechanical Terranex change. Report findings first; do not modify code unless the user explicitly asks for a separate fix pass.
---

# Terranex Code Review

Perform a risk-routed review of the actual change. Review and fix are separate stages.

## Operating principles

- Report-only by default.
- Review the diff and its intent before selecting reviewer lenses.
- Use evidence from code, migrations, tests, canonical docs, and official technical sources.
- Prioritize correctness, tenant isolation, financial truth, data integrity, and regressions over style.
- Deduplicate findings before reporting.
- Do not claim an issue without a concrete failure mode and repository evidence.
- Do not accept the author's tests as proof without checking whether they test the dangerous path.

## Workflow

### 1. Resolve scope and intent

Determine:
- base and head of the reviewed change;
- files and database objects touched;
- intended behavior;
- relevant plan/ADR/canonical decision;
- whether the diff contains unrelated churn.

If intent is ambiguous, infer the narrowest intent supported by the change and record the uncertainty.

### 2. Build risk signals

Classify the touched surfaces:
- product/domain semantics;
- money/currency/accounting;
- PostgreSQL/migrations/RLS;
- auth/authorization;
- idempotency/concurrency/audit;
- UI/RTL/accessibility;
- file/storage boundary;
- dependency/framework change;
- architecture/governance.

Use references/reviewer-routing.md to select only relevant reviewer lenses.

If the host supports independent subagents, run disjoint reviewer lenses in parallel. Otherwise execute the same lenses sequentially. Keep their observations separate until synthesis.

### 3. Validate intent and invariants

Check:
- canonical authority actually permits the behavior;
- no OPEN business decision was guessed;
- implementation matches the stated plan/ADR;
- existing canonical helpers/paths were reused;
- data grain and tenant boundary remain correct;
- tests prove the risky paths, not only happy paths.

### 4. Review security-sensitive code with current guidance

For JavaScript/TypeScript web security and Supabase/PostgreSQL security, verify current official guidance when a finding depends on version-specific behavior.

For a change that creates or materially alters a trust boundary, require or recommend the terranex-threat-model skill rather than pretending a code review is a full threat model.

### 5. Synthesize

Merge duplicate findings and classify them using references/findings-format.md.

A finding must include:
- severity;
- confidence;
- evidence location;
- failure mode/consequence;
- recommended correction;
- verification needed;
- owning surface.

### 6. Residual assessment

End with:
- blockers;
- non-blocking findings;
- coverage gaps;
- review lenses executed;
- required gates not observed;
- whether a separate fix pass is warranted.

Do not edit the branch during this stage.

## Exit criteria

The review is complete when every material touched surface received the appropriate lens, findings are evidence-backed and deduplicated, security/database/financial risks are not buried by style feedback, and the report clearly separates confirmed defects from uncertainty.

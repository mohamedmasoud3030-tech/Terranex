# Terranex Review Findings Format

## Severity

- P0 — immediate catastrophic/security/data-integrity risk; must not ship.
- P1 — high-impact correctness, authorization, financial, migration, or reliability defect; block delivery.
- P2 — meaningful defect or missing protection with bounded impact; normally fix before merge unless explicitly accepted.
- P3 — maintainability, test-quality, clarity, or low-risk improvement; advisory unless it masks future correctness risk.

## Confidence

- High — directly demonstrated by code/test/SQL behavior or authoritative documentation.
- Medium — strong evidence but one material assumption remains.
- Low — plausible concern requiring additional evidence. Keep these out of blocker counts unless the missing evidence itself is the problem.

## Finding template

### [P1][High] Short title

**Surface:** database | financial | auth | UI | architecture | test | dependency

**Evidence:** repository path and line/object/function

**Failure mode:** What can actually go wrong.

**Impact:** User/data/security/financial/operational consequence.

**Why current tests do not prevent it:** State the gap, if applicable.

**Recommended correction:** Smallest safe change.

**Verification:** Exact regression proof or gate required.

## Synthesis rules

- Merge findings that share one root cause.
- Keep independent consequences separate only when they require different fixes.
- Do not inflate severity because code looks unfamiliar.
- Do not report pure style unless it creates a real maintenance or correctness risk.
- If a claim depends on framework behavior, verify the installed version and official docs.
- Separate "confirmed defect" from "coverage gap" and from "open question".

## Fix classification

Use one of:
- fix-now — safe, bounded corrective work;
- manual-design — requires an architecture/business/security decision;
- advisory — optional improvement.

Review remains report-only. A later fix pass may consume this classification.

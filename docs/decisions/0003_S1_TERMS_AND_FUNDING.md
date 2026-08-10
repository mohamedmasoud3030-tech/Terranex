# ADR 0003 — S1 Terms & Funding shape

**Status:** Accepted for GF-003
**Date:** 2026-08-10

## Context

S1 must prove the smallest real-estate investment workflow: activate the
governing agreement, call capital, receive contributions, and show an exact
capital position. The Greenfield contracts separate Commitment, Capital Call,
Contribution, Ownership, and ledger balances, and forbid editable balance
columns or ownership inferred from cash.

## Decision

- Parties and project participants are tenant-scoped. S1 introduces only the
  `INVESTOR` participant role; other roles remain an explicit later change.
- One `investment_agreements` envelope per project. Revisions append
  `agreement_versions`; only one version per project may be `ACTIVE`.
- Activated versions and their `commitment_terms` are immutable at the database
  level. A new version supersedes the active one atomically; history is never
  rewritten.
- Commitments use integer `bigint` minor units plus ISO currency. S1 supports a
  single project reporting currency; cross-currency calls/contributions are
  rejected.
- Capital calls have immutable `capital_call_lines`. They may be issued only
  against an `ACTIVE` version and must not exceed a participant's total
  commitment. S1 does not add approval workflows, notices, or cancellation
  accounting beyond the `ISSUED`/`CANCELLED` state.
- Contributions are append-only posted facts. They carry the exact
  `agreement_version_id`, `capital_call_id`, and `participant_id` in force at
  posting. A unique `(organization_id, idempotency_key)` constraint and a
  row-locked over-call check make replay safe and concurrent overpay impossible.
- Project and partner capital positions are read-only views derived from
  commitment terms, issued call lines, and contributions. No stored balance is
  updated by a command.
- Browser clients have `SELECT` only. All material mutations run through
  `SECURITY DEFINER` RPCs that derive the actor, check membership, validate
  inputs, and append audit events.

## Consequences

- S1 proves exact rollforwards without a subledger or double-entry posting
  engine. Cash receipt and contribution are represented as one operational fact;
  balanced journal posting is deferred to the cost/cash slice.
- Ownership interest is deliberately not modeled: contributed cash does not
  imply ownership percentages.
- Replacing the active agreement requires superseding it with a new version;
  later slices can build amendment/revision flows on this append-only chain.

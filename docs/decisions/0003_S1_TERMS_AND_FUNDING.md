# ADR 0003 — S1 Terms & Funding shape

**Status:** Accepted for GF-003  
**Date:** 2026-08-10

## Context

S1 proves the smallest real-estate investment workflow: define the investors and commitments, activate one governing agreement version, issue capital calls, receive contributions, and show an exact capital position. Commitment, Capital Call, Contribution, Ownership, and ledger balances remain separate concepts; no editable balance or cash-implied ownership is allowed.

## Decision

- Parties and project participants are tenant-scoped. S1 introduces only the `INVESTOR` participant role.
- One `investment_agreements` envelope exists per project. `agreement_versions` are append-only economic snapshots.
- S1 activates exactly one governing version. Once activated, that version, its commitments, and the project participant set are frozen. Agreement amendment/supersession is deliberately deferred because it requires explicit carry-forward rules for prior calls and contributions; S1 does not guess those rules.
- Agreement-draft creation, capital-call issuance, and contribution recording use durable idempotency keys. Replaying the same key with the same payload returns the original effect; reusing the key with different economic data is rejected.
- Commitments, call lines, and contributions use PostgreSQL `bigint` integer minor units plus ISO currency. S1 supports only the project reporting currency; FX and cross-currency capital activity are deferred.
- Browser form values are parsed from decimal text to integer minor units without JavaScript floating-point money arithmetic. PostgreSQL read views expose `bigint` money as text so PostgREST/JavaScript cannot round large integers in transit.
- Capital calls may be issued only against the active governing version. Commitment rows are locked before already-called totals are checked, serializing concurrent calls against the same commitment.
- Contributions are append-only posted operational facts carrying the exact `agreement_version_id`, `capital_call_id`, and `participant_id`. The matching call line is row-locked before the remaining-call amount is checked, preventing concurrent overpayment.
- Database scope guards reject same-tenant cross-project participant/version/call combinations even for privileged writers; browser table DML remains denied.
- Project and partner capital positions are read-only projections derived from commitment terms, issued call lines, and contributions. No command updates an editable balance column.
- Material mutations run through locked-search-path `SECURITY DEFINER` RPCs that derive the actor, check membership and project scope, validate inputs, and append audit events.

## Verification contract

GF-003 is not complete from unit tests alone. The database gate must prove:

- fresh migration replay from S0 through S1;
- two-organization isolation and same-tenant cross-project rejection;
- activated agreement and commitment immutability;
- idempotent same-payload retry and mismatched-payload rejection;
- exact capital rollforward;
- browser direct-write denial;
- real concurrent PostgreSQL sessions for both over-call and over-contribution races.

The canonical `npm run db:test` gate executes the SQL suites plus the two-session concurrency suite on real PostgreSQL; CI uses PostgreSQL 16.

## Consequences

- S1 proves funding-control correctness without introducing the project subledger or double-entry engine. Accounting recognition of cash and contribution is added in the Cost & Cash slice rather than fabricated here.
- Ownership interest is deliberately not modeled; contributed cash does not imply ownership percentage or control.
- Amendment/supersession is a future bounded workflow. Until it exists, the first activated agreement remains governing and participant membership cannot be changed underneath it.
- Capital-call cancellation accounting, approvals, notices, documents/signatures, FX, allocation, and distributions remain outside S1.

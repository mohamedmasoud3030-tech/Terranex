# ADR 0009 — S7 Pilot Hardening

**Status:** Implemented · **Date:** 2026-08-13

## Decision

S7 makes the completed S0–S6 Real Estate product operable in a controlled paid pilot. It is a hardening stage, not a feature-expansion stage. It adds the operational capabilities a first real customer requires — a controlled opening position, external reconciliation evidence, durable acceptance records, executable restore proof, access revocation, and operator runbooks — without adding a second sector, a generic importer, a workflow engine, or a second ledger.

Every S7 fact is a database fact. Nothing in S7 accepts an authoritative balance from the browser, and nothing in S7 writes a balance directly.

## 1. Controlled opening import

A pilot cannot start on an empty ledger, and it must not start on a spreadsheet paste. The opening position is a governed, staged artifact with an explicit lifecycle:

`DRAFT → VALIDATED → READY_FOR_APPROVAL → APPROVED → POSTED`, with `REJECTED` and `FAILED` as terminal outcomes.

The import record is organization- and project-scoped and stores the source file name, a SHA-256 file checksum, the schema version `S7.OPENING.V1`, row counts, accepted and rejected counts, declared and computed control totals, both variances, a mapping summary, a rejection summary, actors, timestamps, a content hash, and an immutable approved snapshot hash.

**Real-Estate mappings only.** Six mapping codes exist and the registry is locked by trigger:

| Code | Semantic role | Side | Requires |
| --- | --- | --- | --- |
| `OPENING_BANK_CASH` | `BANK_CASH` | debit | project cash account |
| `OPENING_DEVELOPMENT_WIP` | `DEVELOPMENT_WIP` | debit | — |
| `OPENING_CUSTOMER_RECEIVABLE` | `CUSTOMER_RECEIVABLE` | debit | party |
| `OPENING_SUPPLIER_PAYABLE` | `SUPPLIER_PAYABLE` | credit | party |
| `OPENING_CONTRIBUTED_CAPITAL` | `CONTRIBUTED_CAPITAL` | credit | party |
| `OPENING_DISTRIBUTION_PAYABLE` | `DISTRIBUTION_PAYABLE` | credit | party |

This is deliberately not a universal importer. There is no mapping designer, no arbitrary chart-of-accounts ingestion, and no code that exists only to make the importer look complete. Every code resolves to a role that already exists in the locked eleven-role semantic registry.

**Row-level validation** produces per-row outcomes with one of twelve explicit reasons: `UNKNOWN_MAPPING_CODE`, `PARTY_REQUIRED`, `PARTY_NOT_ALLOWED`, `PARTY_NOT_IN_ORGANIZATION`, `CASH_ACCOUNT_REQUIRED`, `CASH_ACCOUNT_OUT_OF_SCOPE`, `INVALID_AMOUNT`, `BOTH_SIDES_SET`, `NO_AMOUNT`, `SIDE_CONTRADICTS_MAPPING`, `DUPLICATE_ROW_IN_FILE`, `DESCRIPTION_INVALID`. Rejected rows are persisted with their reason and row number; because two rejected rows can legitimately share a content fingerprint, rejected rows are fingerprinted with the row number included.

**Rejected-row atomicity:** a file with any rejected row never posts. Validation is all-or-nothing at the posting boundary; there is no partial import.

**Control totals must reconcile exactly**, to the minor unit, between the declared totals and the sum of accepted rows, and debits must equal credits. There is no plug and no tolerance.

**Maker ≠ approver** is a table CHECK, not application logic. Approval is OWNER-gated, takes an organization-scoped advisory transaction lock keyed on the import, locks the import row `for update`, and replays idempotently only when both the approval idempotency key and the approval request hash (SHA-256 of the import id and posting date) match. Any other repeat is refused with "opening import is already posted".

**No destructive overwrite:** a project holds at most one active posted opening position. Superseding one requires an explicit linked reversal first, and a dedicated reversal guard refuses to reverse an opening batch while any un-reversed, non-reversal batch was posted later in the same project. Dependents are reversed first, in order.

Posting uses the existing canonical journal: balanced `bigint` minor-unit lines against the existing semantic accounts, through the existing period lock. `S7_OPENING_IMPORT` is an additive journal source type. Ordinary posting into a `CLOSED` period remains impossible; corrections use the existing reversal and S6 correction paths.

## 2. Pilot reconciliation checkpoints

A pilot is credible only if the customer can compare Terranex to their own records and get an exact answer.

Nine checkpoint codes are supported: `PROJECT_CASH`, `SUPPLIER_OBLIGATION_POSITION`, `CUSTOMER_RECEIVABLE_POSITION`, `REALIZED_RESULT`, `CONTRIBUTED_CAPITAL`, `PARTNER_CAPITAL`, `DISTRIBUTION_PAYABLE`, `DISTRIBUTION_PAID`, `INVESTOR_STATEMENT_TOTAL`.

The Terranex side is always derived inside PostgreSQL from posted journal lines by an internal function that is revoked from `authenticated`. The external number is **evidence only**: it is stored with a source reference and an evidence reference, and it never influences a Terranex balance. `REALIZED_RESULT` uses exactly the same economic definition S5 allocates from, so the two can never drift apart by construction.

The variance is a derived integer enforced by a CHECK: `variance = external − terranex`. Zero variance is explicit (`MATCHED`), never implied by absence. A non-zero variance is `VARIANCE` and **must** create a visible exception carrying an owner who is an active member, a severity of `LOW|MEDIUM|HIGH|CRITICAL`, a status, and later a resolution with its own evidence reference. A checkpoint carries at most one open exception at a time.

Sign-off is immutable and maker/checker: the signer is recorded with a timestamp and evidence reference, cannot be the preparer (CHECK), and cannot sign off while an open exception remains. A signed-off checkpoint is frozen by trigger; the economics of any recorded checkpoint are immutable from the moment of recording. Correcting a variance means recording a *new* checkpoint, not editing the old one.

This is not a second ledger. Checkpoints hold no postable balance and feed nothing.

## 3. End-to-end technical rehearsal

`supabase/tests/27_s7_end_to_end_rehearsal.sql` provisions its own fixture project and drives the entire product through production commands only: S0 project and period → S1 parties, agreement, capital call, contributions → S7 opening import → S2 cash attribution, obligation, payment → S3 profile, asset, parcel, controls, acquisition, development phase → S4 disposition, control transfer, recognition, selling cost, collection → S6 close and controlled reopen → S5 rule basis, allocation, distribution, payment → S7 nine reconciliation checkpoints and immutable sign-off.

It is deterministic: every figure is a fixture constant, and the nine checkpoints compare derived balances against literals. A one-minor-unit drift anywhere in the chain produces a non-zero variance, an exception, a refused sign-off, and a failing suite. It asserts balance integrity, the exact cash position, the per-investor capital rollforward, and the provenance chain from opening import to journal, from sale to carrying-cost sources, and from close snapshot to allocation to distribution to payment.

Only after every assertion holds does it record an `END_TO_END_CYCLE` rehearsal fact. It then asserts that the human UAT gate for that project is still `NOT_STARTED`. A passing rehearsal can never advance a human gate.

Fixtures only. No customer data is in this repository.

## 4. Backup and restore rehearsal

`supabase/tests/26_s7_backup_restore.sh` is executable and runs on every canonical database gate. It captures seventeen integrity fingerprints from the verification database — tenant isolation, cross-tenant journal leakage, unbalanced batches, journal totals, cash positions, obligation positions, S6 snapshot provenance and period versions, S5 allocation provenance and totals, distribution settlement, partner-capital rollforward, S7 import state and row fingerprints, S7 reconciliation state, S7 UAT state, and audit volume — then dumps with `pg_dump`, restores into a clean database with `pg_restore`, and re-runs every query on the copy. Any difference fails loudly.

It additionally proves that *structure* survived, not only data: forced default-deny RLS on fourteen tenant tables, six critical immutability and recovery triggers, and a live tamper attempt against a posted journal line that must still be refused.

It refuses to skip itself: if no `pg_dump`/`pg_restore` of a sufficient major version is available, it exits non-zero. It also requires `docs/runbooks/BACKUP_AND_RESTORE.md` to exist, because an executable rehearsal without a written operator procedure is not a restorable system.

It uses standard PostgreSQL tooling, no production credentials, and no production system. On success it records a `BACKUP_RESTORE` rehearsal fact whose evidence explicitly carries `production_restore_performed: false`. **A production restore has not been performed and is not claimed.**

## 5. Access revocation and recovery hardening

`s7_set_membership_status` is the single owner-gated command for membership status, with a mandatory reason and idempotency key. Revocation is immediate: an already-open session loses read access through RLS and is refused by every privileged command in the same instant, leaving no partial row behind. A plain member cannot change any membership status, including their own.

A last-active-owner guard makes it impossible — including by direct DML — to leave an organization without an active owner. Owner recovery is therefore always "appoint, then revoke". This is the minimum viable owner/recovery control set; it is explicitly not an RBAC framework, and no new role hierarchy is introduced.

Revocation must not weaken existing controls, so the suite re-asserts that S5 allocation and S5 distribution self-approval remain impossible after S7's access changes, and that every S7 maker/checker constraint holds. Cross-organization references remain rejected by normalized composite foreign keys and by command-level checks; a member of another tenant sees zero rows in every S7 read model.

No service-role key exists in the browser path: the client is built from the publishable key only, and browser-reachable roles have `select` on read models and nothing else.

## 6. UAT and acceptance evidence

`s7_uat_tasks` is a durable model: task code (`^S7-UAT-[A-Z0-9-]{2,40}$`), project, title, expected outcome, status in `PENDING|EXECUTED|ACCEPTED|REJECTED`, executor, reviewer, timestamps, evidence reference, and notes or rejection reason. It is append-only.

The rules are absolute:

- A registered task starts `PENDING` and stays there without real evidence.
- Recording an execution moves it to `EXECUTED` — never further.
- Acceptance is a separate act by a different person; the executor can never accept their own task.
- Nothing in the system can move a task to `ACCEPTED` by itself. No rehearsal, no test, no gate.

`s7_pilot_rehearsals` records technical rehearsal results (`END_TO_END_CYCLE`, `BACKUP_RESTORE`, `ACCESS_REVOCATION`) as immutable append-only facts. A rehearsal is explicitly not UAT.

`s7_pilot_acceptance_report_read` derives machine-verifiable technical readiness from recorded facts only: posted opening imports, rejected rows, control-total match, checkpoint count, non-zero variances, maximum absolute variance, unresolved and unresolved-critical exceptions, unreconciled bank lines, unbalanced batches, partner-capital rollforward breaks, investor statement total, and the latest result of each rehearsal code. The human gate is reported **separately** as `human_uat_status ∈ NOT_STARTED|PENDING|ACCEPTED|REJECTED`, computed only from real UAT task states. A rehearsal that was never recorded reports as unknown (`null`), never as PASS.

## 7. Pilot workspace UX

The pilot workspace lives inside the existing project workspace at `/projects/[projectId]/pilot`. No new application shell, no new navigation paradigm. It is Arabic and RTL, consistent with the rest of the product, and mobile-usable.

It surfaces: opening import status with control totals and variances, rejected rows with reasons, reconciliation checkpoints with exact variances, pending approvals, unresolved exceptions with severity, UAT task state, rehearsal history, and the acceptance report — with the human UAT line reported separately and never merged into the technical summary. Totals drill through to their source rows.

Distinct states are handled rather than collapsed: loading, empty, filtered-empty, validation error, server error, forbidden, conflict, and completed. Every mutation is a server action against a database command; the browser computes no authoritative money.

## 8. Security and data hardening

All six new tenant tables carry `enable row level security` **and** `force row level security`, with membership-scoped read policies and no browser write grants. Read models are `security_invoker=on`. Every S7 `SECURITY DEFINER` function pins `search_path=pg_catalog,public` and is revoked from `public` and `anon`; internal derivation functions are revoked from `authenticated` as well.

Org-aware composite foreign keys make cross-tenant references structurally impossible rather than merely checked. Text inputs are length-bounded and rejected if they contain unsafe control characters. CSV/formula injection is handled by prefixing an apostrophe on any exported value beginning with `=`, `+`, `@`, `-`, tab, or carriage return. Audit payloads carry identifiers and amounts, not free-text document contents.

Approved imports, recorded checkpoints, sign-offs, UAT evidence, and rehearsal records are immutable by trigger. Every command is deterministically idempotent on an explicit key bound to a request hash, so a retry has exactly one material effect and a changed payload under a reused key is refused.

No queues, no microservices, no service-role workflows.

## 9. Explicitly out of scope

Agriculture and Livestock; a workflow or rules engine; advanced waterfalls, preferred return, carry or clawback; a tax engine; statutory-accounting claims; native bank execution; a marketplace; billing; AI; a report builder; a generic accounting integration; offline/PWA; and any customer-specific fork. Payments remain records of the customer's existing banking process — Terranex does not move money.

## 10. Verification contract

The stage is delivered only when, on the final PR head:

- `npm ci --no-audit --no-fund`, lint, typecheck, test, and production build all pass;
- PostgreSQL 16 clean replay passes, including every existing S0–S6 suite unchanged;
- the S7 behavioural suite, the S7 two-session concurrency races, the S7 forward upgrade from the merged S5/S6 boundary, the S7 backup/restore rehearsal, and the S7 end-to-end rehearsal all pass;
- the Sonar Quality Gate passes without exclusions or lowered thresholds.

No prior test was weakened to make S7 pass.

## 11. Truthfulness boundary

Passing every gate above establishes **technical** pilot readiness. It does not establish that a controlled paid pilot ran, that a real customer's opening balances were imported, that four weekly reconciliations were performed on real data, or that buyer UAT was completed. Those are human events with real customer evidence, and the product reports them separately and honestly: `human_uat_status` stays `NOT_STARTED` or `PENDING` until a real authorised customer approver accepts a real executed task.

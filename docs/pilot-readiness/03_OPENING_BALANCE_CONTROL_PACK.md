# 03 — Opening-Balance Control Pack

**Purpose:** one unambiguous procedure that takes the customer's signed source position at the freeze date to a posted, reconciled, signed-off opening position in Terranex — using the S7 controlled opening import exactly as built (`docs/decisions/0009_S7_PILOT_HARDENING.md` §1–2) and `docs/runbooks/FAILED_OPENING_IMPORT.md` for every failure.

Gates covered: PRM-06 (opening import), PRM-07 (opening reconciliation).

## 1. The five artifacts — never confuse them

The opening workflow produces five **distinct** artifacts. They have different owners, different lifecycles, and different evidential weight. An operator must be able to state, at any moment, which one they are looking at.

| # | Artifact | What it is | Where it lives | Mutability | Who produces it |
| --- | --- | --- | --- | --- | --- |
| A | **Imported source evidence** | The customer's signed trial balance and delivered worksheets (DS-09), with their declared totals | Customer systems; references in the evidence register | Frozen by the customer at the freeze date | Customer finance lead |
| B | **Validated rows** | The staged S7 import (`DRAFT → VALIDATED → READY_FOR_APPROVAL`) with per-row outcomes and zero rejected rows | `s7_opening_imports` / `s7_opening_import_rows` | Append-only import record; superseded by a corrected staging, never edited | Import maker |
| C | **Approved rows** | The same staged import after OWNER approval with posting date — an immutable approved snapshot hash exists | `s7_opening_imports` (`APPROVED`) | Immutable snapshot hash | Customer OWNER (≠ maker) |
| D | **Posted journal facts** | The balanced `S7_OPENING_IMPORT` journal batch on canonical semantic accounts | `journal_batches` / `journal_lines` | Immutable by trigger; correction only via linked reversal | The product, atomically, at approval |
| E | **Reconciliation evidence** | S7 checkpoints comparing derived posted balances to the external signed totals, with variances and sign-off | `s7_reconciliation_checkpoints` (+ exceptions) | Immutable once recorded; sign-off frozen | `<FINANCE_CONTROL_OWNER>` prepares, independent signer signs |

**Hard rules that keep them separate:**

- Artifact A never influences a Terranex balance. External numbers are evidence only (ADR 0009 §2).
- Artifact B cannot post while any row is rejected — rejected-row atomicity is enforced by the product.
- Artifact C is a different person's act than B (table CHECK: maker ≠ approver; approval is OWNER-gated).
- Artifact D is created only by the product in one atomic posting; no balance is ever written directly.
- Artifact E is recorded **after** D exists, compares D against A, and is signed by someone who did not prepare it. A checkpoint is never "signed" from artifacts B/C alone.

The pilot workspace surfaces each artifact in a separate section (import status / checkpoints / UAT); never present them merged.

## 2. Step 1 — Source freeze date

- The customer OWNER and `<PILOT_OPS_OWNER>` agree one calendar date: the **freeze date**. All intake balances are as of end-of-day on this date.
- From the freeze date, the customer's source ledger for the pilot project(s) is frozen for intake purposes: later corrections produce a *new dated extract*, never a silent rewrite of the frozen one.
- **Evidence:** freeze-date record (date, project list, agreeing parties) in the evidence register.
- **Pass:** exactly one freeze date per pilot project, recorded before any dataset is accepted.

## 3. Step 2 — Source-system evidence

- The customer exports the trial balance and sub-ledger extracts (DS-09…DS-15) from their own system/spreadsheet as of the freeze date.
- Every extract carries: source system name, extract date, preparer, and the control totals in §4.
- Terranex staff never prepare the customer's trial balance for them. If the customer asks Terranex to construct it, that is a scope/commercial decision (roadmap risk: paid data-cleaning gate), not a silent service.
- **Evidence:** extract metadata recorded per dataset in the coverage tracker.

## 4. Step 3 — Signed control totals

Before any staging, the customer finance lead declares **in writing** (signed document or tracked email):

| Total | Definition |
| --- | --- |
| Declared debit total | Σ debit balances to import, integer minor units |
| Declared credit total | Σ credit balances to import, integer minor units |
| Cash per account | opening bank/cash balance per DS-08 account |
| Payables total | Σ `OPENING_SUPPLIER_PAYABLE` |
| Receivables total | Σ `OPENING_CUSTOMER_RECEIVABLE` |
| Contributed capital total | Σ `OPENING_CONTRIBUTED_CAPITAL` |
| Unpaid distributions total | Σ `OPENING_DISTRIBUTION_PAYABLE` |
| WIP total | Σ `OPENING_DEVELOPMENT_WIP` |

**Acceptance rule:** declared debit total must equal declared credit total. If the customer's own trial balance does not balance, intake stops at PRM-05 — the customer fixes their own books first. Terranex does not accept a plug.

## 5. Step 4 — Mapping review

- The import maker maps every trial-balance line to exactly one of the six locked S7 mapping codes, on `templates/opening-import-worksheet.csv`.
- The `<FINANCE_CONTROL_OWNER>` reviews the mapping **before** staging:
  - every line with a party balance uses a party-scoped code and a DS-03-matched party;
  - every cash line uses `OPENING_BANK_CASH` with the correct project cash account;
  - no line is forced into a code it does not semantically fit — an unmappable line is a modelling gap report (ADR 0009 §1), decided commercially;
  - the one-route-per-fact rule holds: a pre-freeze contribution expressed as `OPENING_CONTRIBUTED_CAPITAL` + `OPENING_BANK_CASH` is **not** also recorded via the S1/S2 contribution flow (double counting), and vice versa. The coverage tracker records which route was chosen per fact class.
- **Evidence:** mapping worksheet + review note (reviewer, date, exceptions).

## 6. Step 5 — Row-level validation

- The import maker stages the import in the pilot workspace: source file name, SHA-256 checksum of the final worksheet export, declared totals from §4, then the rows.
- Validation runs; the product produces per-row outcomes with the twelve explicit rejection reasons (listed in `02_DATA_INTAKE_CONTRACT.md` DS-09).
- **Pass condition for this step:** status `VALIDATED` or `READY_FOR_APPROVAL` with **zero rejected rows** and computed totals equal to declared totals to the minor unit.
- **Evidence:** import record id, checksum, accepted/rejected counts, declared and computed variances (both must be 0).

## 7. Step 6 — Rejected-row resolution

If any row is rejected:

1. Read the reason; map it back to the source worksheet row via `row_ref`.
2. Fix the data **at the source** (customer extract or mapping worksheet). Content corrections that change amounts or balances require a new dated extract per §3.
3. Re-stage. A staged import that cannot be repaired is explicitly `REJECTED` with a reason — the product keeps the record append-only.
4. **Never**: edit a rejected row into a different semantic to make it pass; split one balance across codes to dodge validation; approve with rejects outstanding (the product refuses anyway).

Escalate to `docs/runbooks/FAILED_OPENING_IMPORT.md` when validation fails repeatedly, when control totals do not reconcile, or when approval is refused.

## 8. Step 7 — Trial import (dry verification)

Before asking the OWNER to approve:

1. Re-verify computed vs declared totals on the staged import (both variances 0).
2. Re-verify debits = credits (product-enforced, but the preparer confirms the number they will present to the approver).
3. Prepare the approval pack: staged import id, row count, accepted count, total, the mapping-review note, the signed control totals from §4.
4. The maker moves the import to `READY_FOR_APPROVAL` (review step) — this is the "trial" boundary: everything short of posting has happened, and nothing posts until approval.

There is deliberately no "post then fix" mode. The trial import is a review state, not a sandbox posting.

## 9. Step 8 — Approval

- The customer OWNER (who is **not** the maker — table CHECK) reviews the approval pack and approves with a posting date.
- Posting date must fall inside exactly one OPEN accounting period for the project (product-enforced; S6 period rules apply).
- Approval is idempotent only for an identical request (same idempotency key **and** same request hash); anything else is refused.
- **Evidence:** approval record (actor, timestamp, posting date) on the import.

## 10. Step 9 — Posting

- Posting is atomic: one balanced `S7_OPENING_IMPORT` journal batch through the canonical S2 invariants and period lock.
- Immediately after posting, verify from the product's own read models (never from the browser's memory of what was submitted):
  - import state `POSTED`;
  - the project's cash positions per account equal the `OPENING_BANK_CASH` rows;
  - the partner/capital and payable/receivable positions reflect the posted lines.
- **Evidence:** posted batch reference.

## 11. Step 10 — Post-import reconciliation (gate PRM-07)

Compare artifact D against artifact A using S7 checkpoints, recorded with as-of date = freeze date (or the first open period date consistent with the checkpoint semantics):

| Checkpoint | External value source (artifact A) | Expected variance |
| --- | --- | --- |
| `PROJECT_CASH` | signed bank confirmation / trial balance cash per account (Σ accounts) | 0 |
| `CONTRIBUTED_CAPITAL` | trial balance contributed capital | 0 |
| `SUPPLIER_OBLIGATION_POSITION` | trial balance/AP aging payables total | 0 |
| `CUSTOMER_RECEIVABLE_POSITION` | trial balance receivables total | 0 |
| `DISTRIBUTION_PAYABLE` | trial balance unpaid distributions | 0 |
| `PARTNER_CAPITAL` | partner capital schedule at freeze | 0 |

Each checkpoint stores `variance = external − terranex` as an exact integer.

**Explicit zero-variance acceptance:** a checkpoint with variance 0 is recorded as `MATCHED`. Zero is stated in the record; it is never implied by silence, and an absent checkpoint is never treated as reconciled. Sign-off requires: variance 0, no open exception, signer ≠ preparer, evidence reference attached. Sign-off is immutable; a signed checkpoint is frozen.

## 12. Step 11 — Variance handling

If any checkpoint shows variance ≠ 0:

1. The product automatically opens an exception (`LOW|MEDIUM|HIGH|CRITICAL`) with an owner who is an active member. Do not sign off — the product refuses while the exception is open.
2. Locate the divergence: artifact A (source wrong), artifact B/C (mapping or row wrong), or artifact D (posting wrong).
3. Correction paths, **only**:
   - source wrong → customer issues a corrected extract; the posted opening is corrected through linked reversal of the opening batch (subject to the reversal guard: later un-reversed postings must be reversed first, in order) or through a superseding corrected import after reversal — per `docs/runbooks/FAILED_OPENING_IMPORT.md`;
   - posting materially wrong → `docs/runbooks/INCORRECT_POSTED_TRANSACTION.md`;
   - never: edit a checkpoint, delete an exception, or sign off with variance outstanding.
4. After correction, record a **new** checkpoint with the corrected external value or corrected Terranex balance. Correcting a variance means recording a new checkpoint, never editing the old one (ADR 0009 §2).
5. Resolve the exception with a resolution statement + evidence reference, then sign off the new checkpoint.

**Severity guidance for opening variances:** CRITICAL — cash or capital variance with no identified cause; HIGH — any identified variance above immateriality the customer sets; MEDIUM — identified single-row mapping error; LOW — presentation difference already explained and corrected. (The customer defines materiality for their business; the acceptance threshold in this pack remains 0 minor units regardless.)

## 13. Step 12 — Final sign-off

The opening position is **final** only when all of the following are true and recorded:

- [ ] Freeze date recorded (§2); source extracts evidenced (§3).
- [ ] Signed control totals declared and internally balanced (§4).
- [ ] Mapping reviewed by `<FINANCE_CONTROL_OWNER>` (§5).
- [ ] Staged import validated with zero rejected rows; declared = computed totals to the minor unit (§6).
- [ ] OWNER approval by a user who is not the maker; posting date in an OPEN period (§9).
- [ ] Import `POSTED`; balances verified from read models (§10).
- [ ] All applicable opening checkpoints recorded with variance = 0 (`MATCHED`), zero open exceptions, signed off by an independent signer (§11).
- [ ] The acceptance report's technical readiness lines (posted opening import, rejected rows = 0, control-total match, non-zero variances = 0) reviewed and attached to the pilot record.

**Sign-off record:** who signed, when, with which evidence references. From this moment, the opening position is an immutable posted fact; any later change goes through reversal/correction runbooks and a new checkpoint, never through this procedure again.

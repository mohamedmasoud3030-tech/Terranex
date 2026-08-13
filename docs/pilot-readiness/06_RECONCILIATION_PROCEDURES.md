# 06 — Reconciliation Procedures

**Purpose:** ten repeatable reconciliations for the pilot (weekly where noted), each with fixed sources, calculation, and acceptance. They are executed through the product's existing machinery: S2 bank matching, S6 close gates, and the nine S7 reconciliation checkpoints (`PROJECT_CASH`, `SUPPLIER_OBLIGATION_POSITION`, `CUSTOMER_RECEIVABLE_POSITION`, `REALIZED_RESULT`, `CONTRIBUTED_CAPITAL`, `PARTNER_CAPITAL`, `DISTRIBUTION_PAYABLE`, `DISTRIBUTION_PAID`, `INVESTOR_STATEMENT_TOTAL`).

**Universal acceptance rule:** financial acceptance variance is **zero minor units**. There are no percentage tolerances, immateriality bands, or rounding accommodations anywhere in this pack. The S7 checkpoint stores `variance = external − terranex` as an exact integer; acceptance is `MATCHED` at variance 0, recorded explicitly — never implied. Any non-zero variance opens a mandatory owned exception; sign-off is refused while it is open. The Terranex side is always derived inside PostgreSQL from posted journal lines; the external number is evidence only and never influences a Terranex balance.

**Four categories that must never be collapsed** (per `05_FINANCE_AND_ACCOUNTING.md` and the charter's principles):

| Category | Examples | Reconciliation treatment |
| --- | --- | --- |
| Authoritative financial facts | posted journal lines, derived balances, checkpoints' Terranex side | reconcile exactly, zero minor units |
| External evidence | bank statements, customer trial balance, capital register | evidence only; never writes a Terranex balance |
| Management estimates/valuations | `property_valuations`, forecast-at-completion | **not** ledger reconciliation inputs. A valuation differing from cost or from a prior estimate is a business/evidence matter reviewed via the valuation workflow (method/source/approval); it never silently becomes a ledger tolerance, and it never enters a checkpoint as a "variance to accept" |
| Operational status | lifecycle states, milestone completion, exception states | reviewed as operational truth; a status is never a substitute for a financial figure |

If a valuation or estimate disagrees with posted cost/result, the disagreement is documented and decided by the approval workflow — the ledger side stays exact and unrevised until a real correction posts through the product.

**Universal roles:** preparer = `<FINANCE_CONTROL_OWNER>` (or delegate); signer = a different active member; sign-off is immutable and maker/checker (product CHECK: signer ≠ preparer). Exception owner = active member named on the exception.

**Universal record per run:** date, period/week, checkpoint ids, external source reference, evidence reference, variance, exception ids (if any), signer.

---

## R-01 — Bank ↔ book (weekly, per account)

- **Source A:** bank-issued statement lines for the period (immutable imported external facts with provider fingerprint).
- **Source B:** posted book cash movements (receipts/payments/contributions) from journal lines.
- **Calculation:** explicit reconciliation matches (one-to-one; one-to-many/many-to-one only via explicit reconciliation groups). Unmatched on either side remain listed as reconciling items.
- **Acceptable variance:** 0 unmatched minor units at week end, or every unmatched item carries an owner and an explanation that resolves within 7 days (aged unreconciled cash must be 0 at close).
- **Evidence:** reconciliation match references; remaining unmatched list.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** `docs/runbooks/UNRECONCILED_CASH.md`.
- **Sign-off:** weekly signer on the derived `PROJECT_CASH` checkpoint set (see R-02).

## R-02 — Project cash (weekly checkpoint)

- **Source A:** bank-confirmed closing balance per pilot account (statement closing balance or bank confirmation), Σ across accounts.
- **Source B:** `PROJECT_CASH` — Terranex derived cash position from posted journal lines.
- **Calculation:** variance = Σ bank closing − Terranex derived position (integer minor units).
- **Acceptable variance:** 0.
- **Evidence:** statement/bank confirmation references; checkpoint record.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** trace difference to R-01 unmatched items or a wrong posting (`INCORRECT_POSTED_TRANSACTION.md`); correct; record a **new** checkpoint.
- **Sign-off:** independent signer; checkpoint frozen on sign-off.

## R-03 — Contribution / capital position (weekly)

- **Source A:** customer's capital register: commitments, called, contributed per participant (from their agreement administration/spreadsheet).
- **Source B:** `CONTRIBUTED_CAPITAL` checkpoint total and the per-participant contribution records derived from posted events.
- **Calculation:** variance = external contributed total − Terranex contributed capital; per-participant differences listed separately.
- **Acceptable variance:** 0 on the total and on every participant line (a total that matches via offsetting participant errors is a fail, not a pass).
- **Evidence:** capital register reference; checkpoint.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** locate missing/duplicated contribution postings; correct via reversal/repost; new checkpoint.
- **Sign-off:** independent signer.

## R-04 — Obligation / payable position (weekly)

- **Source A:** customer AP aging / supplier statements at the reconciliation date.
- **Source B:** `SUPPLIER_OBLIGATION_POSITION` — derived supplier payable position.
- **Calculation:** variance = external payables total − Terranex derived total; material per-supplier differences listed.
- **Acceptable variance:** 0.
- **Evidence:** AP aging reference; checkpoint.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** missing obligation → record it; wrong posting → `INCORRECT_POSTED_TRANSACTION.md`; settled-but-unrecorded payment → record per UAT-06 flow; new checkpoint.
- **Sign-off:** independent signer.

## R-05 — Property carrying cost (weekly; close-mandatory)

- **Source A:** customer's cost ledger / development cost schedule per asset-phase at the reconciliation date.
- **Source B:** Terranex derived carrying position: `DEVELOPMENT_WIP`-role balances from posted lines plus acquisition carrying-cost sources on assets.
- **Calculation:** variance = external carrying total − Terranex carrying total, per pilot asset.
- **Acceptable variance:** 0.
- **Evidence:** cost schedule reference; derivation breakdown.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>` with the operating member who captures costs.
- **Resolution:** missed obligation/cost item → capture and post; wrong `cost_treatment` → correction path; new checkpoint (record as checkpoint-adjacent evidence if no matching checkpoint code applies — the close gate `ASSET_SECTOR_ROLLFORWARDS` carries the formal control at close).
- **Sign-off:** independent signer; at close, evidenced inside `ASSET_SECTOR_ROLLFORWARDS` gate evidence.

## R-06 — Sale receivable / collection (weekly when sales exist)

- **Source A:** customer's sale contracts and collection records (contracted proceeds, collected to date).
- **Source B:** `CUSTOMER_RECEIVABLE_POSITION` — derived open sale receivables; collection records matched to bank lines.
- **Calculation:** variance = external open receivable − Terranex derived receivable; collection completeness = every collection matched to a bank line.
- **Acceptable variance:** 0.
- **Evidence:** contract/collection references; checkpoint; unmatched collections list (must be empty).
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** unmatched collection → `UNRECONCILED_CASH.md`; wrong recognition → `INCORRECT_POSTED_TRANSACTION.md`; new checkpoint.
- **Sign-off:** independent signer.

## R-07 — Partner capital (weekly; close-mandatory)

- **Source A:** customer's per-partner capital schedule at the reconciliation date.
- **Source B:** `PARTNER_CAPITAL` — derived partner capital position; rollforward equation: Closing = Opening + Contributions + AllocatedIncome − AllocatedLoss − Distributions + OtherApprovedCapitalAdjustments.
- **Calculation:** variance per participant and in total; the rollforward must reproduce the closing balance exactly from postings.
- **Acceptable variance:** 0 per participant and in total; zero rollforward breaks.
- **Evidence:** partner schedule reference; checkpoint; rollforward breakdown.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** trace to R-03 (contributions), allocation lines (R-08), or distribution records; correct the wrong side; new checkpoint.
- **Sign-off:** independent signer; at close, formalized in the `PARTNER_CAPITAL_ROLLFORWARD` gate (FAIL is a close blocker).

## R-08 — Allocation / distribution (per allocation event; close-mandatory totals)

- **Source A:** independent recalculation of the allocation from the close snapshot source amount and the governing agreement's shares (customer spreadsheet is acceptable and expected).
- **Source B:** allocation run lines; `DISTRIBUTION_PAYABLE` and `DISTRIBUTION_PAID` checkpoints.
- **Calculation:** per-participant variance = independent amount − allocation line; payable/paid variances = external − derived. Line totals must equal the allocable source exactly (largest-remainder rounding residual is stored, never lost).
- **Acceptable variance:** 0 per participant and on payable/paid totals.
- **Evidence:** independent recalculation reference; allocation run id; checkpoints.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** `docs/runbooks/FAILED_ALLOCATION_OR_DISTRIBUTION.md`; an approved run is never overwritten — correction is a new comparison or a reversal per the runbook; new checkpoints.
- **Sign-off:** independent signer.

## R-09 — Opening balances (once, at PRM-07; re-run only via correction)

- **Source A:** signed customer trial balance at the freeze date (artifact A of the control pack).
- **Source B:** posted `S7_OPENING_IMPORT` batch, checkpointed per `03_OPENING_BALANCE_CONTROL_PACK.md` §11.
- **Calculation:** declared vs computed control totals (both variances 0); checkpoint variance per balance class = external − derived.
- **Acceptable variance:** 0 everywhere, to the minor unit; debits = credits.
- **Evidence:** import record (checksum, counts, totals), checkpoint set, sign-offs.
- **Exception owner:** `<FINANCE_CONTROL_OWNER>`.
- **Resolution:** `FAILED_OPENING_IMPORT.md` (reversal-guard ordering) then new checkpoints.
- **Sign-off:** independent signer per checkpoint.

## R-10 — Close snapshot (per period close)

- **Source A:** the week-4 checkpoint set (R-02…R-08 all signed) plus the close checklist inputs.
- **Source B:** the S6 close run with its ten gates and the immutable close snapshot.
- **Calculation:** every gate computed server-side; `JOURNAL_BATCHES_BALANCED` (all batches balance), `BANK_RECONCILIATION_COVERAGE` (unresolved lines FAIL unless approved exception), `SUSPENSE_CONTROL_ACCOUNTS`, `RECEIVABLE_PAYABLE_AGING`, `ASSET_SECTOR_ROLLFORWARDS`, `EVIDENCE_AND_APPROVALS`, `POSTING_CURRENCY_RULES`, `SECTOR_CUT_OFF`, `PARTNER_CAPITAL_ROLLFORWARD`, `CLOSE_REPORT_AND_EXCEPTIONS`.
- **Acceptable variance:** 0 unreconciled/unexplained minor units across gates; any `APPROVED_EXCEPTION` carries evidence and an owner.
- **Evidence:** close run id, gate results, snapshot hash, exception records.
- **Exception owner:** close preparer triages; OWNER decides approval.
- **Resolution:** per gate: cash → `UNRECONCILED_CASH.md`; closed-period facts later found wrong → `CLOSED_PERIOD_CORRECTION.md`; reopen only through the controlled superseding period version.
- **Sign-off:** OWNER close approval (product-enforced); snapshot immutable.

---

## Weekly reconciliation record template

| Field | Content |
| --- | --- |
| Week / period | e.g. W2, dates |
| Checkpoints recorded | ids + codes |
| Variances | all 0, or exception ids with severities |
| Exceptions opened / resolved | ids, owners, resolutions, evidence |
| Consecutive count | n of 4 (resets on any unsigned week) |
| Sign-off | signer ≠ preparer, timestamp, evidence reference |

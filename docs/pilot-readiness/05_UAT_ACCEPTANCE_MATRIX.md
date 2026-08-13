# 05 — UAT as Real Business Acceptance

**Purpose:** the pilot UAT matrix. Scenarios are **business outcomes over S0–S7**, not button-level UI checks. Each is a human acceptance task to be executed on the pilot customer's real data during Weeks 0–4.

**Status of every scenario below: `PENDING`.** Nothing in this document, in any script, or in any rehearsal marks a scenario passed. The product's UAT model (`s7_uat_tasks`) enforces: a task starts `PENDING`; execution moves it to `EXECUTED` only; acceptance is a separate act by a different person (executor ≠ acceptor); no rehearsal, test, or gate can self-accept.

## Operating conventions

- **Task codes:** register each scenario as `S7-UAT-<SEQ>` (product pattern `^S7-UAT-[A-Z0-9-]{2,40}$`), e.g. `S7-UAT-01`…`S7-UAT-19`.
- **Roles:** application roles are only `OWNER` and `MEMBER` (status `ACTIVE`/`INACTIVE`). Scenario roles below add the operational responsibility from `09_PILOT_ROLES_AND_RESPONSIBILITIES.md` in parentheses.
- **Executor:** the customer user who runs the scenario. **Acceptor:** `<CUSTOMER_APPROVER>` only. They must be different people.
- **Evidence:** every execution records an evidence reference (document identifier in the customer's systems). Scenarios touching posted facts must cite the resulting batch/checkpoint/statement identifiers.
- **Rejection:** any scenario may be `REJECTED` with a mandatory reason; disposition is fix-and-rerun or logged to the GA backlog with written customer agreement.

Legend for expected results: amounts are exact integer minor units; "derives" means computed server-side from posted lines, never stored.

---

## UAT-01 — Organization and project access

- **Business precondition:** pilot organization exists with at least two members (OWNER + one MEMBER); the pilot project is configured.
- **Role:** MEMBER (operating member).
- **Action:** sign in; open the pilot project workspace; attempt to read a project of a **different** organization (second test org provisioned for this scenario).
- **Expected result:** the pilot project opens with overview, cash, and exceptions; the foreign organization's project is not visible and every read attempt is refused (default-deny RLS). No row from another tenant appears anywhere.
- **Evidence:** screenshots/session reference of both attempts; foreign-org refusal message.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-02 — Agreement version

- **Business precondition:** DS-04 delivered; investor parties exist.
- **Role:** MEMBER (import maker) prepares; OWNER activates.
- **Action:** create the governing agreement version with participants, commitments, and allocation basis; activate it.
- **Expected result:** activation stores an immutable governing version snapshot with commitments; participant shares resolve to exactly 100%; the version cannot be edited after activation (amendment is a deferred capability — attempting it must not silently mutate history).
- **Evidence:** activated version reference; attempt-to-edit refusal.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-03 — Capital call

- **Business precondition:** governing agreement active.
- **Role:** MEMBER (finance) issues under the OWNER mandate.
- **Action:** issue a capital call with due date and per-participant lines from the effective agreement.
- **Expected result:** call lines match the agreement basis; call state `ISSUED`; totals exact in minor units; the call changes no cash or capital by itself (commitment ≠ called ≠ contributed).
- **Evidence:** call reference and line totals; agreement basis reference.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-04 — Contribution

- **Business precondition:** open capital call; pilot cash account exists.
- **Role:** MEMBER (finance).
- **Action:** record a contribution against a call line for a real receipt; post its cash effect via the controlled contribution-to-cash attribution.
- **Expected result:** contribution posts cash (Debit bank/project cash / Credit contributed capital) atomically; capital rollforward updates only from the posted event; repeating the attribution with the same idempotency key has exactly one material effect.
- **Evidence:** contribution record, posted batch reference, updated rollforward.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-05 — Obligation approval

- **Business precondition:** supplier party exists; open period.
- **Role:** MEMBER (operating member) prepares draft; OWNER authorizes.
- **Action:** prepare a cost obligation with explicit `cost_treatment` (`EXPENSE` or `CAPITALIZABLE_WIP`); OWNER authorizes.
- **Expected result:** authorization posts the balanced batch (Expense or Development WIP / Supplier Payable); a non-OWNER cannot authorize; the draft cannot be authorized twice under a changed payload with a reused key.
- **Evidence:** obligation reference; posted batch; refusal evidence for the non-OWNER attempt.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-06 — Payment

- **Business precondition:** authorized obligation; funded pilot cash account; **the customer's banking process has actually executed the payment outside Terranex**.
- **Role:** OWNER (payment posting is OWNER-authorized in the S2 model).
- **Action:** record the payment against the obligation after the bank execution.
- **Expected result:** payment posts (Supplier Payable / Cash) with exact amounts; obligation settlement state updates; Terranex never initiates or claims to initiate the money movement — the record states it follows the customer's banking process.
- **Evidence:** payment reference; bank statement line reference showing the real outflow.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-07 — Bank reconciliation

- **Business precondition:** posted receipts/payments; real bank statement lines imported.
- **Role:** MEMBER (finance) imports/matches; OWNER voids if needed.
- **Action:** import statement lines; reconcile matched lines one-to-one; leave one line deliberately unmatched; attempt a duplicate import of the same statement.
- **Expected result:** matched lines reconcile without recreating payments; the unmatched line stays visible as unreconciled; the duplicate import is refused by account + provider fingerprint; book and bank balances remain separately displayed with reconciling items.
- **Evidence:** reconciliation match references; duplicate-import refusal; unreconciled line reference.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-08 — Property lifecycle

- **Business precondition:** real-estate profile, asset, parcels, and acquisition entered (DS-11/DS-12).
- **Role:** MEMBER (operating member); OWNER where the transition is material.
- **Action:** drive the asset through its implemented lifecycle path (e.g. acquisition recorded → control record → development phase events), confirming each state with evidence.
- **Expected result:** lifecycle transitions are explicit commands with history (state history immutable); no "owned" state without acquisition/control evidence; transitions preserve parcel/asset integrity.
- **Evidence:** state history references; control record reference.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-09 — Budget vs actual

- **Business precondition:** approved budget version; posted costs (obligation flow).
- **Role:** MEMBER (finance) prepares the view; OWNER reviews.
- **Action:** open the budget-vs-actual position for a development phase/asset after real costs post.
- **Expected result:** cost-to-date derives from posted lines only; budget version is immutable; variance figures drill to postings; capitalizable vs expense treatment is visible and matches obligation choices.
- **Evidence:** report view reference; drill-through to at least one posting.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-10 — Valuation

- **Business precondition:** held asset; valuer/source known.
- **Role:** MEMBER (investment/operating) proposes; OWNER approves.
- **Action:** record a management valuation with method, source, effective date, and evidence reference.
- **Expected result:** valuation is stored as a dated management estimate with approval; it is **never** merged into realized result or presented as guaranteed value; reports keep realized vs valued distinct.
- **Evidence:** valuation record reference; report view showing separation.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-11 — Disposition

- **Business precondition:** asset ready for disposal; buyer party exists.
- **Role:** MEMBER prepares; OWNER approves material steps.
- **Action:** create the disposition, transfer control, and recognize the sale.
- **Expected result:** recognition posts balanced revenue and derecognizes carrying cost via explicit carrying-cost sources; disposal profit = recognized proceeds − carrying amount − selling costs (never cash received alone); selling costs stay separate.
- **Evidence:** disposition, recognition, and carrying-cost-source references; posted batches.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-12 — Collection

- **Business precondition:** recognized sale with open receivable.
- **Role:** MEMBER (finance).
- **Action:** record a collection (including a partial collection) matched to the receivable, then reconcile it to a bank statement line.
- **Expected result:** collection posts cash against the receivable exactly; partial and remaining amounts stay explicit; the collection reconciles to the bank line without recreating the sale.
- **Evidence:** collection and reconciliation references; bank line reference.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-13 — Realized result

- **Business precondition:** recognized revenue and costs in the period.
- **Role:** MEMBER (finance) derives; OWNER reviews.
- **Action:** open the realized-result read model for the project/period.
- **Expected result:** realized result derives from posted lines; it equals exactly the economic definition S5 allocates from (same source, no drift); it excludes valuation movement and cash timing; every total drills to postings.
- **Evidence:** result figure with drill-through references.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-14 — Allocation

- **Business precondition:** an approved S6 close snapshot containing allocable realized result; governing agreement with allocation rule basis.
- **Role:** MEMBER (finance) prepares; a different approver approves (maker/checker enforced).
- **Action:** prepare the allocation run from the close snapshot; approve it.
- **Expected result:** the run stores the exact agreement version, snapshot, inputs, and per-participant lines; largest-remainder rounding makes lines total **exactly** to the source amount; self-approval by the preparer is refused; re-running with current data produces comparison, never overwrite.
- **Evidence:** allocation run reference; line totals proof; self-approval refusal.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-15 — Distribution

- **Business precondition:** approved allocation; distributable position under the recorded-liability rule.
- **Role:** MEMBER proposes; different approver approves; payment recorded after banking execution.
- **Action:** approve a distribution; record its payment as a record of the customer's banking process.
- **Expected result:** approval creates the distribution payable fact; payment settles it only when recorded; distribution cannot exceed the approved payable; concurrent duplicate attempts cannot over-distribute; partner capital updates from postings only.
- **Evidence:** distribution, payment, and capital rollforward references.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-16 — Period close

- **Business precondition:** Week 4 state per the runbook; close blockers resolved.
- **Role:** MEMBER (close preparer) runs the close; OWNER approves.
- **Action:** run the close run; review all ten gates; approve.
- **Expected result:** all gates PASS or APPROVED_EXCEPTION with evidence; approval stores the immutable content-hashed snapshot and locks the period; ordinary posting into the closed period is refused afterwards.
- **Evidence:** close run reference; gate results; post-close posting refusal.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-17 — Correction / reversal

- **Business precondition:** a posted transaction the customer agrees to use for the exercise (or a deliberately staged pilot correction).
- **Role:** MEMBER raises the correction; OWNER approves; `<FINANCE_CONTROL_OWNER>` verifies.
- **Action:** correct a posted fact through the linked reversal/replacement path (and through the closed-period path if the period is closed).
- **Expected result:** the original remains immutable; the reversal exactly negates it with linkage; the replacement posts separately; closed-period correction uses the controlled late-posting/reopen policy with evidence; no destructive edit occurs anywhere.
- **Evidence:** original/reversal/replacement batch chain; correction request reference.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-18 — Opening import / reconciliation

- **Business precondition:** the real opening datasets (DS-09) quality-gated.
- **Role:** MEMBER (import maker) stages; OWNER approves (≠ maker); `<FINANCE_CONTROL_OWNER>` prepares checkpoints; independent signer signs.
- **Action:** execute the full `03_OPENING_BALANCE_CONTROL_PACK.md` procedure on real data, including one deliberate validation failure (e.g. one malformed row) in a discarded staging to observe rejection behavior.
- **Expected result:** the deliberate bad row is rejected with an explicit reason and blocks posting; the corrected staging validates at zero rejects; approval posts one balanced batch; opening checkpoints show variance 0 and are signed off; the acceptance report reflects posted import, zero rejects, control-total match.
- **Evidence:** import ids (discarded + posted), checkpoint ids, sign-off records.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

## UAT-19 — Revoked membership

- **Business precondition:** a pilot user with active membership who has consented to the exercise; at least one other active OWNER exists.
- **Role:** OWNER executes revocation; `<SECURITY_OWNER>` witnesses.
- **Action:** set the user's membership to `INACTIVE` with a reason; the revoked user immediately attempts reads and a privileged command.
- **Expected result:** revocation is immediate — the open session loses read access through RLS and privileged commands are refused at once; the reason and actor are recorded; a MEMBER cannot change any membership status including their own; revoking the last active OWNER is refused.
- **Evidence:** membership change record; refusal evidence from the revoked session; last-owner-guard refusal.
- **Acceptance sign-off:** `<CUSTOMER_APPROVER>`.

---

## Acceptance summary (to be filled only during the pilot)

| Scenario | Code | Executed (who/when/evidence) | Decision (ACCEPTED/REJECTED) | Acceptor |
| --- | --- | --- | --- | --- |
| UAT-01 … UAT-19 | `S7-UAT-01`…`S7-UAT-19` | — pending — | — pending — | `<CUSTOMER_APPROVER>` |

The pilot passes UAT (gate PRM-15) only when every mandatory scenario is `ACCEPTED` in the product and the acceptance report's human gate reads `ACCEPTED` from real task states.

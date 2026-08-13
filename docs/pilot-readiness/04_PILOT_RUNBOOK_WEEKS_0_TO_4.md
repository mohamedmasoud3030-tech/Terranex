# 04 — Four-Week Controlled Pilot Runbook (Week 0 → Week 4)

**Purpose:** the operating plan for the controlled paid Real Estate pilot required by roadmap Phase 4. Week 0 prepares; Weeks 1–3 operate and reconcile; Week 4 closes, verifies, and decides.

**Cadence truth:** the canonical exit gate requires **four consecutive weekly reconciliations**. Weeks 1, 2, 3, and 4 are those four weeks. Week 0 is preparation and does not count. A missed or unsigned week restarts the consecutive count.

**Standing rules:** all severities use the product exception scale `LOW|MEDIUM|HIGH|CRITICAL`; all financial acceptance is zero minor units; payments are recorded **after** the customer's existing banking process executes them (no native money movement); evidence references point at customer-held documents.

---

## Week 0 — Readiness, import, training

Gates covered: PRM-01…PRM-09.

### Environment readiness (days 0–1)

- [ ] PRM-01/PRM-02 completed: `08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md` fully PASS/SIGNED-OFF for the pilot environment.
- [ ] Acceptance report read on the pilot project: technical rehearsals `END_TO_END_CYCLE`, `BACKUP_RESTORE`, `ACCESS_REVOCATION` recorded and current for the deployed release; `human_uat_status` expected `NOT_STARTED`.
- [ ] Support channel live; `SUPPORT_ESCALATION.md` placeholders filled for this engagement (`<PILOT_OPS_OWNER>`, `<FINANCE_CONTROL_OWNER>`, `<ENGINEERING_ONCALL>`, `<SECURITY_OWNER>`, `<CUSTOMER_APPROVER>`).

### Access (days 1–2)

- [ ] Customer OWNER account created and signed in; last-active-owner guard understood (appoint, then revoke — never revoke the only owner).
- [ ] Minimal operating users invited per `09_PILOT_ROLES_AND_RESPONSIBILITIES.md`.

### Data import (days 2–4)

- [ ] PRM-04/PRM-05: intake delivered and quality-gated per `02_DATA_INTAKE_CONTRACT.md`.
- [ ] S1/S2/S3 baseline entered per the binding intake sequence (parties → agreement/commitments → calls → contributions → accounts → assets/acquisitions/budgets).
- [ ] PRM-06: S7 opening import staged, validated (zero rejected rows), approved by OWNER, posted — per `03_OPENING_BALANCE_CONTROL_PACK.md`.

### Opening reconciliation (day 4)

- [ ] PRM-07: opening checkpoints recorded and signed off at variance 0.

### Operator training (days 4–5)

- [ ] Each pilot user completes their supervised first cycle on live pilot data, matched to their responsibility:
  - operating member: capture a cost obligation / record a contribution receipt / import a statement line set;
  - finance: reconcile, prepare checkpoint, raise/resolve exception;
  - OWNER: authorize an obligation, approve a correction;
  - all: find the exception queue, read a read model, drill a total to its posted lines.
- [ ] Terminology check: users can state the difference between commitment/called/contributed capital, cash vs realized result, allocation vs distribution, valuation vs realized gain (07_UX_INFORMATION_ARCHITECTURE.md §6 semantics).

### Initial UAT tasks (day 5)

- [ ] Register the Week 0 UAT subset from `05_UAT_ACCEPTANCE_MATRIX.md` (codes `S7-UAT-*`) and execute them; **do not accept** — acceptance belongs to Weeks 1–4 with live evidence.
- [ ] Go-live decision (PRM-10) recorded by `<CUSTOMER_APPROVER>`.

**Week 0 exit:** opening position posted and reconciled at zero variance; users trained; go-live decision recorded. Otherwise: fix and repeat; do not start Week 1.

---

## Weeks 1–3 — Operating weeks (repeated)

Gates covered: PRM-11 (daily), PRM-12 (weekly).

### Daily — operational capture (operating members)

- Same-day capture of material events: obligations, receipts/contributions, payments (recorded after banking execution), sector events, documents-as-references.
- Target metric (roadmap §9): material events linked to project and evidence/status ≥ 95%; events captured within 24h.
- End of day: exception queue reviewed; every new exception has an owner.

### Daily — exception triage (`<FINANCE_CONTROL_OWNER>`)

1. Read the exception queue (approvals waiting, unidentified/unreconciled cash, overdue calls/obligations, missing evidence, close blockers).
2. Classify severity (`LOW|MEDIUM|HIGH|CRITICAL`) per `SUPPORT_ESCALATION.md`; assign owner; set due date.
3. CRITICAL: same-day escalation record; security/tenancy suspicions go immediately to `docs/runbooks/CROSS_TENANT_OR_SECURITY_INCIDENT.md`.
4. Track aging: **unreconciled cash older than 7 days must be 0 at every week boundary** (roadmap pilot metric).

### Daily — bank reconciliation (finance)

- Import each pilot account's bank statement lines as they become available (S2 import; duplicate fingerprints refused automatically).
- Match lines to posted receipts/payments one-to-one through explicit reconciliation groups; unmatched lines stay visible as unreconciled — never force a match.
- Book and bank balances are always shown separately with reconciling items.

### Weekly — project/partner rollforward (`<FINANCE_CONTROL_OWNER>`, Friday close-out)

Run the full weekly checkpoint set per `06_RECONCILIATION_PROCEDURES.md`:

- [ ] Bank ↔ book per account → `PROJECT_CASH` checkpoint.
- [ ] Supplier obligation position → `SUPPLIER_OBLIGATION_POSITION`.
- [ ] Customer receivable position → `CUSTOMER_RECEIVABLE_POSITION` (if sales exist).
- [ ] Contributed capital → `CONTRIBUTED_CAPITAL`.
- [ ] Partner capital per participant → `PARTNER_CAPITAL`.
- [ ] Distribution payable/paid → `DISTRIBUTION_PAYABLE` / `DISTRIBUTION_PAID` (when applicable).
- [ ] Sign off every zero-variance checkpoint (signer ≠ preparer); open exceptions on any variance and resolve before sign-off.

**Weekly record:** week number, checkpoint ids, variances (all 0 or exceptions resolved), exceptions opened/closed, sign-offs. This record is the evidence for "four consecutive weekly reconciliations".

### Issue classification (all weeks)

| Class | Definition | Treatment | Deadline |
| --- | --- | --- | --- |
| CRITICAL | suspected tenant exposure; destructive change to posted fact; unreconciled cash with unknown cause; system unavailable | Immediate escalation; runbook per `07_INCIDENT_SUPPORT_MATRIX.md`; pilot clock decision by `<CUSTOMER_APPROVER>` | same day |
| HIGH | wrong posted transaction; failed close gate; statement variance unresolved > 7 days | Runbook; correction through reversal/repost | 2 business days |
| MEDIUM | single-row data error; missed capture; mapping question | Normal correction/training | within the week |
| LOW | terminology/UX confusion; cosmetic | Log for GA backlog | weekly review |

### Correction procedure (only these paths)

- Wrong posted transaction → `docs/runbooks/INCORRECT_POSTED_TRANSACTION.md` (linked reversal + replacement; posted facts are immutable).
- Wrong fact in a closed period → `docs/runbooks/CLOSED_PERIOD_CORRECTION.md`.
- Wrong opening row → `docs/runbooks/FAILED_OPENING_IMPORT.md` (reversal guard ordering applies).
- Failed allocation/distribution → `docs/runbooks/FAILED_ALLOCATION_OR_DISTRIBUTION.md`.
- Unreconciled cash → `docs/runbooks/UNRECONCILED_CASH.md`.
- **Never:** SQL edits on posted facts, deletions of evidence, maker/checker bypass, credential sharing (standing rules in `docs/runbooks/README.md`).

### Evidence capture (continuous)

Every material event, exception resolution, correction, checkpoint, and sign-off carries an evidence reference entered in `templates/pilot-evidence-register.csv`. An item without a reference is treated as incomplete at Week 4 review.

---

## Week 4 — Close, verify, accept, decide

Gates covered: PRM-12 (final week), PRM-13, PRM-14, PRM-15, PRM-16.

### Final weekly reconciliation (days 1–2)

- [ ] Fourth consecutive weekly checkpoint set recorded and signed off at variance 0 (exceptions, if any, resolved with evidence).
- [ ] Confirm the consecutive count: Weeks 1–4 all signed. Any gap → restart after resolution; do not backfill.

### Period close (days 2–3) — PRM-13

- [ ] Resolve close blockers: unreconciled lines, suspense/control balances, missing evidence/approvals, cut-off items.
- [ ] Run the close run; all ten gates PASS or APPROVED_EXCEPTION with evidence:
  `JOURNAL_BATCHES_BALANCED`, `BANK_RECONCILIATION_COVERAGE`, `SUSPENSE_CONTROL_ACCOUNTS`, `RECEIVABLE_PAYABLE_AGING`, `ASSET_SECTOR_ROLLFORWARDS`, `EVIDENCE_AND_APPROVALS`, `POSTING_CURRENCY_RULES`, `SECTOR_CUT_OFF`, `PARTNER_CAPITAL_ROLLFORWARD`, `CLOSE_REPORT_AND_EXCEPTIONS`.
- [ ] OWNER approves close; period becomes `CLOSED`; close snapshot stored (immutable, content-hashed).

### Investor/partner statement (day 3) — PRM-14

- [ ] If the period holds allocable realized result: allocation prepared from the approved close snapshot under the governing agreement version's rule basis; maker ≠ approver approves; distribution (if any) approved and paid as a record of the customer's banking process.
- [ ] Generate the investor statement from posted facts. Target metric: production time < 10 minutes after close approval.

### Independent recalculation (day 3)

- [ ] The customer's finance lead recalculates statement totals **outside Terranex** (their spreadsheet/accounting process) from the same source facts.
- [ ] Record `INVESTOR_STATEMENT_TOTAL` and `PARTNER_CAPITAL` checkpoints with the independent numbers. Acceptance: variance = 0. Any divergence → locate, correct the wrong side (product paths only), re-derive, re-checkpoint.

### Signed UAT (days 4–5) — PRM-15

- [ ] All mandatory scenarios from `05_UAT_ACCEPTANCE_MATRIX.md` executed with evidence; `<CUSTOMER_APPROVER>` accepts or rejects each (executor ≠ acceptor enforced by the product).
- [ ] Every rejection has a reason and a disposition (fix-and-rerun during pilot, or logged to the GA backlog with `<CUSTOMER_APPROVER>` agreement).
- [ ] Acceptance report `human_uat_status = ACCEPTED` verified from real task states.

### Unresolved issue review (day 5)

- [ ] Full issue register reviewed: zero unresolved CRITICAL security/data issues; every HIGH resolved or explicitly accepted in writing by `<CUSTOMER_APPROVER>` with a remediation date; MEDIUM/LOW logged to the GA backlog.

### Pilot exit decision (day 5) — PRM-16

Exit requires **all five** canonical Phase 4 gates, evidenced:

1. four consecutive weekly reconciliations signed off;
2. one period close approved;
3. accurate investor statement (zero-variance independent recalculation);
4. zero unresolved critical security/data issues;
5. buyer acceptance (signed UAT + written acceptance).

Outcome record: PASS → proceed to PRM-17 GA decision and commercial continuation (subscription renewal intent per roadmap §10); FAIL → extend pilot with a written remediation plan; the consecutive-reconciliation count rules still apply.

---

## Pilot metrics tracker (weekly snapshot)

| Metric (roadmap §9) | Target | W1 | W2 | W3 | W4 |
| --- | --- | --- | --- | --- | --- |
| Time to first configured real project | ≤ 2 business days after clean source data | measured in Week 0 | | | |
| Material events linked to project + evidence/status | ≥ 95% | | | | |
| Unreconciled cash older than 7 days | 0 at close | | | | |
| Partner statement production time | < 10 min after close approval | | | | |
| Statement variance vs independent calculation | 0 | | | | |
| Cross-tenant/security critical issues | 0 | | | | |
| Posted events changed destructively | 0 | | | | |
| Weekly active users in pilot roles | ≥ 80% of invited | | | | |
| Critical workflow completed without developer intervention | 100% | | | | |

A metric missed in any week gets a root-cause line in the weekly record; metrics never self-certify — each cell carries an evidence reference.

# 01 — Pilot Readiness Map

**Purpose:** translate `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md` into one dependency-driven operational sequence from the end of technical verification (S0–S7 merged and audited) through the first paid pilot and the GA decision.

**Conventions:**

- Owners use the responsibility titles defined in [`09_PILOT_ROLES_AND_RESPONSIBILITIES.md`](09_PILOT_ROLES_AND_RESPONSIBILITIES.md). Named people are placeholders (`<...>`) until the engagement fills them in, exactly as in `docs/runbooks/README.md`.
- "Minor units" means integer currency minor units (EGP piastres for the Egypt launch). Acceptance variance is **zero minor units** everywhere.
- Gate IDs `PRM-00`…`PRM-17` are stable references used by the other pack documents.

## Gate sequence

```text
PRM-00 verified main
  └─ PRM-01 deployment readiness
       └─ PRM-02 environment configuration
            └─ PRM-03 customer onboarding prerequisites
                 └─ PRM-04 source-data intake
                      └─ PRM-05 data-quality gate
                           └─ PRM-06 opening import
                                └─ PRM-07 opening reconciliation
                                     └─ PRM-08 user provisioning
                                          └─ PRM-09 operational rehearsal
                                               └─ PRM-10 controlled go-live
                                                    ├─ PRM-11 daily exception handling (continuous, Weeks 1–4)
                                                    └─ PRM-12 weekly reconciliation (×4, Weeks 1–4)
                                                         └─ PRM-13 first period close
                                                              └─ PRM-14 investor statement verification
                                                                   └─ PRM-15 signed UAT
                                                                        └─ PRM-16 four-week pilot exit
                                                                             └─ PRM-17 GA decision
```

PRM-11 and PRM-12 run in parallel every pilot week; PRM-13 requires the final (Week 4) reconciliation of PRM-12. PRM-08 depends on PRM-03 (the customer OWNER already exists) but is sequenced after PRM-07 because full operating-user provisioning is only justified once the opening position is trustworthy.

---

## PRM-00 — Verified main

- **Owner:** Terranex engineering (`<ENGINEERING_ONCALL>`).
- **Input:** the audit workstream (Phase 2C/2D, security and financial-integrity remediation) finished and merged to `main`.
- **Required evidence:** merge commit SHA on `main`; green CI run on that SHA (`greenfield-ci.yml`: application and database jobs); canonical database gate `npm run db:test` including the S7 end-to-end rehearsal (`supabase/tests/27_s7_end_to_end_rehearsal.sql`) and backup/restore rehearsal (`supabase/tests/26_s7_backup_restore.sh`).
- **Pass condition:** all S0–S7 suites pass on `main` unchanged; no open critical security or data-integrity finding from the audits remains unresolved.
- **Fail condition:** any audit finding unresolved, or any red gate on the merge commit.
- **Remediation:** stays inside the audit workstream until closed; this readiness pack does not patch audit findings.
- **Dependency:** none (start of chain).

## PRM-01 — Deployment readiness

- **Owner:** Terranex engineering (`<ENGINEERING_ONCALL>`).
- **Input:** verified main (PRM-00); the checklist in [`08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md`](08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md).
- **Required evidence:** completed checklist with every item marked automatic-pass, operator-done, or sign-off recorded; a production build of the exact commit; migration replay from empty proven on the pilot Supabase project.
- **Pass condition:** every checklist item is PASS or SIGNED-OFF by its named owner; no item is "not verified".
- **Fail condition:** any checklist item failed, skipped, or claimed without evidence.
- **Remediation:** fix the failing prerequisite; re-run the affected checklist section; record the re-run.
- **Dependency:** PRM-00.

## PRM-02 — Environment configuration

- **Owner:** Terranex engineering (`<ENGINEERING_ONCALL>`) with `<PILOT_OPS_OWNER>` witnessing.
- **Input:** dedicated pilot Supabase project; application deployment target.
- **Required evidence:** recorded environment variable names and their configured state (names only, never values); migration state listing for the pilot project; Auth configuration snapshot reference; backup schedule reference for the pilot project.
- **Pass condition:** `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` point at the pilot project; all migrations applied on the pilot project; no service-role credential exists anywhere in the browser-reachable code path (this is the shipped product behavior — verify, do not add one).
- **Fail condition:** wrong project reference, missing migration, or any secret observed in logs/browser bundle.
- **Remediation:** reconfigure from `08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md`; never fix by hand-editing database state.
- **Dependency:** PRM-01.

## PRM-03 — Customer onboarding prerequisites

- **Owner:** `<PILOT_OPS_OWNER>` with the customer's economic buyer.
- **Input:** the commercial handoff agreement from [`10_COMMERCIAL_HANDOFF_REQUIREMENTS.md`](10_COMMERCIAL_HANDOFF_REQUIREMENTS.md) fully agreed and signed.
- **Required evidence:** signed pilot engagement reference; named `<CUSTOMER_APPROVER>`; selected pilot project(s) recorded; opening freeze date agreed; data preparation responsibility matrix agreed.
- **Pass condition:** every item in `10_COMMERCIAL_HANDOFF_REQUIREMENTS.md` is agreed in writing; the customer OWNER account exists in the pilot organization and has signed in successfully.
- **Fail condition:** any handoff item unresolved (especially: no named acceptance authority, no freeze date, or disagreement about who prepares source data).
- **Remediation:** do not start data intake; resolve commercially. Unresolved legal/accounting items require professional review, not improvisation.
- **Dependency:** PRM-02.

## PRM-04 — Source-data intake

- **Owner:** customer finance lead (preparation) with `<PILOT_OPS_OWNER>` (contract check).
- **Input:** the intake contract in [`02_DATA_INTAKE_CONTRACT.md`](02_DATA_INTAKE_CONTRACT.md); the customer's own trial balance, agreements, and records as of the freeze date.
- **Required evidence:** one intake delivery per dataset with its source reference; the completed `templates/source-data-coverage-tracker.csv` row per dataset; control totals declared by the customer in writing.
- **Pass condition:** every mandatory dataset for the selected pilot project is delivered with declared control totals; nothing mandatory is missing.
- **Fail condition:** a mandatory dataset missing, undated, or delivered without a declared control total.
- **Remediation:** return the dataset for re-preparation; record the rejection reason in the coverage tracker. Do not proceed on partial data.
- **Dependency:** PRM-03.

## PRM-05 — Data-quality gate

- **Owner:** `<PILOT_OPS_OWNER>` (execution), customer finance lead (resolution of source errors).
- **Input:** delivered datasets from PRM-04.
- **Required evidence:** completed validation worksheet per dataset (per `02_DATA_INTAKE_CONTRACT.md` validation rules); rejected/queried item list returned to the customer with their written answers.
- **Pass condition:** zero unresolved rejection conditions; the customer confirms in writing that the delivered data is complete as of the freeze date; declared totals internally consistent.
- **Fail condition:** any open rejection condition, or the customer declines to confirm completeness.
- **Remediation:** customer corrects at the source and re-delivers; the quality gate repeats. Paid data-cleaning, if needed, follows roadmap risk register item "Customer source data is unreliable" — never silently absorb bad data into the opening position.
- **Dependency:** PRM-04.

## PRM-06 — Opening import

- **Owner:** import maker prepares; customer OWNER approves (product-enforced maker ≠ approver).
- **Input:** data-quality-passed opening datasets; the procedure in [`03_OPENING_BALANCE_CONTROL_PACK.md`](03_OPENING_BALANCE_CONTROL_PACK.md); the six S7 opening mapping codes only.
- **Required evidence:** staged import with source file name and SHA-256 checksum; validation outcome with zero rejected rows; declared and computed control totals; approval record with posting date inside an OPEN accounting period.
- **Pass condition:** import reaches `POSTED`; declared debit total = computed debit total, declared credit total = computed credit total, debits = credits, all to the minor unit; rejected-row count = 0.
- **Fail condition:** any rejected row, any non-zero control-total variance, or approval refused (including maker/checker refusal).
- **Remediation:** `docs/runbooks/FAILED_OPENING_IMPORT.md`. A failed import is fixed by correcting the source rows and staging a corrected import, or by explicit `REJECTED` with reason — never by editing posted facts.
- **Dependency:** PRM-05.

## PRM-07 — Opening reconciliation

- **Owner:** `<FINANCE_CONTROL_OWNER>` (preparation), a different authorized signer (sign-off).
- **Input:** posted opening import (PRM-06); the customer's signed source trial balance as of the freeze date.
- **Required evidence:** S7 reconciliation checkpoints recorded for the opening position (`PROJECT_CASH`, `CONTRIBUTED_CAPITAL`, `SUPPLIER_OBLIGATION_POSITION`, `CUSTOMER_RECEIVABLE_POSITION`, `DISTRIBUTION_PAYABLE` as applicable) with external values taken from the signed source trial balance; sign-off records.
- **Pass condition:** every recorded checkpoint has variance = 0 (`MATCHED`) and is signed off by a signer who is not the preparer; zero open exceptions.
- **Fail condition:** any non-zero variance or any open exception at sign-off time (the product refuses sign-off while an exception is open).
- **Remediation:** follow [`03_OPENING_BALANCE_CONTROL_PACK.md`](03_OPENING_BALANCE_CONTROL_PACK.md) §8 (variance handling): correct via linked reversal or a corrected import per runbook, then record a **new** checkpoint — checkpoints are never edited.
- **Dependency:** PRM-06.

## PRM-08 — User provisioning

- **Owner:** customer OWNER (invitations), `<PILOT_OPS_OWNER>` (verification).
- **Input:** the responsibility model in [`09_PILOT_ROLES_AND_RESPONSIBILITIES.md`](09_PILOT_ROLES_AND_RESPONSIBILITIES.md); the agreed pilot user list.
- **Required evidence:** membership list of the pilot organization with each user's operational responsibility; confirmation that at least one active OWNER exists (product-enforced guard); confirmation that every invited user signed in at least once.
- **Pass condition:** every operational responsibility in the pilot plan is assigned to a named, active member; ≥ 80% of invited operating users have signed in (roadmap pilot metric: weekly active users in pilot roles).
- **Fail condition:** an unassigned material responsibility, or a user unable to sign in.
- **Remediation:** re-invite or fix Auth enrollment; if access must be removed, use the membership status command with reason (immediate revocation, per S7).
- **Dependency:** PRM-07 (opening position trustworthy), PRM-03 (customer OWNER exists).

## PRM-09 — Operational rehearsal

- **Owner:** `<PILOT_OPS_OWNER>` (facilitation) with all customer pilot users.
- **Input:** provisioned users (PRM-08); the Week 0 plan in [`04_PILOT_RUNBOOK_WEEKS_0_TO_4.md`](04_PILOT_RUNBOOK_WEEKS_0_TO_4.md).
- **Required evidence:** latest recorded technical rehearsals (`END_TO_END_CYCLE`, `BACKUP_RESTORE`, `ACCESS_REVOCATION`) as reported by the acceptance report read model; completed operator training record; executed (not yet accepted) UAT tasks for the Week 0 set.
- **Pass condition:** the three technical rehearsals are recorded and current for the deployed release; every pilot user completes their supervised first cycle (capture → approve → post → reconcile on live pilot data); every planned Week 0 UAT task has been executed with evidence.
- **Fail condition:** any rehearsal missing/failed for the deployed release, or any user unable to complete their supervised cycle.
- **Remediation:** fix environment/training gaps and repeat; a failing rehearsal is an engineering incident (`docs/runbooks/FAILED_DEPLOYMENT_OR_MIGRATION.md` where deployment-related).
- **Dependency:** PRM-08.

## PRM-10 — Controlled go-live

- **Owner:** `<PILOT_OPS_OWNER>` with `<CUSTOMER_APPROVER>`.
- **Input:** PRM-09 passed; written go-live decision from `<CUSTOMER_APPROVER>`.
- **Required evidence:** go-live decision record (date, decision, participants); the daily and weekly operating cadence from `04_PILOT_RUNBOOK_WEEKS_0_TO_4.md` scheduled; support channel and escalation owners confirmed live (`SUPPORT_ESCALATION.md` placeholders filled for this engagement).
- **Pass condition:** the customer starts capturing real daily operations in Terranex from the agreed go-live date; no fallback decision ("stay on spreadsheets only") was taken.
- **Fail condition:** the customer declines go-live, or support ownership is not confirmed.
- **Remediation:** resolve the blocking concern; go-live is re-decided explicitly — it never happens by drift.
- **Dependency:** PRM-09.

## PRM-11 — Daily exception handling (Weeks 1–4, continuous)

- **Owner:** customer operating members (capture), `<FINANCE_CONTROL_OWNER>` (triage).
- **Input:** daily operational capture per the runbook; the exception queue.
- **Required evidence:** daily exception digest with owner, severity (`LOW|MEDIUM|HIGH|CRITICAL`), and resolution outcome per exception; dismissal without reason is impossible by product design.
- **Pass condition:** every exception raised has an owner and a disposition; no unreconciled cash older than 7 days remains at any week boundary (roadmap pilot metric: 0 at close); no CRITICAL exception older than 24h without an escalation record.
- **Fail condition:** unowned exceptions, or aged unreconciled cash.
- **Remediation:** the relevant runbook (`07_INCIDENT_SUPPORT_MATRIX.md` maps situations to runbooks); severity per `SUPPORT_ESCALATION.md`.
- **Dependency:** PRM-10.

## PRM-12 — Weekly reconciliation (×4, Weeks 1–4)

- **Owner:** `<FINANCE_CONTROL_OWNER>` (preparation), independent signer (sign-off).
- **Input:** the procedures in [`06_RECONCILIATION_PROCEDURES.md`](06_RECONCILIATION_PROCEDURES.md); the customer's own weekly records (bank statements, cash book, partner records).
- **Required evidence:** one S7 reconciliation checkpoint set per week with external source references and evidence references; sign-off per checkpoint; exceptions with resolutions where variances occurred.
- **Pass condition:** for each of four consecutive weeks, every applicable checkpoint is recorded with variance = 0 (`MATCHED`) — or every non-zero variance has a resolved exception and a corrected re-checkpoint — and is signed off.
- **Fail condition:** any week with an unsigned checkpoint or an open exception at week end; a missed week breaks the consecutive count, which restarts.
- **Remediation:** variance handling per `06_RECONCILIATION_PROCEDURES.md`; if the week is lost, restart the four-week count — do not backfill sign-offs for weeks that were not actually reconciled.
- **Dependency:** PRM-10; each week depends on the previous week being signed off.

## PRM-13 — First period close

- **Owner:** close preparer (customer finance), customer OWNER (close approval — product-enforced).
- **Input:** Week 4 reconciliation complete (PRM-12); the close procedure in [`04_PILOT_RUNBOOK_WEEKS_0_TO_4.md`](04_PILOT_RUNBOOK_WEEKS_0_TO_4.md) §Week 4.
- **Required evidence:** close run with all ten gate results (`JOURNAL_BATCHES_BALANCED`, `BANK_RECONCILIATION_COVERAGE`, `SUSPENSE_CONTROL_ACCOUNTS`, `RECEIVABLE_PAYABLE_AGING`, `ASSET_SECTOR_ROLLFORWARDS`, `EVIDENCE_AND_APPROVALS`, `POSTING_CURRENCY_RULES`, `SECTOR_CUT_OFF`, `PARTNER_CAPITAL_ROLLFORWARD`, `CLOSE_REPORT_AND_EXCEPTIONS`); close snapshot; approved exceptions where a gate result is `APPROVED_EXCEPTION`.
- **Pass condition:** every gate PASS or `APPROVED_EXCEPTION` with evidence; close approved by the OWNER; period `CLOSED`.
- **Fail condition:** any gate FAIL without an approved exception; `BANK_RECONCILIATION_COVERAGE` FAIL with unreconciled lines is never approvable by decree — resolve per `docs/runbooks/UNRECONCILED_CASH.md`.
- **Remediation:** resolve blockers, re-run the close run; corrections in already-closed periods use `docs/runbooks/CLOSED_PERIOD_CORRECTION.md`.
- **Dependency:** PRM-12 (Week 4).

## PRM-14 — Investor statement verification

- **Owner:** `<FINANCE_CONTROL_OWNER>` (preparation), independent verifier (customer side), `<CUSTOMER_APPROVER>` (acceptance).
- **Input:** closed period (PRM-13); the S5 allocation and distribution facts; the partner capital rollforward.
- **Required evidence:** independent recalculation of the statement totals outside Terranex (customer's own spreadsheet/accounting process) with its source reference; `INVESTOR_STATEMENT_TOTAL` and `PARTNER_CAPITAL` checkpoints comparing it to the derived Terranex totals; statement totals traceable to posted lines.
- **Pass condition:** variance = 0 on every statement checkpoint; the independent recalculation is recorded with evidence; the partner capital rollforward equation holds exactly: Closing = Opening + Contributions + AllocatedIncome − AllocatedLoss − Distributions + OtherApprovedCapitalAdjustments.
- **Fail condition:** any non-zero variance, or a statement figure that cannot be traced to posted lines.
- **Remediation:** locate the divergence (Terranex posting vs external calculation); correct the wrong side through the product's reversal/correction paths only; re-derive and re-checkpoint.
- **Dependency:** PRM-13.

## PRM-15 — Signed UAT

- **Owner:** customer executing users (execution), `<CUSTOMER_APPROVER>` (acceptance — product-enforced executor ≠ acceptor).
- **Input:** the registered UAT task set from [`05_UAT_ACCEPTANCE_MATRIX.md`](05_UAT_ACCEPTANCE_MATRIX.md); all execution evidence.
- **Required evidence:** every registered task executed with an evidence reference; acceptance or rejection recorded per task by a person other than the executor; the acceptance report's `human_uat_status` computed from real task states.
- **Pass condition:** every mandatory UAT task is `ACCEPTED`; every `REJECTED` task has a recorded reason and an agreed disposition; `human_uat_status = ACCEPTED` for the pilot project.
- **Fail condition:** any mandatory task still `PENDING`/`EXECUTED`, or any rejection without disposition.
- **Remediation:** rejected scenarios are fixed as product issues or training gaps and re-executed; nothing in the system can self-accept a task — do not work around that.
- **Dependency:** PRM-14.

## PRM-16 — Four-week pilot exit

- **Owner:** `<CUSTOMER_APPROVER>` (buyer acceptance) with `<PILOT_OPS_OWNER>`.
- **Input:** all prior gates; the exit checklist below.
- **Required evidence:** the pilot exit record naming each satisfied gate with its evidence references.
- **Pass condition — exactly the canonical Phase 4 exit gates:**
  1. four consecutive weekly reconciliations signed off (PRM-12);
  2. one period close approved (PRM-13);
  3. accurate investor statement verified at zero variance (PRM-14);
  4. zero unresolved critical security/data issues (PRM-11 + audit stream findings);
  5. buyer acceptance recorded (PRM-15 + explicit written acceptance).
- **Fail condition:** any of the five unmet.
- **Remediation:** continue pilot operation (extended weeks, restarted reconciliation count) until all five are met; the roadmap allows no partial exit.
- **Dependency:** PRM-11–PRM-15.

## PRM-17 — GA decision

- **Owner:** Terranex founder/product owner with the economic buyer's renewal signal.
- **Input:** PRM-16 passed; the commercial learning-plan signals from roadmap §10 (setup/pilot fee paid; users capture data without the founder operating for them; management used a Terranex statement/exception for a real decision; subscription renewal intent).
- **Required evidence:** pilot exit record; pilot metrics assessment against roadmap §9 targets; the first GA work package selected from [`11_GA_READINESS_BACKLOG.md`](11_GA_READINESS_BACKLOG.md).
- **Pass condition:** explicit written decision to enter Phase 5, with the first work package named.
- **Fail condition:** exit gates passed but learning-plan signals negative (e.g. onboarding required custom code) — in that case roadmap §10 says: pause expansion, productize first (see WP1/WP5 in the GA backlog).
- **Remediation:** targeted GA backlog packages before any second customer or second sector.
- **Dependency:** PRM-16.

---

## Gate-to-evidence crosswalk

| Gate | Primary product evidence | Primary pack document |
| --- | --- | --- |
| PRM-00 | CI green run on `main`; rehearsal facts | audit workstream output |
| PRM-01/02 | checklist completion record | `08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md` |
| PRM-03 | signed engagement reference | `10_COMMERCIAL_HANDOFF_REQUIREMENTS.md` |
| PRM-04/05 | coverage tracker, validation worksheets | `02_DATA_INTAKE_CONTRACT.md` |
| PRM-06 | `s7_opening_imports` POSTED record | `03_OPENING_BALANCE_CONTROL_PACK.md` |
| PRM-07 | `s7_reconciliation_checkpoints` sign-offs | `03_OPENING_BALANCE_CONTROL_PACK.md` |
| PRM-08 | membership list | `09_PILOT_ROLES_AND_RESPONSIBILITIES.md` |
| PRM-09 | `s7_pilot_rehearsals`, executed UAT tasks | `04_PILOT_RUNBOOK_WEEKS_0_TO_4.md` |
| PRM-10 | go-live decision record | `04_PILOT_RUNBOOK_WEEKS_0_TO_4.md` |
| PRM-11 | exception queue records | `07_INCIDENT_SUPPORT_MATRIX.md` |
| PRM-12 | weekly checkpoint sets | `06_RECONCILIATION_PROCEDURES.md` |
| PRM-13 | `close_runs` + ten gates + snapshot | `04_PILOT_RUNBOOK_WEEKS_0_TO_4.md` |
| PRM-14 | `INVESTOR_STATEMENT_TOTAL` checkpoint | `06_RECONCILIATION_PROCEDURES.md` |
| PRM-15 | `s7_uat_tasks` ACCEPTED set | `05_UAT_ACCEPTANCE_MATRIX.md` |
| PRM-16 | pilot exit record | this document |
| PRM-17 | GA decision record | `11_GA_READINESS_BACKLOG.md` |

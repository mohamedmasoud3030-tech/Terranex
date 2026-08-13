# 10 — Commercial Pilot Handoff Requirements

**Purpose:** what must be agreed in writing between Terranex and the pilot customer **before** the paid pilot starts (gate PRM-03). Everything here stays inside the shipped product boundary (S0–S7) and the canonical product documents. This document prepares the agreement; it is **not** the agreement and contains no legal promises — items requiring professional legal/accounting review are flagged `[LEGAL]` / `[ACCOUNTING]` and must be resolved by qualified professionals, not improvised here.

**Form:** each requirement has a statement, the product fact it rests on, and the record that proves agreement. Records go to the engagement operations plan (customer data stays with the customer; identifiers only).

## H-01 — Pilot scope

- **Statement:** the pilot covers the shared investment/finance/control core plus the Real Estate sector pack only, operated on the customer's real project data for four operating weeks after a preparation week (Week 0).
- **Rests on:** roadmap Phase 4; ADR 0009 scope (no second sector, no generic importer, no workflow engine, no second ledger).
- **Agreement record:** scope paragraph naming exactly what is in and out; out-of-scope list mirrors ADR 0009 §9 (agriculture/livestock, advanced waterfalls/carry/preferred return, tax engine, statutory-accounting claims, native bank execution, marketplace, billing features, AI, report builder, generic accounting integration, offline/PWA).

## H-02 — Selected Real Estate project(s)

- **Statement:** one or more named projects (name + customer internal reference), all EGP reporting currency, all Real Estate sector.
- **Rests on:** product constraints (sector `REAL_ESTATE` and reporting currency `EGP` are the only values in v1).
- **Agreement record:** project list; a project needing another currency or sector is out of scope for this pilot and deferred per the canonical documents.

## H-03 — Data preparation responsibility

- **Statement:** the customer prepares all source datasets per `02_DATA_INTAKE_CONTRACT.md` from their own systems; Terranex validates and operates the intake but does not author the customer's books. If the customer needs Terranex to perform data cleaning/construction, that is a separately priced activity decided explicitly (roadmap risk register: "paid data-cleaning gate"), never silent work.
- **Rests on:** intake contract; roadmap risk "Customer source data is unreliable".
- **Agreement record:** responsibility matrix (customer prepares / Terranex validates / customer resolves rejections) with named customer finance lead.

## H-04 — Opening-date freeze

- **Statement:** one freeze date per pilot project; all opening positions as of that date; source extracts frozen thereafter (corrections produce new dated extracts).
- **Rests on:** `03_OPENING_BALANCE_CONTROL_PACK.md` §2.
- **Agreement record:** freeze date(s) and the sign-off that they will not move silently; any change is a written decision with consequences for the reconciliation calendar.

## H-05 — No native money movement

- **Statement:** Terranex never initiates, holds, or moves money. Payments and distributions in the pilot are **records** of transactions the customer executes through their own banking process; the product wording is "record payment", never "send/hold money".
- **Rests on:** product charter §8 boundaries; ADR 0009 §9 ("Payments remain records of the customer's existing banking process — Terranex does not move money"); roadmap Phase 4.
- **Agreement record:** explicit clause; the customer confirms understanding in writing. `[LEGAL]` — the clause wording itself must be professionally reviewed; this pack supplies the product fact, not the legal text.

## H-06 — Customer retains existing banking process

- **Statement:** the customer keeps their current banking relationships, authorization procedures, and controls unchanged for the pilot; Terranex integrates with them only by recording outcomes (statements imported as external facts; payments recorded after execution).
- **Rests on:** S2 bank reconciliation design (statements are immutable external facts; matching never posts economics by itself).
- **Agreement record:** statement that banking execution stays with the customer; bank-statement delivery cadence agreed (weekly minimum, per R-01).

## H-07 — Source-document responsibility

- **Statement:** original documents (contracts, title papers, invoices, statements, resolutions) remain in the customer's systems under the customer's custody and retention policy. Terranex stores **evidence references** (identifiers) linked to facts, not the documents. Retrieval during pilot checks is the customer's obligation.
- **Rests on:** standing rules in `docs/runbooks/README.md` (documents live in the customer's systems); v1 has no document storage.
- **Agreement record:** custody statement + evidence-register convention (`templates/pilot-evidence-register.csv`). `[LEGAL]` — document retention obligations may be regulated; professional review required.

## H-08 — Reconciliation responsibility

- **Statement:** weekly reconciliation is a joint duty with fixed sides: the customer supplies external control totals from their own records (evidence only); Terranex derives its side from posted facts inside the database; `<FINANCE_CONTROL_OWNER>` prepares checkpoints; an independent signer signs. Variance acceptance is zero minor units.
- **Rests on:** ADR 0009 §2 (external numbers never influence Terranex balances); `06_RECONCILIATION_PROCEDURES.md`.
- **Agreement record:** responsibility split + weekly calendar for Weeks 1–4 + named signers (preparer ≠ signer).

## H-09 — Support channel

- **Statement:** one inbound channel for pilot reports (agreed medium), staffed per `docs/runbooks/SUPPORT_ESCALATION.md`, with `<PILOT_OPS_OWNER>` as first response. Every report becomes a triaged record with severity, owner, and disposition.
- **Rests on:** `docs/runbooks/SUPPORT_ESCALATION.md`.
- **Agreement record:** channel, operating hours, and response expectations. `[LEGAL]` — response-time commitments become service-level terms; for the pilot, record what is actually committed, and route formal SLA policy to GA backlog WP2.

## H-10 — Incident escalation

- **Statement:** escalation owners named before go-live: `<PILOT_OPS_OWNER>`, `<FINANCE_CONTROL_OWNER>`, `<ENGINEERING_ONCALL>`, `<SECURITY_OWNER>`, `<CUSTOMER_APPROVER>` — the same placeholders the runbooks use. Security/tenancy suspicions escalate immediately at highest severity.
- **Rests on:** `docs/runbooks/README.md` escalation table; `CROSS_TENANT_OR_SECURITY_INCIDENT.md`.
- **Agreement record:** filled escalation table with real names/contacts; communication rules from `07_INCIDENT_SUPPORT_MATRIX.md` (what may/may not be promised).

## H-11 — Acceptance authority

- **Statement:** exactly one named customer person (`<CUSTOMER_APPROVER>`) holds acceptance authority: UAT acceptance, weekly reconciliation summary sign-off witness, and the pilot exit acceptance. They must be an OWNER in the product (acceptance acts are OWNER-scoped or must differ from executors/preparers).
- **Rests on:** product UAT rules (executor ≠ acceptor); gate PRM-15/PRM-16.
- **Agreement record:** named authority + deputy rule (if the authority is unavailable, acceptance waits; nobody else signs).

## H-12 — Pilot exit criteria

- **Statement:** the pilot exits only on the five canonical Phase 4 gates: (1) four consecutive signed weekly reconciliations; (2) one approved period close; (3) accurate investor statement (zero-variance independent recalculation); (4) zero unresolved critical security/data issues; (5) buyer acceptance.
- **Rests on:** roadmap §5 Phase 4 exit; `04_PILOT_RUNBOOK_WEEKS_0_TO_4.md` Week 4.
- **Agreement record:** exit criteria verbatim + the consequence of each outcome (pass → commercial continuation/renewal intent; fail → written extension plan; the consecutive-week count rules apply unchanged).

## Professional-review flags (must be resolved before signature)

| Item | Why it needs a professional |
| --- | --- |
| `[LEGAL]` Pilot agreement text, liability, and warranty wording | Legal counsel; the charter defines the product boundary (private B2B operational system, no public solicitation, no custody) — the contract must reflect it exactly |
| `[LEGAL]` Customer data processing and retention terms | Roadmap operations release gate requires approved terms; Egyptian regulatory context (FRA boundaries) is a legal determination |
| `[ACCOUNTING]` Treatment of the customer's statutory books vs the Terranex subledger | Qualified accountant: Terranex is an investment/operational subledger; the statutory GL stays external in v1 (05_FINANCE_AND_ACCOUNTING.md §1) |
| `[ACCOUNTING]` Opening accounting-policy choices embedded in the trial balance | The customer's accountant owns classification/policy; the product records evidence for policy application and claims no IFRS compliance by itself |
| `[LEGAL]` Setup/pilot fee and subscription terms | Commercial experiment per charter §9; pricing numbers are commercial decisions, not product requirements |

## What this document deliberately does not do

- No guarantee of results, returns, or savings ("calculated return" is never a "promised return"; valuations are management estimates).
- No claim that a production restore has occurred or that recovery objectives have been met (see `08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md` §9).
- No commitment of features beyond S0–S7; anything else is GA backlog (`11_GA_READINESS_BACKLOG.md`) and not pilot scope.

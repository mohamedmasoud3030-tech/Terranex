# 12 — Pre-Pilot Activation & Real-Project Intake Status

**Purpose:** the single consolidated record of where Terranex stands at the pre-pilot boundary — environment readiness, the provisioning boundary for the isolated pilot Supabase project, real-project intake readiness, and the exact values still required from outside the repository. It classifies every required environment value and lists every still-missing customer/operator value **by name only**.

**Status:** this is a preparation record. **Nothing here activates, deploys, or imports anything.** No pilot Supabase project has been provisioned, no customer value is recorded, and no canonical delivery exit (Phase 2 / Phase 3 / Phase 4) is marked passed. Where this document and a canonical Greenfield document or an earlier pack file disagree, the canonical source wins.

**Standing rules apply:** zero-minor-unit acceptance, names-only for secrets, no customer data in this repository, no self-advancing human gates, no service-role credential in any browser path.

---

## 1. Environment readiness — required values classification

The shipped application consumes **exactly two** environment variables (see `.env.example` and `src/shared/supabase/env.ts`). Everything else is infrastructure the operator supplies outside this repository.

| # | Required value | Class | Meaning and state |
| --- | --- | --- | --- |
| 1 | `NEXT_PUBLIC_SUPABASE_URL` | **B** | Required but missing. Value can only exist once a dedicated pilot Supabase project is provisioned (source is **C** — operator/external infrastructure). |
| 2 | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | **B** | Required but missing. Publishable (browser-safe) key of that same pilot project; still configured per environment, never hardcoded. Source is **C**. |
| 3 | Dedicated pilot Supabase project (isolated, empty or migrations-only) | **C** | External infrastructure dependency. **Does not exist yet.** Must be a dedicated project, never a shared/dev project. |
| 4 | Supabase Auth (email sign-in) configuration on the pilot project | **C** | Operator config on the pilot project; no customer user exists yet. |
| 5 | Application deployment target (Next.js host, HTTPS, agreed domain/subdomain) | **C** | Operator decision (architecture decision A-001: one deployable unit). Not chosen. |
| 6 | Secrets location, access restriction, rotation procedure | **C** | Operator-supplied provider; this repository stores none. |
| 7 | Scheduled logical backups + named owner + RPO/RTO agreement | **C/S** | Operator + professional review. The repository rehearsal (`26_s7_backup_restore.sh`) is **not** the production backup policy. |
| 8 | Error monitoring / alerting path + named on-call | **C/S** | Operator tooling choice; v1 ships no built-in monitor. |
| 9 | Service-role key in any browser path | **D** | **Not required — and must never be added.** The product is publishable-key-only by design; verify absence, do not introduce one. |

**GitHub Actions secrets:** CI (`greenfield-ci.yml`) consumes only build-time placeholders and requires **no** repository secret today. No deployment workflow exists in the repository. Pilot Supabase credentials, when provisioned, belong to the operator's secret manager outside this repository — never in repository files or in chat. (At the time of this record, repository secrets could not be enumerated by the executing agent — HTTP 403 on the secrets API — so the presence/absence of any operator-added secret is recorded as **unverified**, not as a configured value.)

**PRM-01 / PRM-02 outcome:** `NOT_STARTED`. The `08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md` sign-off block remains `(pending)`. This is honest: the pilot environment does not exist, so no checklist item is claimed as evidenced.

---

## 2. Provisioning boundary (everything prepared up to the external credential)

The repository already contains every artifact needed to bring up an isolated pilot database **up to the point where external credentials are required**. The operator must:

1. Provision a dedicated Supabase project (PostgreSQL 16) for the pilot. External act.
2. Replay the complete schema **from migrations only**, never by hand: run the canonical database gate `bash scripts/db-test.sh` (or `npm run db:test`) against the pilot project's PostgreSQL — every ordered migration under `supabase/migrations/*.sql` applies in order, and every verification suite under `supabase/tests/*` runs. No ad-hoc schema reconstruction.
3. Capture the migration-state listing as PRM-02 evidence (which migrations, in which order).
4. Verify the authorization boundary on the pilot project — all covered by existing suites, re-demonstrated per engagement:
   - default-deny RLS and two-tenant isolation (`01_s0_isolation.sql`, plus S7 re-assertions);
   - OWNER/MEMBER boundary, maker ≠ checker, last-active-owner guard, immediate access revocation (`23_s7_pilot_hardening.sql`, `24_s7_concurrency.sh`);
   - required RPCs exercised through the same suites (no new RPC is required — S0–S7 suites call them);
   - **no browser client holds service-role access** — the shipped client is publishable-key-only; verify by inspection of `src/shared/supabase/*` and the built bundle, not by adding a key.
5. Verify financial posting and period-close controls on the pilot project (`16_s6_period_close.sql`, `17_s6_close_concurrency.sh`, `28_phase2c_financial_integrity.sql`).
6. Verify the S7 import path (`23_s7_pilot_hardening.sql`, `24_s7_concurrency.sh`, `27_s7_end_to_end_rehearsal.sql`).
7. Configure `.env.local` on the deployment target with the two names from §1 (values supplied by the operator's secret mechanism, never committed).
8. Run the release smoke test per `08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md` §14 **before any customer data entry**.

**Boundary statement:** the repository is ready up to and including step 7's configuration point. Steps 1 (project provisioning) and the credential values are the external infrastructure dependency; nothing else blocks technical activation. No pilot environment was actually reached in this execution, and none is claimed.

---

## 3. Real-project intake readiness

The existing intake contract (`02_DATA_INTAKE_CONTRACT.md`) was re-verified against the S0–S7 data needs and is **complete**. Coverage:

| Dataset | Covers | S0–S7 need |
| --- | --- | --- |
| DS-01 Organization / DS-02 Projects | tenant + project shell | S0 |
| DS-03 Parties / DS-04 Agreements / DS-05 Commitments / DS-06 Calls / DS-07 Contributions | terms & funding | S1 |
| DS-08 Cash accounts / DS-10 Payables / DS-16 Bank statements | cost & cash | S2 |
| DS-11 Assets/parcels / DS-12 Acquisitions / DS-13 Development costs | real-estate operations | S3 |
| DS-14 Sales & dispositions | revenue & realized result | S4 |
| DS-15 Historical distributions | allocation & distribution | S5 |
| DS-09 Opening balances (six locked mapping codes) | controlled opening import | S7 |
| DS-17 Supporting documents (evidence references) | evidence across all slices | all |

The binding intake sequence in `02_DATA_INTAKE_CONTRACT.md` (§"Intake sequence") matches the S0→S1→S2→S3→S7 product order, and the six locked mapping codes / nine checkpoint codes / ten close gates are consistent with the migrations (verified by `scripts/pilot-readiness/check-readiness-pack.sh`).

**Result:** no genuinely required Terranex field is missing from the intake contract. **No contract change was required** in this execution. Every balance that cannot enter through an existing S0–S7 command is already designated EVIDENCE-ONLY and stays in the customer's systems. There is no second import engine and none is added.

The blank intake worksheets already exist and are header-only: `templates/opening-import-worksheet.csv`, `templates/source-data-coverage-tracker.csv`, `templates/pilot-evidence-register.csv`.

---

## 4. Missing values inventory (names only — never fabricated)

Every value below is **C** (external / customer / operator supplied). None is authorized or recorded. Each is listed with the exact gate it blocks. Until it exists, the named gate stays pending — this is a dependency, not a defect.

| Missing value (exact name) | Class | Blocks |
| --- | --- | --- |
| `CUSTOMER_NAME` / `LEGAL_ENTITY_NAME` | C | DS-01 organization; PRM-03 engagement |
| `CUSTOMER_OWNER_USER` / `CUSTOMER_APPROVER` / `CUSTOMER_EMAIL` | C | PRM-03 engagement; PRM-08 user provisioning; PRM-15 UAT |
| `REAL_FREEZE_DATE` | C | PRM-03 engagement; PRM-04 intake delivery |
| `SIGNED_CONTROL_TOTALS` | C | PRM-04/PRM-05 data quality; PRM-06 import; PRM-07 reconciliation |
| `CUSTOMER_SOURCE_FILES` | C | PRM-04 intake delivery |
| `CUSTOMER_OPENING_BALANCES` | C | PRM-06 opening import (canonical Phase 2 exit) |
| `CUSTOMER_BANK_BALANCES` / `CUSTOMER_RECEIVABLES` / `CUSTOMER_PAYABLES` | C | PRM-06/PRM-07 (Phase 2 exit) |
| `REAL_PROPERTY_VALUES` / `REAL_CAPITAL_POSITIONS` | C | PRM-04/PRM-07 (Phase 2 exit) |
| `PRODUCTION_DOMAIN` | C | PRM-02 environment (HTTPS/domain) |
| `REAL-PILOT SUPABASE PROJECT CREDENTIALS` | C | PRM-01/PRM-02 environment |

**Product-generated (not external, must not be pre-invented):** `REAL_ORGANIZATION_ID` and `REAL_PROJECT_ID` are assigned by the product at activation (organization/project creation), not supplied from outside. They exist only when the customer creates them; they are not intake inputs.

---

## 5. Canonical phase status (unchanged, honest)

| Canonical gate | Status | Produced by |
| --- | --- | --- |
| Phase 2 exit — "a real opening project can be imported and every financial balance reproduced" | **Not passed** | PRM-04 + PRM-05 + PRM-06 + PRM-07 on real customer data |
| Phase 3 exit — "one real project runs … in staging" | **Not passed** | PRM-09B supervised real-project staging proof |
| Phase 4 — controlled paid pilot | **Not started** | blocked until Phase 2 + Phase 3 exits pass with real evidence |
| Phase 5 — general availability | **Not started** | blocked until Phase 4 exit (PRM-16) passes |

Technical verification (S0–S7 merged; typecheck/lint/test/build and migration/RLS/concurrency rehearsals green on fixtures) is **not** delivery exit evidence. The sequence remains: technical baseline → isolated pilot/staging environment → customer source-data freeze → signed control totals → S7 controlled opening import → validation/rejection resolution → approval/posting → exact zero-variance opening reconciliation → full real-project lifecycle staging proof → Phase 2 exit → Phase 3 exit → controlled paid pilot → four weeks of operation → buyer UAT → Phase 4 exit → only then Phase 5.

---

## 6. Activation sequence (reference only — no step is executed here)

PRM-00 (verified main) → PRM-01/PRM-02 (environment, §1–§2 above) → PRM-03 (signed engagement + freeze date + named approver) → PRM-04/PRM-05 (intake delivery + quality gate) → PRM-06 (S7 opening import) → PRM-07 (zero-variance opening reconciliation = Phase 2 exit evidence) → PRM-08 (user provisioning) → PRM-09 + PRM-09B (training + real-project staging proof = Phase 3 exit evidence) → PRM-10 (go-live) → PRM-11…PRM-16 (pilot operation through Phase 4 exit) → PRM-17 (GA decision). Details in `01_PILOT_READINESS_MAP.md`; no gate advances without its real evidence.

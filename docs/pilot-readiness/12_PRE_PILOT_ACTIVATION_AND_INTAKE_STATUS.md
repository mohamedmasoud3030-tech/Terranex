# 12 — Pre-Pilot Activation & Real-Project Intake Status

**Purpose:** consolidated technical truth at the pre-pilot boundary: live environment readiness, Greenfield database state, frontend/backend compatibility, deployment status, remaining customer/operator inputs, and canonical phase status.

**Current status:** the Terranex technical pilot environment is now **initialized, synchronized, secured, connected to the application, and smoke-tested**. This does **not** satisfy canonical Phase 2 or Phase 3, because those exits require real-project evidence. Phase 4 remains not started.

Standing rules remain binding: zero-minor-unit reconciliation, forward-only migrations, no customer secrets/data in Git, no self-advancing human gates, and no service-role/secret key in any browser path.

---

## 1. Live technical environment

### Supabase

- Project ref: `nwpyeobuxzbdnnzyfyqw`
- Project name: `Terranex`
- Region: `eu-central-1`
- Status: `ACTIVE_HEALTHY`
- PostgreSQL version observed during activation: `17.6.1.127`
- Public URL: `https://nwpyeobuxzbdnnzyfyqw.supabase.co`
- Modern publishable browser key: **available and active**; value is intentionally not reproduced here.
- Service-role/secret key in browser configuration: **absent by design**.

The previously existing legacy Terranex `public` application schema was explicitly authorized for replacement. The legacy `public` schema was removed and the Greenfield schema was rebuilt exclusively from repository migrations. Supabase Auth/Storage schemas were not dropped by that reset.

### Vercel

- Production URL: `https://terranex.vercel.app`
- Production deployment framework: Next.js 16.3 via the repository `vercel.json` override.
- Production build: **READY**.
- Browser runtime values loaded by the production build:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- No PAT, database password, Supabase secret key, or service-role key is present in the browser runtime configuration.

Final anonymous smoke test on production:

- `GET /` → protected by the auth proxy and redirected to `/login`.
- `GET /login` → `200`.
- Runtime logs for the final deployment showed no `permission denied for table organizations` recurrence and no 500 from the smoke sequence.

---

## 2. Greenfield database verification

The live database was verified against the repository after activation.

| Check | Verified result |
| --- | --- |
| Canonical Greenfield tables | **62 / 62 present** |
| Unrelated/legacy `public` application tables | **0** |
| Tables explicitly required by migrations to use `FORCE ROW LEVEL SECURITY` | **22 / 22** |
| Applied migration ledger | **32 / 32** |
| Frontend `.from(...)` object references inspected | **28** |
| Frontend `.rpc(...)` function references inspected | **18** |
| Missing frontend-referenced tables/views in live DB | **0** |
| Missing frontend-referenced RPCs in live DB | **0** |
| Core S6/S7/audit/journal security anchors | **verified** |
| Supabase Security Advisor error-level findings after hardening | **0** |

The post-activation hardening is recorded in the forward-only migration:

`supabase/migrations/20260813000300_pilot_security_advisor_hardening.sql`

It closes the live advisor findings without weakening tenant controls:

- enables and forces RLS on `s7_opening_mapping_codes`;
- permits authenticated read-only access to that immutable reference registry;
- removes accidental anonymous/public execution of the 9-argument S5 allocation command while retaining the authenticated command surface;
- pins the search path on the three S1 trigger guards.

The same repository state was replayed from zero on a PostgreSQL 16 CI service. The canonical migration replay plus SQL/concurrency verification suites passed before the hardening PR was merged.

---

## 3. Frontend ↔ backend compatibility

The application and live Greenfield backend are now aligned at the database object contract level.

The frontend currently uses the canonical Supabase client from `src/shared/supabase/*` and requires exactly the two browser-safe runtime values listed in §1. Static extraction of frontend Supabase calls found 28 table/view references and 18 RPC names; every referenced object exists in the live Greenfield database.

A production-only sequencing defect was also found and fixed after the first live connection: Next.js could begin a tenant page query before the parent layout's anonymous-user redirect completed. The fix moves the anonymous private-route guard into `src/proxy.ts`, so an unauthenticated request is redirected before tenant queries execute. Database grants were **not** widened to make anonymous access work.

This proves the currently shipped frontend has the required live table/RPC surface. It does not replace user-flow UAT with a real signed-in pilot user.

---

## 4. Environment readiness classification

| Required item | State |
| --- | --- |
| Dedicated Terranex Supabase project | **READY / verified** |
| Greenfield schema replay | **COMPLETE** |
| Migration state synchronized | **COMPLETE — 32/32** |
| Tenant/security database anchors | **VERIFIED** |
| Supabase Security Advisor error-level findings | **0** |
| Modern publishable key | **AVAILABLE** |
| Vercel production deployment | **READY** |
| Production Supabase runtime configuration | **CONFIGURED** |
| Anonymous production smoke | **PASS** |
| Real pilot user provisioning / signed-in UAT | **PENDING real engagement** |
| Scheduled production backup owner + agreed RPO/RTO | **PENDING operator decision/evidence** |
| Error monitoring / alerting owner | **PENDING operator decision/evidence** |
| Real customer intake | **NOT STARTED** |

Technical environment activation is therefore no longer the blocker for the next delivery evidence. Remaining gates are either operational hardening items explicitly listed above or real-customer evidence requirements.

---

## 5. Real-project intake readiness

The existing intake contract (`02_DATA_INTAKE_CONTRACT.md`) remains the binding data contract and covers the S0–S7 opening needs:

| Dataset | Covers | Slice |
| --- | --- | --- |
| DS-01 Organization / DS-02 Projects | tenant + project shell | S0 |
| DS-03 Parties / DS-04 Agreements / DS-05 Commitments / DS-06 Calls / DS-07 Contributions | terms & funding | S1 |
| DS-08 Cash accounts / DS-10 Payables / DS-16 Bank statements | cost & cash | S2 |
| DS-11 Assets/parcels / DS-12 Acquisitions / DS-13 Development costs | real-estate operations | S3 |
| DS-14 Sales & dispositions | revenue & realized result | S4 |
| DS-15 Historical distributions | allocation & distribution | S5 |
| DS-09 Opening balances using the six locked mapping codes | controlled opening import | S7 |
| DS-17 Supporting documents/evidence references | evidence across slices | all |

No second import engine is required. Blank controlled worksheets already exist under `docs/pilot-readiness/templates/`.

---

## 6. Remaining external values — names only

These are real engagement/customer/operator inputs, not technical schema defects:

- `CUSTOMER_NAME` / `LEGAL_ENTITY_NAME`
- `CUSTOMER_OWNER_USER` / `CUSTOMER_APPROVER` / `CUSTOMER_EMAIL`
- `REAL_FREEZE_DATE`
- `SIGNED_CONTROL_TOTALS`
- `CUSTOMER_SOURCE_FILES`
- `CUSTOMER_OPENING_BALANCES`
- `CUSTOMER_BANK_BALANCES`
- `CUSTOMER_RECEIVABLES`
- `CUSTOMER_PAYABLES`
- `REAL_PROPERTY_VALUES`
- `REAL_CAPITAL_POSITIONS`
- named backup owner + accepted RPO/RTO
- named monitoring/on-call owner

`REAL_ORGANIZATION_ID` and `REAL_PROJECT_ID` are product-generated identifiers and must not be fabricated in advance.

---

## 7. Canonical phase status

| Canonical gate | Status | Required evidence |
| --- | --- | --- |
| Phase 2 exit — real opening project imported and every financial balance reproduced | **NOT PASSED** | real controlled opening import + exact zero-variance reconciliation |
| Phase 3 exit — one real project runs the required lifecycle in staging | **NOT PASSED** | supervised real-project staging lifecycle proof |
| Phase 4 — controlled paid pilot | **NOT STARTED / NOT YET ALLOWED** | Phase 2 + Phase 3 exits first |
| Phase 5 — GA | **NOT STARTED** | Phase 4 exit first |

S0–S7 implementation, database replay, live schema/security verification, frontend/backend object compatibility, and production deployment are technical evidence only. They do not substitute for the real-project evidence required by Phase 2 and Phase 3.

---

## 8. Next governed execution sequence

The technical environment is ready. The next delivery sequence is now:

`customer source-data freeze → signed source control totals → S7 controlled opening import → rejection resolution → approval/posting → exact zero-variance opening reconciliation → Phase 2 exit → full real-project lifecycle in staging → Phase 3 exit → controlled paid pilot Phase 4`

No canonical phase advances until its real evidence exists.

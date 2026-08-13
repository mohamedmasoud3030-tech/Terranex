# 08 — Deployment & Environment Readiness Checklist

**Purpose:** the exact prerequisites for the real pilot deployment (gate PRM-01/PRM-02), without changing production infrastructure and without claiming any deployment has occurred. **No deployment has been performed at the time of writing; every item below is pending until evidenced.**

**Verification classes:**

- **[A]** can be verified automatically (script/CI/command output).
- **[O]** must be configured by an operator (a human sets it; verification is inspection of state, not values).
- **[E]** requires an external credential or service (exists outside this repository and outside Terranex).
- **[S]** requires human sign-off (a named owner records a decision).

Secrets: this checklist handles **names and states only**. No secret value is ever written into this repository, this checklist, logs, or a browser bundle. Verification scripts in `scripts/pilot-readiness/` validate names against `.env.example` without reading values.

## 1. Environment variables [A/O]

The shipped application consumes exactly two variables (see `.env.example` and `src/shared/supabase/env.ts`):

| Variable | Class | Pilot requirement |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | O | Points at the dedicated pilot Supabase project. Verify: app reaches the pilot project, not any other. |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | O | The publishable key of the pilot project. It is browser-safe by design; it is still configured per environment, never hardcoded. |

- [ ] Both variables configured for the pilot deployment target. [O]
- [ ] No additional secret is required by the build: verify the production build succeeds with only these two. [A]
- [ ] No service-role key exists in any browser-reachable path (the product is built publishable-key-only; verify, do not add one). [A]
- [ ] No secret value appears in Git, logs, test fixtures, or the built client bundle (scan). [A]

## 2. Supabase project / environment [E/O]

- [ ] One dedicated Supabase project provisioned for the pilot (never a shared/dev project). [E]
- [ ] Project reference recorded in the engagement operations plan (identifier, not credentials). [O]
- [ ] Organization-level isolation assumption verified: the pilot database starts empty or migrated-only; no leftover fixtures. [O]
- [ ] Region/timezone choice recorded (reporting cut-offs reference dates; the product stores ISO dates). [S]

## 3. Database migration state [A]

- [ ] Clean replay from empty passes on the pilot project: every ordered migration under `supabase/migrations/` applies in order. [A]
- [ ] Migration state listing captured as evidence (which migrations applied, in order). [A]
- [ ] The canonical database gate (`npm run db:test`, PostgreSQL 16) passes for the exact release commit — including S0–S7 suites, the end-to-end rehearsal, and the backup/restore rehearsal. [A]
- [ ] No migration was hand-edited after apply; any forward fix is a new ordered migration (repository rule). [O]

## 4. Auth configuration [O/E]

- [ ] Supabase Auth enabled on the pilot project; email sign-in configured for customer users. [E/O]
- [ ] Invitation/enrollment procedure agreed with the customer OWNER (who creates the first users: gate PRM-08). [S]
- [ ] Session handling verified through the shipped server/client pattern (proxy refreshes sessions; no custom session hacks). [A]
- [ ] Membership model confirmed: application roles are OWNER and MEMBER only; status ACTIVE/INACTIVE; revocation immediate. [A — behavior proven by S7 suites]

## 5. Secrets management [O/E]

- [ ] A secrets location exists for the engagement (provider chosen by the operator); this repository stores none. [E]
- [ ] Access to the Supabase project dashboard/credentials restricted to `<ENGINEERING_ONCALL>` and the owner. [O]
- [ ] Rotation procedure recorded (who rotates, when, and how a rotated key reaches the deployment target). [S]
- [ ] Standing rule restated: service-role credentials never enter browser code and are never used from a support session. [O]

## 6. Application deployment [O/A]

- [ ] One deployable Next.js application build produced from the exact release commit. [A]
- [ ] Deployment target chosen and configured (platform is an operator decision — v1 is one deployable unit by architecture decision A-001). [O/E]
- [ ] The deployed build matches the commit whose gates are green (build metadata recorded). [A]
- [ ] Preview vs pilot environments are distinct; no preview environment holds pilot customer data. [O]

## 7. HTTPS / domain [E/O]

- [ ] Pilot environment served exclusively over HTTPS with a valid certificate. [E]
- [ ] Domain/subdomain agreed with the customer and recorded (Arabic-first product; RTL unaffected by domain choice). [S]
- [ ] No plain-HTTP route to the pilot environment exists (redirect or refuse). [O]

## 8. Backup policy [O/E/S]

- [ ] Scheduled logical backups enabled for the pilot Supabase project (frequency + retention recorded). [E/O]
- [ ] Backup ownership named (`<ENGINEERING_ONCALL>`). [S]
- [ ] Distinction preserved: the repository's automated rehearsal is **not** the production backup policy (`docs/runbooks/BACKUP_AND_RESTORE.md`). [O]

## 9. Restore verification [A/S]

- [ ] Automated backup/restore rehearsal passes on the release commit (`supabase/tests/26_s7_backup_restore.sh`: seventeen integrity fingerprints, RLS/immutability survival, tamper refusal). [A]
- [ ] Rehearsal fact `BACKUP_RESTORE` recorded with `production_restore_performed: false` — and it stays false until a named operator performs and records a real restore. [A]
- [ ] Recovery objectives (RPO/RTO) agreed with the customer and recorded — **requires professional review**; the product sets none by itself. [S]

## 10. Logging [O]

- [ ] Application and database logs available to `<ENGINEERING_ONCALL>` for the pilot environment. [O]
- [ ] Audit trail understood as the product's canonical record: `audit_events` are append-only and carry identifiers/safe metadata, never secrets or document contents. [A]
- [ ] Log access restricted to support roles named in the engagement. [O]

## 11. Error monitoring [O/E]

- [ ] An alerting path exists for application errors and failed requests (tooling is an operator choice; v1 ships no built-in monitor and this checklist does not force one). [E/O]
- [ ] Inbound reports from the customer route through the support channel into `SUPPORT_ESCALATION.md` regardless of tooling. [O]
- [ ] On-call assignment recorded (`<ENGINEERING_ONCALL>`). [S]

## 12. Audit retention [S]

- [ ] Customer data processing and retention terms approved in writing — roadmap operations release gate; **requires professional legal review**; do not improvise policy here. [S]
- [ ] Append-only evidence expectation communicated: imports, checkpoints, exceptions, UAT tasks, rehearsals, and audit events are never deleted; corrections add records. [O]
- [ ] Evidence references (not files) are what Terranex stores; customer documents remain in customer systems, so document retention is primarily the customer's policy — confirm understanding in the handoff (see `10_COMMERCIAL_HANDOFF_REQUIREMENTS.md`). [S]

## 13. Admin recovery [A/S]

- [ ] Last-active-owner guard verified (appoint, then revoke — the database refuses to leave zero active owners). [A — proven by S7 suites; re-demonstrate per engagement]
- [ ] OWNER recovery procedure agreed: add a second active OWNER early in the pilot (UAT-19 exercises the boundary). [S]
- [ ] Membership revocation drill scheduled (UAT-19). [O]

## 14. Smoke test [A/O]

Run on the pilot environment after deployment, before any customer data entry:

- [ ] Sign in as OWNER; create/open the pilot project shell. [A]
- [ ] Verify the pilot workspace loads with honest empty states (no seeded/fake data). [A]
- [ ] Verify the acceptance report read model responds (rehearsals expected: current; human UAT expected: `NOT_STARTED`). [A]
- [ ] Verify a second organization cannot see pilot rows (two-tenant check per S0 suites, re-demonstrated). [A]
- [ ] Record the smoke-test result with the release commit id. [O]

## 15. Release rollback decision [S]

- [ ] Rollback criteria agreed before go-live: what observable failure triggers rollback (e.g. failed migration, auth outage, integrity error). [S]
- [ ] Rollback path understood: migrations are additive and never hand-edited; a failed release/migration is handled by `docs/runbooks/FAILED_DEPLOYMENT_OR_MIGRATION.md`, not by ad-hoc schema surgery. [O]
- [ ] Decision owner named: `<ENGINEERING_ONCALL>` executes, `<PILOT_OPS_OWNER>` communicates to the customer. [S]

---

## Sign-off block

| Section | Verified by | Method | Date | Evidence reference |
| --- | --- | --- | --- | --- |
| 1–15 | (pending) | per-class above | (pending) | (pending) |

PRM-01 passes only when every checkbox is evidenced; a single "not verified" item fails the gate honestly instead of being claimed.

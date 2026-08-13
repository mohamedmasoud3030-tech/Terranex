# 11 — GA Readiness Backlog

**Purpose:** prioritized Phase 5 (General Availability) backlog, derived strictly from the canonical Phase 5 requirements, the expected operational friction of the controlled pilot, and the capabilities the repository actually has. Packages are deliberately LARGE execution units, not micro-tasks.

**Canonical Phase 5 order (roadmap §5):** hardened onboarding/import → support/admin console and service-level policy → billing/plan limits → external accounting export adapter → second design partner → **only then** second sector pack.

**Sequencing lock (authoritative):**

```text
technical verification (PRM-00)
  → real opening project imported / canonical Phase 2 exit (PRM-04…PRM-07)
  → real project end-to-end in staging / canonical Phase 3 exit (PRM-09B)
  → controlled paid pilot / Phase 4 operation (PRM-10…PRM-15)
  → Phase 4 exit (PRM-16)
  → WP1 / Phase 5
```

**Do not start WP1 (or any Phase 5 product code) immediately after the technical audit.** A green audit stream proves technical correctness on fixtures; it does not produce the pilot friction evidence Phase 5 productization must be built from. Three modes are distinct and must not blur:

| Mode | Allowed when | Examples |
| --- | --- | --- |
| Safe pre-pilot preparation | now (this pack) | procedures, templates, checklists, runbooks, documentation — no product code |
| Phase 4 operational execution | after Phase 2/3 staging gates | running the pilot on real data, capturing friction evidence |
| Phase 5 productization | **only after Phase 4 exit (PRM-16) passes** | WP1–WP5 product code, built from observed pilot evidence, not speculated friction |

**Hard exclusions for all packages:** second sector implementation (Agriculture/Livestock); advanced waterfall/carry/preferred return/clawback; public investor onboarding or marketplace; native banking/money movement; AI forecasting/automated valuation; custom report builder; offline/PWA; tenant-specific forks. Nothing in this backlog may start before the pilot exit gate (PRM-16) passes, and nothing outranks an open audit finding (roadmap §6 priority 1).

---

## WP1 — Hardened onboarding & import (start first)

- **Purpose:** turn the single-customer opening-intake process (this pack's `02`/`03` procedures + S7 import) into a repeatable product onboarding for the next customers, killing per-customer code. This is the direct answer to roadmap commercial learning test #7: "onboarding can be repeated for a second company without custom code."
- **Dependencies:** **Phase 4 exit (PRM-16) passed — mandatory and non-negotiable.** WP1 must not start after the technical audit alone, and it must not productize speculated pilot friction before the pilot is observed. Inputs: real pilot friction evidence (rejected-row reasons, modelling-gap reports from DS-09, intake rework logs, staging-proof findings from PRM-09B) plus merged audit-stream state.
- **Expected files/domains:** `src/features/pilot/` (import workspace ergonomics, staging worksheets), S7 import schema evolution via new forward migrations (e.g. staged-row ergonomics, rejection reporting, intake summary read models) — additive only; intake templates moved into the product rather than this pack's worksheets where proven; onboarding checklist surfaced in the pilot workspace.
- **Acceptance gate:** a second organization's opening position is imported and reconciled to zero variance without any repository code change; intake rejection reasons cover every observed pilot failure mode or are explicitly reported as modelling gaps; S7 suites extended, none weakened.
- **Must NOT be built yet:** a universal importer or mapping designer; arbitrary chart-of-accounts ingestion; new semantic account roles; non-EGP currency support; document storage. The six-code locked registry stays locked unless a real modelling gap and a product decision say otherwise.

## WP2 — Support/admin console and service-level policy

- **Purpose:** give Terranex operators first-class support tooling and a published service-level policy, replacing ad-hoc support memberships (`09_PILOT_ROLES_AND_RESPONSIBILITIES.md` §3) and placeholder escalation with a defined operating model.
- **Dependencies:** pilot incident records and `07_INCIDENT_SUPPORT_MATRIX.md` gap findings (G-01 close-gate triage; G-02 non-cash variance treatment); WP1 not required but typically concurrent.
- **Expected files/domains:** new `docs/runbooks/CLOSE_RUN_GATE_FAILURE.md` (and any other gap the pilot proves); a bounded support/admin surface inside the existing Next.js app (organization health: rehearsal state, acceptance report, exception aging, membership overview) reusing existing read models — no second application shell; service-level policy document with severities, response/escalation targets, and communication rules consistent with `SUPPORT_ESCALATION.md`.
- **Acceptance gate:** every pilot-observed support situation resolves through documented procedure without developer SQL access; support actions are audited per-actor with no service-role browser path; the SLA policy is agreed commercially for GA customers.
- **Must NOT be built yet:** customer-facing ticketing integrations; notification channels (email/WhatsApp delivery); self-service admin for financial corrections (corrections stay on product command paths with maker/checker).

## WP3 — Billing and plan limits

- **Purpose:** charge for GA: subscription tiers per organization with enforceable plan limits, per the charter's business model (setup/migration fee + monthly subscription per organization tier, included seats with fair-use boundary).
- **Dependencies:** pilot commercial continuation/renewal signal (roadmap learning test #6); WP2 (support ownership must exist before selling at scale); an external payment collection decision (Terranex has no money movement — billing collection itself is external by product boundary).
- **Expected files/domains:** plan/entitlement model as a new bounded context with tenant-safe RLS and audit; enforcement hooks at organization/project/membership creation limits; metering read models for the value metrics (projects, members, posted events). Money handling for the subscription itself stays outside Terranex (collected externally); the product stores entitlement facts, not payment execution.
- **Acceptance gate:** an organization over its plan limit is blocked from the limited action with an honest Arabic/RTL state; entitlement changes are audited and effective-dated; no financial invariant or tenant isolation weakens (full regression suites green).
- **Must NOT be built yet:** in-app payment collection or custody of any kind; usage-based per-transaction pricing engines; plan marketplaces.

## WP4 — External accounting export adapter

- **Purpose:** deliver approved journal batches to the customer's statutory/general ledger (which remains external in v1) as a real integration, per `05_FINANCE_AND_ACCOUNTING.md` §14: batch ID/version, lines, account mapping, dimensions, currency, source refs, document refs, checksum; export status pending/sent/accepted/rejected/reversed; durable outbox only inside this slice.
- **Dependencies:** at least one closed pilot period with a verified investor statement (PRM-13/PRM-14 evidence); the customer's external accountant engaged with approved chart/policy mapping (roadmap risk: "External accountant rejects exports" — involve them early); WP1/WP2 not strictly required but GA-sequenced after them.
- **Expected files/domains:** a new adapter feature (`src/features/<adapter>/`) with server-authoritative export commands; transactional outbox introduced here because a real external consumer now exists (architecture §8 rule satisfied); mapping configuration owned by the organization's approved policy — semantic roles map out, there is still no editable chart of accounts inside Terranex; Egyptian e-invoicing remains separate and later (ETA certification, server-side credentials only).
- **Acceptance gate:** a closed period's approved batches export with checksums and are accepted by the external system in a test environment; export status lifecycle is auditable; a rejected export is re-sendable idempotently; statutory mapping reviewed and signed by a qualified accountant `[ACCOUNTING]`.
- **Must NOT be built yet:** a two-way GL sync or second editable ledger; tax return preparation; e-invoice production certification inside this package; generic integration framework for hypothetical consumers.

## WP5 — Second design partner (then, and only then, second-sector preparation)

- **Purpose:** prove GA repeatability by onboarding a second Real Estate design partner end-to-end using WP1–WP4 outputs; only after this succeeds does the second sector pack (Agriculture or Livestock, per product decision) enter planning.
- **Dependencies:** WP1 (repeatable onboarding), WP2 (support model), WP3 (billing), and pilot exit evidence. The second sector itself depends additionally on the sector-pack release gate (`04_SECTOR_MODELS.md` §6) — including real customer sample data replayed end-to-end — which cannot start inside this package.
- **Expected files/domains:** engagement artifacts (this pack's templates instantiated for partner two); any onboarding product fixes WP5 exposes (routed back into WP1 scope); no core rewrite.
- **Acceptance gate:** partner two reaches their own four-week pilot exit with zero custom code; the commercial learning plan signals hold (users capture data without the founder operating for them; management uses Terranex for real decisions; subscription renews).
- **Must NOT be built yet:** any Agriculture/Livestock runtime module; cross-project consolidation or netting; multi-currency/FX engine; investor self-service beyond the existing self-scope.

---

## Sequencing summary

All triggers presuppose the full sequencing lock above (technical verification → Phase 2 exit → Phase 3 exit → Phase 4 → Phase 4 exit). The technical audit finishing is a precondition for the *staging gates*, not for Phase 5 product work.

| Order | Package | Trigger |
| --- | --- | --- |
| 1 | WP1 Hardened onboarding & import | **Phase 4 exit (PRM-16) passed** with real pilot friction evidence — never earlier |
| 2 | WP2 Support/admin console + SLA | pilot incident evidence (can overlap WP1, still post-Phase-4-exit) |
| 3 | WP3 Billing & plan limits | renewal intent confirmed |
| 4 | WP4 External accounting export adapter | closed-period evidence + accountant engagement |
| 5 | WP5 Second design partner | WP1–WP4 delivered |
| — | Second sector pack | only after WP5 acceptance gate; separate product decision |

If the pilot itself disproves a premise (e.g. onboarding still needs code per customer), the roadmap says: pause expansion and productize first — i.e. loop back into WP1/WP2 before anything else.

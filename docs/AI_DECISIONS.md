# AI Decisions — Terranex (2026-08-17)

Decisions made autonomously during this review/improvement cycle, with evidence and rationale. All decisions are reversible and none change the product's target market, legal posture, or business policy.

## AD-01 — Keep the existing architecture and stack (no replacement)
**Decision:** continue with the Next.js modular monolith + single Supabase/PostgreSQL backend; no framework, database, auth, or state-management replacement.
**Why:** the stack is working (all gates green), matches the canonical target architecture in `AGENTS.md`, and replacing it would create risk with no product benefit.
**Reversibility:** n/a (nothing changed).

## AD-02 — Local database verification gets real tooling, not an emulation
**Decision:** provision a disposable real PostgreSQL 16.14 in the sandbox (npm binary package `@embedded-postgres/linux-x64`, used **outside** the repository in `/tmp` only) and build real `psql`, `pg_dump`, `pg_restore` 16.4 from PostgreSQL source (GitHub mirror) to run the canonical `scripts/db-test.sh` locally.
**Why:** the previous session could not run the database gate locally (no psql/Docker) and had to mark it unresolved. The canonical runner was not modified or replaced; only the tool binaries were supplied locally.
**Reversibility:** fully — nothing was added to the repository.
**Constraint:** the npm binary package and built tools are sandbox-only artifacts; they are never added to `package.json` or committed.

## AD-03 — The demo showcase seed activates demo policy explicitly, per demo org
**Decision:** fix `scripts/demo/seed_real_estate_showcase.sql` by inserting the two policy-authority rows (`CAPITAL_CONTRIBUTION`, `INVESTOR_ECONOMICS`) for the **demo organization only**, right after the demo org is created, labeled as synthetic demo policy (`policy_version = 'DEMO-SHOWCASE-POLICY-2026-01'`, `evidence_reference = 'DEMO-AGREEMENT-2026-001 (synthetic demo fixture)'`).
**Why:**
- The showcase narrative (60/40 demo agreement, allocation, distribution) is explicitly synthetic demo data already documented in `docs/demo/REAL_ESTATE_SHOWCASE.md`. Keeping it requires those commands, which now fail closed.
- The safety boundary is **per-organization**: real organizations still start with an empty registry and stay policy-inert. No company business rule is invented; the demo org's "policy" is a labeled synthetic fixture.
- The alternative (deleting the S5 section from the seed) would gut the showcase; the alternative (documenting a manual activation step) would leave the seed non-re-runnable, contradicting its own documentation.
**Guardrails:** the pre-owner-policy migration itself remains untouched and still ships an empty registry (characterization test `tests/r10-policy-block.test.ts` keeps asserting this); a new DB suite (`supabase/tests/zz_demo_seed_replay.sql`) proves the seed succeeds on a fresh schema, is re-runnable (no-op), and activates policy rows **only** for the demo org.
**Second defect found while executing the seed:** the R4 payment boundary had also broken the seed — `pay_cost_obligation` is now a fail-closed tombstone (migration `20260815034000`). The seed's three supplier payments now post through the production maker/checker surface (`prepare_cost_payment` by the demo maker, `approve_cost_payment` by the OWNER checker), with identical journal and cash effects. This is a seed fixture repair, not a product-rule change.

## AD-04 — Organization context via cookie + header switcher (minimal, reversible)
**Decision:** implement a first-class active-organization context: a server helper reading a `terranex_active_org` cookie (validated against the user's memberships, falling back to the first org), a header `<select>` switcher (client component: sets the cookie, `router.refresh()`), and switch the org-scoped top-level pages (Home, Projects, Portfolios, Portfolios/new, Assets, Intake, Projects/new) to use it. Project/portfolio pages keep resolving the org from the entity itself.
**Why:** RLS supports multi-org memberships, so silently using `organizations[0]` risks recording data in the wrong org. A cookie+select is the smallest robust pattern that fits the existing server-component architecture (no new dependency, no URL pollution, works across navigation). It is fully reversible (delete cookie → first org).
**Alternatives considered:** URL query param on every link (invasive, easy to lose), client-side global state + context provider (needs client root + hydration plumbing), a dedicated settings page (heavier). Cookie + select wins on simplicity and compatibility.
**Scope guard:** no org-switch is forced onto entity-scoped pages (portfolio/project pages already bind to the entity's org), and single-org users see no switcher at all.

## AD-05 — Intake copy is made sector-honest (no invented behavior)
**Decision:** rewrite the `/intake` start-page copy to describe the three supported sectors accurately and link projects to their sector landing page, without adding any new workflow.
**Why:** the current copy ("القطاع الأول: عقاري") is factually wrong for the shipped product and misleads operators. Copy change only; no business rule changes.

## AD-06 — Authenticated users visiting `/login` are redirected home
**Decision:** make `/login` a thin server wrapper: if a session exists, redirect to `/`; otherwise render the existing login form (extracted to a client component, behavior unchanged).
**Why:** standard session UX; prevents double-login confusion after expiry/bookmark flows. The anonymous redirect (`proxy.ts`) and the sign-in action are untouched.

## AD-07 — Arabic app-level error boundary + health endpoint
**Decision:**
1. Add `src/app/(app)/error.tsx` (client component) so any unhandled error inside the authenticated shell shows an Arabic, recoverable state instead of the default English Next.js error page.
2. Add `GET /api/health` returning `{ status: 'ok' }` (no auth, no data access, no new env vars) for deployment/post-deploy smoke.
**Why:** both are standard, dependency-free operational basics; the deployment checklist and runbooks currently have no code-level health/smoke surface. The health route does not change the documented "exactly two environment variables" contract.

## AD-08 — CI gains a dependency-audit step (least-privilege spirit preserved)
**Decision:** add `npm audit --audit-level=low` to the `app` job of `greenfield-ci.yml` (which already runs with `permissions: contents: read`).
**Why:** `npm audit` is clean today (verified) but un-gated; a CI step makes future dependency drift visible before merge. It is a read-only check that matches the workflow's existing least-privilege posture.

## AD-09 — R15 admission gate stays blocked; no owner-policy invention
**Decision:** `npm run r15:admission` remains BLOCKED. No default percentages, no placeholder policy rows for real orgs, no entitlement UI.
**Why:** `BD-001…BD-012` are owner decisions (legal/economic). This session's demo-policy work (AD-03) is explicitly synthetic demo-fixture scope and never touches real-tenant policy.

## AD-10 — Evidence labels
Only `VERIFIED COMPLETE`, `IMPLEMENTED BUT NOT VERIFIED`, `BLOCKED BY OWNER/EXTERNAL ACTION`, `NOT STARTED` are used. A passing build/test alone is not proof of completion; each milestone lists what was run where.

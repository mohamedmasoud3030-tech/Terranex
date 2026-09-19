# Terranex Greenfield — Agent Policy

**Effective:** 2026-08-15
**Status:** Canonical for `main` and every branch created from it

## Mission

Build Terranex as a greenfield Investment Operations OS for private investment operators in real estate, agriculture, and livestock. The shared investment, finance, control, and audit core is built once; sector behavior remains inside explicit bounded contexts. The management hierarchy is Organization → Investment Portfolio → Investment Project; Portfolio organizes independent projects and must not silently acquire fund/legal/investor-pool semantics.

## Canonical sources

Read these files completely before changing the product:

1. `AGENTS.md`
2. `docs/greenfield/01_PRODUCT_CHARTER_AND_MARKET.md`
3. `docs/greenfield/02_OPERATING_MODEL_AND_JOURNEYS.md`
4. `docs/greenfield/03_DOMAIN_MODEL.md`
5. `docs/greenfield/04_SECTOR_MODELS.md`
6. `docs/greenfield/05_FINANCE_AND_ACCOUNTING.md`
7. `docs/greenfield/06_SYSTEM_ARCHITECTURE_AND_SECURITY.md`
8. `docs/greenfield/07_UX_INFORMATION_ARCHITECTURE.md`
9. `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md`
10. `docs/OPEN_BUSINESS_DECISIONS.md`
11. `GREENFIELD_EXECUTION.md`
12. `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`
13. `docs/decisions/0002_SIMPLICITY_AND_VERTICAL_SLICES.md`
14. `docs/decisions/0012_SECTOR_EXPANSION_SEQUENCE.md`
15. `docs/ROADMAP_R0_R17.md` (R0–R17 sequence; hard stop at R13; R14–R17 policy pack)
16. `docs/DB_DEVELOPMENT.md`

No deleted or archived Terranex file is authoritative. The frozen legacy snapshot is recorded in `docs/LEGACY_FREEZE.md` and exists only for forensic reference.

## Project Agent Skills

Terranex project skills live under .agents/skills and follow the Agent Skills SKILL.md format with progressive disclosure.

- Load only the skill or skills whose frontmatter description matches the current task; do not preload the whole skill set.
- Project skills are operational workflows, not product/business authority. AGENTS.md, canonical Terranex documents, ADRs, and OPEN_BUSINESS_DECISIONS take precedence.
- External skill repositories are design evidence. Do not vendor generic copies beside the Terranex synthesis unless a later decision explicitly requires it.
- Before adding, merging, or deleting a project skill, follow docs/agent-os/SKILL_DESIGN_STANDARD.md and update the gap analysis/source registry.

Current project skills:

| Skill | Trigger domain |
| --- | --- |
| terranex-architecture-decision | ADRs, system design, technology/data/API boundaries |
| terranex-implementation-planning | Deterministic implementation plans and agent handoffs |
| terranex-implementation | Runtime implementation, fixes, tests, migrations, dependencies |
| terranex-code-review | Risk-routed diff/branch/PR review; review remains separate from fix |
| terranex-database | PostgreSQL, migrations, RLS, tenant isolation, data/financial grain |
| terranex-threat-model | Repository-grounded AppSec threat modeling for trust-boundary changes |

## Non-negotiable boundary

- Do not refactor, port, or recreate legacy business logic by default.
- Do not copy legacy entities, migrations, workflows, routes, financial rules, tests, or product documentation into Greenfield.
- A generic technical fragment may be reused only after a written assessment proves it matches the Greenfield contracts and introduces no hidden domain assumption.
- Sector expansion history is Real Estate first, Agriculture second, Livestock third; all three authorized technical paths now exist. Preserve their bounded contexts and shared core rather than reopening the historical sequence or creating competing duplicate cores.
- Terranex is a private operational system in v1, not crowdfunding, custody, a public marketplace, or a statutory general ledger.
- Investment Portfolio is a management/reporting parent above independent projects. Do not treat it as a fund, legal entity, SPV, pooled vehicle, investor pool, or second ledger unless an explicit later business decision establishes that meaning.

## Anti-hallucination and domain-invention rules

Terranex agents must distinguish four kinds of information and never collapse them:

1. **Canonical product/business decision** — explicitly approved in current canonical docs/ADRs.
2. **Implementation fact** — behavior that exists in code/migrations/tests; this proves what the system currently does, not that the behavior is universally correct business policy.
3. **External evidence** — law, accounting/industry standard, mature product pattern, public reference artifact, or professional guidance; this can validate a pattern or constraint but does not prove this company uses a specific optional rule.
4. **Assumption/open business decision** — anything material not established by the three categories above.

Mandatory rules:

- Never promote a guess, legacy practice, synthetic demo, fixture, UI label, existing column, coincidentally matching amount, industry convention, or “common” workflow into a company business rule.
- Never infer legal/entity structure, fund/SPV status, investor pooling, ownership, entitlement, contribution basis, profit/loss allocation, distribution formula, reserves, fees, tax/withholding, cross-project netting/recycling, or investor lifecycle behavior from names or current data.
- **Portfolio capital deployment/project funding is not investor contribution, ownership, allocation, distribution, or payment.** Keep each fact explicit.
- Contribution amount does not imply ownership. Ownership does not imply profit-allocation basis. Allocation does not imply distributable cash. Approved distribution does not imply payment.
- Portfolio/project roll-ups are derived management views. A dashboard requirement never authorizes a new ledger or cross-project accounting behavior.
- External standards and mature platforms are research evidence only. Apply a rule only when it is mandatory for the product boundary or explicitly approved for Terranex/the target company.
- For accounting, tax, regulatory, or legal consequences, preserve the product fact/evidence and require qualified validation where the treatment is not already established. Do not claim compliance by inference.
- If a material implementation depends on an unresolved business rule, search the canonical sources and relevant authoritative evidence. If still unresolved, add/reference the item in `docs/OPEN_BUSINESS_DECISIONS.md`, stop **only the dependent scope**, and continue unrelated bounded work.
- Do not evade an unresolved decision by adding generic configuration, a rules engine, nullable schema, an `OTHER` enum, a fake default percentage, or a placeholder workflow.
- A later agent may delete or change an earlier user/agent idea when stronger evidence proves it unrealistic or incorrect; preserve the reason and source of the correction.
- Never claim customer validation, legal approval, accounting approval, production evidence, or business-owner approval unless that evidence actually exists.

## Current delivery gate

Real Estate (S0–S7, GF-010/GF-011), Agriculture (GF-013 through GF-019), and Livestock (GF-020 through GF-024) are technically implemented for their currently authorized scopes. The historical sector-expansion sequence is closed at GF-024; older text describing Livestock or GF-021/GF-022 as the active slices is stale and must not drive new work. R0 — Canonical Portfolio Realignment & Anti-Hallucination Governance — is **merged** and no longer the active task.

The canonical roadmap is now the **R0–R17** sequence defined in `docs/ROADMAP_R0_R17.md` and referenced in `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md`. The controlling strategy is **Build Everything Independent First**:

- **R0 — Canonical Realignment:** merged. `Portfolio ≠ Project ≠ Asset ≠ Legal Vehicle ≠ Operating Cycle`; Terranex agents never invent Investor Economics.
- **R1 – R12 (independent build phases):** implement every feature whose correctness does **not** depend on unresolved legal/economic policy. Sector work (Real Estate, Agriculture, Livestock), the shared Finance Core, Portfolio/Project/Asset management, procurement, reporting, management UX, and production hardening proceed without waiting for the target company's investor answers.
- **R13 — Full Company Simulation:** prove every pound is traceable across a large synthetic scenario (RE/Ag/Livestock portfolios, purchases, revenue, cash, valuations, sales, closeouts). No invented investor entitlements.
- **Hard stop at R13:** after R13, do not start portfolio/investor-economics expansion that depends on an OPEN item in `docs/OPEN_BUSINESS_DECISIONS.md` until the owner resolves it.
- **R14 – R17 (small policy pack):** only after the owner answers the 13 business-policy questions (the policy pack) do we reflect the real agreement (R14), investor economics (R15), distribution & investor statements (R16), and final company UAT (R17).

**Delivered slice status on this lineage:**

- **R1 — Portfolio Foundation (merged through PR #139):** the Organization → Investment Portfolio → Investment Project management hierarchy: Portfolio identity and narrow `DRAFT | ACTIVE | ARCHIVED` lifecycle, one current parent Portfolio per Project, append-only/soft-closed membership history, Arabic/RTL Portfolio workspace, RLS/audit/idempotent commands. Management/reporting only — no fund/SPV/legal-entity/investor-pool semantics, no second ledger.
- **R4 — Procurement & Shared Operations (procure-to-pay + contracts/evidence delivered):** the shared operational foundation carries exact commercial PO terms, approved unposted commitment truth, receipt-matched Supplier Invoices, and linkage to the existing Finance Core payable/payment/bank-reconciliation mechanisms under ADR 0030. ADR 0031 adds private versioned PO/contract/receipt/invoice files and evidence approval gates. Only the bounded shared inventory-value concepts and R4 closeout audit remain; no second Procurement or Finance ledger exists.

Delivered slice labels (R1 Portfolio Foundation, R4 Procurement Foundation/Receiving) name the bounded increments; the R1–R17 phase numbers above define roadmap phases and gates. The slice-vs-phase mapping is recorded in `docs/ROADMAP_R0_R17.md`.

**Deferral rule:** a feature whose correctness depends on an unresolved rule stops **only the rule-dependent portion**, not the feature or the feature's independent 90%. Build the independent part now; keep the entitlement/allocatable-number surface inert until the policy is fixed. Never invent a default, a fake percentage, an `OTHER` enum, a generic rules engine, or a guessed entitlement rule to avoid the stop. Never display an investor profit/entitlement number computed from an unapproved basis.

Terranex follows a **product-first** strategy. Customer interviews, a design partner, or customer documents are not prerequisites for implementation of established common product behavior. Build the common Investment Operations Core from the approved Greenfield model, established industry patterns, authoritative standards, and explicit test scenarios; then configure or extend it for each company without forking the core. Company-specific investor/legal/economic behavior, however, must not be fabricated under the product-first rule.

Implementation outside the R0 docs-only branch is authorized only within the next approved bounded slice. Record decisions just in time for that slice; do not create an architecture-document phase before working software. A slice may introduce only the schema, rules, UI, and tests it actually uses. Keep Egypt-specific tax, statutory accounting, e-invoicing, and regulatory behavior isolated until professionally validated.

The first operating market is Egypt. Arabic/RTL, EGP, Egyptian document terminology, and Egypt-ready configuration are launch priorities, but country-specific rules must not be hardcoded into the shared core.

Real Estate completed the S0-S7 technical path and the GF-010/GF-011 hosted workspace work using a clearly synthetic showcase. Agriculture and Livestock completed their authorized technical construction through GF-019 and GF-024 respectively. Technical completion is **not** customer validation, buyer UAT, paid-pilot evidence, legal/accounting approval, or production-company evidence.

## Target architecture

- One deployable Next.js App Router application at the repository root; no monorepo and no internal package workspace.
- One Supabase project with one PostgreSQL database, Supabase Auth, private Storage, and default-deny RLS.
- Feature folders under `src/features`; genuinely shared code under `src/shared` only after two real consumers exist.
- Server Actions or Route Handlers for application commands; transactional SQL/RPC only when a write must be atomic in the database.
- No microservices, CQRS framework, event sourcing, generic repository, plugin/rules engine, transactional outbox, offline sync, PWA machinery, queues, or external integrations until an implemented workflow proves the need.
- Company differences use small typed configuration or explicit bounded extensions; never tenant-specific forks.
- Build one complete vertical slice at a time. The conceptual domain catalog is not a request to scaffold unused entities.
- The Portfolio layer does not get a duplicate finance, ownership, payment, approval, or audit engine. Project-authoritative facts roll up through read models.

## Financial and security rules

- Never use floating point for money.
- Every tenant-owned record carries `organization_id`; cross-tenant references require database-enforced integrity.
- Material commands are atomic, idempotent, version-aware, authorized, and auditable.
- Posted facts are append-only; corrections use reversal/repost with a complete chain.
- The browser never supplies authoritative balances, entitlements, or approval outcomes.
- Never infer ownership, entitlement, or distribution rights from cash movement, contribution amount, Portfolio membership, or Project membership.
- Keep Portfolio capital deployment, funding/accounting mechanism, investor contribution, ownership, result allocation, distribution, and payment as distinct concepts.
- No secrets, real credentials, personal data, or unsanitized customer artifacts enter Git.
- Do not access or modify production data, Supabase, Vercel, banking, or external accounting systems without explicit authorization.

### Client idempotency-key lifecycle

For UI/client command nonces and idempotency keys:

- the same key must remain stable across retries of the **same logical submission**;
- generate a new key only after confirmed success of the previous logical operation;
- validation, authentication, transport, or server failure must **not** rotate the key;
- after confirmed success, a later distinct submission from the same form/session must use a fresh key;
- regression coverage is required for successive successful submissions from the same reusable form/session, not only retry behavior.

## Database development access

- `npm run db:test` / `bash ./scripts/db-test.sh` is the canonical local database gate.
- The runner must use local `psql` when available and automatically fall back to disposable PostgreSQL 16 via Docker when `psql` is unavailable.
- Every ordered migration under `supabase/migrations/*.sql` and every verification suite under `supabase/tests/*.sql` is discovered automatically.
- Missing `psql` alone is never a valid reason to skip database verification.
- If neither `psql` nor Docker is available, report the database gate as unresolved and rely on the repository CI database job before merge; never mark it simulated or passed.
- Use `npm run db:shell` / `bash ./scripts/db-shell.sh` for an interactive local database shell.
- Never commit Supabase database passwords, service-role keys, personal access tokens, or shared-environment connection strings. Shared/demo/production migrations require explicit authorization and environment-supplied secrets.

## UX rules

- Arabic/RTL is the primary experience; English/LTR remains supported.
- Mobile-first density, WCAG 2.2 AA, keyboard support, and honest loading/error/empty/offline/conflict states are required.
- Keep navigation shallow and context-aware: Portfolio → Project → source. Do not introduce nested page-within-page or tab sprawl.
- Every Portfolio total must be traceable to Project composition; every Project total must be traceable to source facts/evidence.
- Do not show portfolio ownership, pooled investor balance, portfolio distributable profit, or cross-project netted economics until the corresponding business decisions are resolved.
- Do not imply that a draft, pending approval, unreconciled amount, or failed sync is final.

## Change discipline

- Before starting any implementation branch, run `git fetch origin` and create the branch from the exact current `origin/main`; never trust a stale session/workspace branch as the base. `greenfield/foundation` is historical and non-authoritative unless Mohamed explicitly reactivates it.
- Before opening or updating an implementation PR, verify `git rev-list --left-right --count origin/main...HEAD`; the branch must be **0 behind** its target. If it is behind, repair the lineage before delivery rather than opening a divergent PR.
- Inspect the target comparison before delivery. A narrow vertical slice must not unexpectedly delete/reintroduce legacy files or show unrelated repository-wide churn.
- Before a business-sensitive implementation PR, state which canonical decision(s) authorize the behavior and which `OPEN_BUSINESS_DECISIONS` IDs, if any, remain unresolved. Do not ship code whose correctness depends on an OPEN item.
- Do not replace the canonical database runner with an embedded/alternate PostgreSQL implementation. Extend `scripts/db-test.sh` and `supabase/tests` only when the active slice needs new verification.
- Work in one bounded vertical slice at a time.
- Search before creating. There must be one canonical implementation for money, authorization, project identity, status, formatting, and UI primitives.
- Do not add an abstraction for a single implementation or a shared module for a single consumer.
- Record material architecture, accounting, authorization, and scope choices as ADRs.
- Do not add a dependency or provider unless the current slice uses it and the platform/runtime cannot satisfy the need simply.
- Never edit an applied migration; add an ordered forward migration with recovery and verification notes.
- Preserve unrelated work and inspect the complete diff before committing.
- Do not deploy production or merge to `main` unless Mohamed explicitly requests it.
- Open a pull request for completed branch work and include scope, decisions, verification, risks, unresolved business dependencies, and the next gate.

## Verification expectations

Use the smallest truthful gate for the current phase. A documentation/governance-only change must prove its diff is restricted to documentation/governance and perform cross-document consistency checks; it must not claim runtime/database gates that were not needed or run.

Once runtime code exists in a changed slice, every completed slice must cover its affected layers and ultimately support:

- typecheck, lint, unit/integration/contract/E2E, and build;
- migration replay and upgrade paths;
- two-tenant RLS and investor self-scope;
- atomicity, concurrency, idempotency, reversal, and period-lock behavior;
- Arabic/RTL, responsive, accessibility, and failure-state verification;
- secret/dependency/static security checks.

Do not claim a gate passed unless it was run against the reported commit and environment.

## Definition of complete

A task is complete only when the requested outcome is implemented, relevant evidence is committed, targeted verification passes, the diff contains no legacy leakage or secrets, unresolved business dependencies are explicit, and the PR clearly states what remains outside scope.

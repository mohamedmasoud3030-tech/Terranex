# Terranex Greenfield — Agent Policy

**Effective:** 2026-08-10
**Status:** Canonical for `greenfield/foundation` and all descendant Greenfield branches

## Mission

Build Terranex as a greenfield Investment Operations OS for private investment operators in real estate, agriculture, and livestock. The shared investment, finance, control, and audit core is built once; sector behavior remains inside explicit bounded contexts.

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
10. `GREENFIELD_EXECUTION.md`
11. `docs/decisions/0001_PRODUCT_FIRST_BUILD.md`

No deleted or archived Terranex file is authoritative. The frozen legacy snapshot is recorded in `docs/LEGACY_FREEZE.md` and exists only for forensic reference.

## Non-negotiable boundary

- Do not refactor, port, or recreate legacy business logic by default.
- Do not copy legacy entities, migrations, workflows, routes, financial rules, tests, or product documentation into Greenfield.
- A generic technical fragment may be reused only after a written assessment proves it matches the Greenfield contracts and introduces no hidden domain assumption.
- Do not build equal depth for three sectors. The first paid design partner selects the first sector pack; real estate is only the tie-break default.
- Terranex is a private operational system in v1, not crowdfunding, custody, a public marketplace, or a statutory general ledger.

## Current delivery gate

Current phase: **Phase 1 — architecture runway and executable product foundation**.

Terranex follows a **product-first** strategy. Customer interviews, a design partner, or customer documents are not prerequisites for implementation. Build the common Investment Operations Core from the approved Greenfield model, established industry patterns, authoritative standards, and explicit test scenarios; then configure or extend it for each company without forking the core.

Before material financial/domain implementation:

- record ADRs for tenancy, accounting boundary, money representation, agreement versioning, posting/reversal, authorization, and offline scope;
- trace material workflows and accounting behavior to an approved Greenfield decision, authoritative standard, or documented product assumption;
- create executable acceptance fixtures for the common J1–J8 workflows, including normal, correction, approval, multi-currency, and multi-tenant cases;
- keep Egypt-specific tax, statutory accounting, e-invoicing, and regulatory behavior isolated behind country configuration or integrations until professionally validated.

The first operating market is Egypt. Arabic/RTL, EGP, Egyptian document terminology, and Egypt-ready configuration are launch priorities, but country-specific rules must not be hardcoded into the shared core. Real estate remains the first sector-pack default unless Mohamed explicitly changes it.

## Target architecture

- TypeScript modular monolith.
- Maintained Next.js App Router release and Arabic-first responsive PWA.
- PostgreSQL through Supabase, Supabase Auth, private Storage, and default-deny RLS.
- Server-side transactional commands for material writes.
- Immutable financial facts, balanced postings, reversals instead of destructive edits, idempotency, maker-checker controls, audit, and transactional outbox.
- Offline drafts only; never offline financial posting or approval.
- Package/import direction: UI → application → domain; infrastructure implements ports; sector packages never depend on each other.

## Financial and security rules

- Never use floating point for money.
- Every tenant-owned record carries `organization_id`; cross-tenant references require database-enforced integrity.
- Material commands are atomic, idempotent, version-aware, authorized, and auditable.
- Posted facts are append-only; corrections use reversal/repost with a complete chain.
- The browser never supplies authoritative balances, entitlements, or approval outcomes.
- No secrets, real credentials, personal data, or unsanitized customer artifacts enter Git.
- Do not access or modify production data, Supabase, Vercel, banking, or external accounting systems without explicit authorization.

## UX rules

- Arabic/RTL is the primary experience; English/LTR remains supported.
- Mobile-first density, WCAG 2.2 AA, keyboard support, and honest loading/error/empty/offline/conflict states are required.
- Keep navigation shallow and project-centered; do not introduce nested page-within-page or tab sprawl.
- Do not imply that a draft, pending approval, unreconciled amount, or failed sync is final.

## Change discipline

- Work in one bounded vertical slice at a time.
- Record material architecture, accounting, authorization, and scope choices as ADRs.
- Do not add a large dependency or external provider without documenting why the existing stack cannot satisfy the requirement.
- Never edit an applied migration; add an ordered forward migration with recovery and verification notes.
- Preserve unrelated work and inspect the complete diff before committing.
- Do not deploy production or merge to `main` unless Mohamed explicitly requests it.
- Open a pull request for completed branch work and include scope, decisions, verification, risks, and the next gate.

## Verification expectations

Use the smallest truthful gate for the current phase. Once runtime code exists, every completed slice must cover its affected layers and ultimately support:

- typecheck, lint, unit/integration/contract/E2E, and build;
- migration replay and upgrade paths;
- two-tenant RLS and investor self-scope;
- atomicity, concurrency, idempotency, reversal, and period-lock behavior;
- Arabic/RTL, responsive, accessibility, and failure-state verification;
- secret/dependency/static security checks.

Do not claim a gate passed unless it was run against the reported commit and environment.

## Definition of complete

A task is complete only when the requested outcome is implemented, relevant evidence is committed, targeted verification passes, the diff contains no legacy leakage or secrets, and the PR clearly states what remains outside scope.

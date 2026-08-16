# ADR 0032 — R8 Cross-Sector Asset & Performance Layer

**Status:** Accepted for R8
**Date:** 2026-08-16

## Context

R8 in `docs/greenfield/08_MVP_AND_DELIVERY_ROADMAP.md` asks to "unify what
can be unified without distorting each sector: asset register, acquisition
cost, current approved valuation, operating income/cost, … project/portfolio/
sector performance — so the owner sees how much Real Estate, Livestock and
Agriculture each made, where capital is, where cash is, and which projects
are losing."

The obvious reading of "asset register" is a shared `assets` table that the
three sectors write into. **That reading is not authorized**, and building it
would have been the single most damaging change available in this repository.

`docs/greenfield/03_DOMAIN_MODEL.md:175` states that sector tables connect
through `investment_project_id` and their own roots; they do not share one
universal asset activity table. Line 64 adds that portfolio membership does
not merge project assets, cash, liabilities, agreements or investor
economics. §9 lists "one 'transaction' table mixing draft, cash, revenue,
cost, journal and bank statement concepts" and "polymorphic strings without
referential integrity for financial dimensions" among the prohibited
shortcuts — a universal asset table is the same anti-pattern applied to the
asset dimension. §3 permits creating an aggregate or table only when an
approved vertical slice uses it.

## Decision

**R8 is delivered as a read-only projection over sector-owned roots, never
as a new base table and never as a new foreign-key target.**

The migration `20260816059000_r8_cross_sector_asset_and_performance.sql`
creates exactly two views and nothing else:

- `cross_sector_asset_register_read` — unions `property_assets`,
  `agricultural_land_assets`, `farms` and `livestock_sites`, each joined to
  its project, sector and current parent portfolio.
- `sector_performance_read` — per organization, sector and project currency:
  project count, asset count, cash, revenue, cost of sale, expense, WIP,
  contributions, receivables, payables and realized result.

The migration contains no `create table`, no `alter table`, no
`create function`, no `security definer`, and no DML. There is no
`actions.ts` and no `rpc.ts` in `src/features/assets/`. Every asset shown
remains written, validated and owned by its own sector slice. Deleting both
views would remove reporting and destroy no fact.

### Absent facts are stated, never guessed

The register spans sectors with genuinely different maturity. Real Estate has
acquisitions, approved valuations and recognized sales; Agriculture has land
control basis but no valuation policy; Farms and Livestock Sites have no
acquisition concept at all. Emitting `0` for the missing cells would tell an
operator "this asset cost nothing" or "this asset is worth nothing" — a
fabricated figure, which is precisely what the domain model forbids.

Every money column is therefore paired with a `*_status` column, and a
missing figure is `NULL` alongside a status that explains *why*:

| Status | Meaning |
|---|---|
| `NOT_RECORDED` | The fact belongs to this asset kind but has not been entered |
| `NOT_APPLICABLE_NO_ACQUISITION_FACT` | The concept does not exist for this asset kind |
| `NOT_MODELLED_FOR_THIS_ASSET_KIND` | No state machine exists for this kind |
| `UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY` | No approved policy exists yet |
| `CONTRACTED_CONSIDERATION_AND_CLOSING_COSTS` | Real-estate acquisition basis |
| `AGREED_CONSIDERATION` | Agricultural land consideration basis |
| `APPROVED_VALUATION` / `NO_APPROVED_VALUATION` | R5 valuation state |
| `REALIZED_ON_RECOGNIZED_SALE` / `NO_RECOGNIZED_SALE` | R5 disposal state |

`UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY` is deliberately the same token
`livestock_cohort_results_read` already uses for the same idea, so the schema
does not grow a second dialect for "we will not guess this".

The distinction between `NOT_RECORDED` and
`NOT_APPLICABLE_NO_ACQUISITION_FACT` is load-bearing and is preserved into
Arabic ("لم تُسجَّل بعد" vs "لا ينطبق على هذا النوع من الأصول"): one is a data-entry
gap the operator can close, the other is a category error. Collapsing both to
a dash would reintroduce the ambiguity the read model exists to remove.

Only `APPROVED` valuations reach the register; a merely `PROPOSED` valuation
is never promoted, and the database gate proves it.

### Roll-up follows the existing F10 canon

`sector_performance_read` is reporting-only and never a ledger. It sums
project-authoritative facts, never mixes currencies (the project currency is
part of the grouping key), and carries the established
`NO_REPORTING_CURRENCY | SAME_CURRENCY | NO_RATE_SNAPSHOT | CONVERTED_AT_RATE`
ladder. Conversion uses `fx_convert_exact`; no floating-point arithmetic
touches money at any layer.

Two refinements beyond a naive roll-up:

1. **No partial converted totals.** Each `converted_*` column is `NULL`
   unless *every* project in the group converted. Summing only the
   convertible subset would produce a smaller-but-plausible number that reads
   as a complete total — a worse failure than reporting nothing.
2. **Driven off the project register, not the finance spine.**
   `project_financial_position_read` only contains projects that already
   carry financial facts. Joining from it would have silently dropped a newly
   registered project — and its assets — from its own sector until someone
   posted money against it. The view therefore starts from
   `investment_projects` and left-joins the spine. The database gate asserts
   conservation of both projects and assets, and this exact regression was
   verified to fail the gate.

### Tenancy is inherited, not re-implemented

Both views are `security_invoker=on`. Every underlying root already enforces
`select using (is_active_member(organization_id))`, so the caller's own RLS
applies and cannot drift from the sector policy. The views grant `SELECT` to
`authenticated` only, with `public` and `anon` revoked.

The database gate proves cross-tenant isolation *as a real `authenticated`
role*, not as the owning superuser — RLS is bypassed for the table owner, so
an isolation claim made as `postgres` would prove nothing.

## Verification

`supabase/tests/92_r8_cross_sector_asset_and_performance.sql` was validated
by mutation: reverting each of the four decisions above (emitting a zero cost
for farms, dropping `security_invoker`, inner-joining the finance spine,
weakening the status/amount pairing) makes the gate fail with a specific
message. The first mutation initially survived, which exposed that asserting
the status text alone was insufficient; the gate now asserts that an absence
status carries no amount *and* no currency, plus the converse — that any
reported amount is explained by a matching status.

## Consequences

- The owner gets the R8 cross-sector view without any sector losing ownership
  of its own assets.
- R2's remaining "Asset core" and R8's "cross-sector asset layer" are
  satisfied as reporting, leaving the sector roots free to evolve
  independently.
- No part of this slice depends on an OPEN item in
  `docs/OPEN_BUSINESS_DECISIONS.md`; it introduces no ownership, entitlement,
  allocation or distribution semantics, and so does not approach the R13 hard
  stop.
- If a future approved decision genuinely requires a shared asset aggregate,
  it must arrive as its own ADR with a vertical slice that writes to it. This
  ADR deliberately does not pre-build that table.

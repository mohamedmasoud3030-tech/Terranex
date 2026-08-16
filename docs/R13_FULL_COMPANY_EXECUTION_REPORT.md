# R13 — Full Synthetic Company Execution Report

**Date:** 2026-08-16  
**Executable gate:** `supabase/tests/95_r13_full_company_scenario.sql`  
**CI evidence:** PR #149, Greenfield CI database job `95166027797` — PASS (2m53s)  
**Policy boundary:** R14 was not started.

## Integrated company proved

The final PostgreSQL gate promotes the already-posted R5 rental fixture into the named target organization **المجموعة العربية المتحدة**, retains a hostile second organization, creates two management Portfolios, and composes:

- one Real Estate project with an actual held property and posted rental chain;
- one Agriculture project with its sector-authoritative Farm root;
- two independent Livestock projects in the same Portfolio, each with its own Site root;
- canonical Portfolio assignment, historical move and return;
- a project RiskItem on only one of the two Livestock projects;
- authenticated hostile-tenant reads against project, asset, governance, rental, journal and organization-report surfaces.

No universal Asset table, Portfolio ledger, investor allocation, ownership entitlement, distribution, waterfall or cross-project pooling was introduced.

## Exact reconciliation evidence

The posted rental chain supplies non-zero evidence rather than a fabricated all-zero scenario:

| Measure | Sum(Project authoritative rows) | Portfolio roll-up | Organization BY_CURRENCY | Difference |
|---|---:|---:|---:|---:|
| Revenue recognized (EGP minor units) | 120000 | 120000 | 120000 | 0 |
| Cash (EGP minor units) | 70000 | 70000 | 70000 | 0 |
| Open receivable (EGP minor units) | 50000 | 50000 | 50000 | 0 |

The gate also calculates and compares cost of sale, project expense, WIP, contributions, open payable, paid and retention from authoritative Project rows to both F10 levels and requires every difference to equal zero. No expected zero is hardcoded for those measures.

The rental recognition journal is balanced at 120000 debit = 120000 credit; collection changes cash/receivable but not revenue; the bank statement line has one active allocation. Those facts are produced and asserted by gate 93 and consumed by the final integrated gate.

## Isolation evidence

The final gate requires:

- four current Projects in the operating Portfolio;
- exactly two Livestock Projects in that Portfolio;
- one Site per Livestock Project and no sibling Site leakage;
- one RiskItem in Livestock A and zero in Livestock B;
- three append-only Agriculture assignment rows after move-out/move-back, with exactly one current parent;
- zero hostile-tenant rows across all six queried security surfaces, executed after switching to the real `authenticated` role.

## Why this gate composes earlier gates

`db-test.sh` replays every migration and then runs SQL/concurrency gates in filename order in one fresh PostgreSQL database. R13 is the last gate. It cannot pass if any preceding procurement, finance-control, Real Estate, Agriculture, Livestock, exact-money, FX, period-close, correction, idempotency, concurrency, RLS or security-definer test fails. Gate 95 integrates the resulting authorized facts and hierarchy; it does not duplicate production commands or bypass them with a synthetic second ledger.

## Status boundary

- **R1–R13 independent technical scope:** COMPLETE on the CI-proved PR head.
- **Production/pilot claims requiring a deployed environment, customer records, restore execution in that environment, legal evidence or owner acceptance:** REAL-WORLD EVIDENCE BLOCKED, not represented as complete by a synthetic gate.
- **BD-001…BD-012 and investor/legal/economic semantics:** POLICY BLOCKED.
- **R14:** NOT STARTED.

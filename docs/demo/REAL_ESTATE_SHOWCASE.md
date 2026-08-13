# Permanent Real Estate Showcase Demo

## Status

This dataset is a permanent presentation fixture for Terranex. **Do not delete it during normal testing, cleanup, pilot preparation, or migration work.**

It is synthetic demo data only. It is not customer evidence, does not satisfy canonical Phase 2 or Phase 3 exit criteria, and must never be presented as real buyer/UAT evidence.

## Live identity

- Organization: `شركة أفق النيل للاستثمار العقاري – DEMO`
- Project: `مشروع واحة سفنكس – المرحلة الأولى (DEMO)`
- Internal reference: `DEMO-RE-2026-001`
- Live project ID: `0556711f-0605-4ff4-bf6c-e65492eb9c5b`
- Currency: EGP
- Strategy: `DEVELOP_SELL`
- Freeze date: 2026-06-30

## Scenario

The permanent showcase exercises the real S0-S7 operating path and production controls:

- two investors with a 60/40 governing allocation and EGP 35,000,000 total contributed capital;
- a controlled EGP 5,000,000 opening position posted through S7 with exact debit/credit equality;
- one main property acquisition, closing costs, site-preparation budget and development lifecycle;
- EGP 25,000,000 total capitalized acquisition/development cost;
- EGP 34,000,000 approved sale and collection;
- EGP 1,500,000 direct selling cost left payable;
- EGP 7,500,000 realized result;
- July 2026 closed and August 2026 open;
- a 60/40 result allocation and EGP 3,000,000 approved/paid distribution;
- EGP 41,000,000 final project cash;
- EGP 39,500,000 partner capital plus EGP 1,500,000 supplier payable;
- nine signed-off S7 reconciliation checkpoints with zero total variance;
- one disposed asset and one expansion asset still in `DUE_DILIGENCE` so the workspace demonstrates both completed and live pipeline work.

There is deliberately no fabricated customer UAT, bank statement, or external document. Evidence identifiers point to synthetic demo references only.

## Seed source

`/scripts/demo/seed_real_estate_showcase.sql`

The seed is an explicit, idempotent operational fixture, not a migration and not an automatic startup seed. It uses the production command/RPC surfaces for financial and lifecycle facts. Re-running after the project exists is a no-op.

The demo maker Auth identity is intentionally retained for maker/checker history. Its credentials are not stored in the repository.

Presentation login is a real authenticated membership. See `docs/demo/PRESENTATION_ACCESS.md`.

## Protection rule

Do not delete or reset this project unless the repository owner explicitly requests deletion of the permanent Terranex showcase. Database cleanup scripts must exclude internal reference `DEMO-RE-2026-001`.

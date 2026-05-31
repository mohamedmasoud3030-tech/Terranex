# Terranex — Investment Operating System

## Runtime status

Terranex uses the production runtime only. Fresh browser profiles start empty by design.

## Core runtime

- `src/core/storage/localStorageStore.ts` provides typed local storage access and cross-tab synchronization.
- `src/core/storage/migrations.ts` runs safe one-time migrations before the application renders.
- `src/core/lib/profitability.ts` calculates profitability from transactions and obligations.
- `src/core/lib/deletionGuards.ts` prevents deletion when linked financial or operational records exist.
- `src/core/lib/validation.ts` provides runtime validation helpers.

## Main features

- Projects
- Assets
- Partners
- Documents
- Transactions
- Obligations
- Operational events and stock adjustments
- Sector views for real estate, agriculture, and livestock
- Arabic-first RTL interface

## Data policy

The production runtime does not create demo projects, fixture assets, sample transactions, or sample obligations automatically.

Recoverable legacy finance records migrate into the supported ledger stores. Records that cannot be mapped safely remain preserved for audit without invented project or partner links.

## Profitability definitions

- Accounting profit equals income minus expenses.
- Open receivables and open payables are displayed separately.
- Cash exposure equals open receivables minus open payables.

## Local verification

Use the existing package scripts to run type checking, linting, and the production build before deployment.

# Odoo Egypt Investor Accounting Runbook

This document describes the server-side accounting boundary for the first Egyptian Terranex deployment.

## Source of truth

Terranex owns the operational and investor lifecycle. Odoo receives approved accounting events only:

- Bank/cash accounts
- Customer and supplier invoices and payments
- Explicit posted manual vouchers and their reversal vouchers
- Approved profit distributions
- Bank-backed partner capital contributions and withdrawals
- Distribution payments and append-only reversals

Draft distributions, derived reporting projections, and manual cash-like partner ledger rows are never posted to Odoo.

## Required Egyptian configuration

Install `account` and `l10n_eg`. Configure a unique company, a miscellaneous journal, bank/cash journals, and the following unique account codes:

- `ODOO_PARTNER_CAPITAL_ACCOUNT_CODE`: partner capital/equity control
- `ODOO_RETAINED_EARNINGS_ACCOUNT_CODE`: retained earnings used when a distribution is approved
- `ODOO_DISTRIBUTION_PAYABLE_ACCOUNT_CODE`: partner distribution payable control

The bridge fails closed when an account code is absent or ambiguous. It does not create or guess chart-of-account entries.

## Posting sequence

1. Run `odoo-sync` so partner, project, invoice, payment, and bank-journal mappings exist.
2. Run `odoo-investor-sync` for approved distributions and partner cash events.
3. A distribution payment remains unavailable until its approved distribution has an Odoo move mapping.
4. A financial reversal remains unavailable until its original partner-ledger entry has an Odoo move mapping.
5. Failed events remain in the durable PostgreSQL outbox with retry history.

## Accounting entries

- Distribution approval: debit retained earnings, credit distribution payable by partner.
- Capital contribution: debit bank/cash, credit partner capital.
- Capital withdrawal: debit partner capital, credit bank/cash.
- Distribution payment: debit distribution payable, credit bank/cash.
- Reversal: post an independent move with the original debit and credit sides exchanged.

## Production gate

Do not enable the bridge until the Egyptian chart codes, bank journal default accounts, company ID, miscellaneous journal, Odoo API secret, and Supabase Edge Functions have been verified in a non-production Odoo database. ETA e-invoicing remains a separate onboarding phase.
# Terranex Domain Model

This document defines the first business vocabulary for Terranex.

## Core entities

### Sector

A top-level investment area.

Initial sectors:

- Real estate
- Agriculture
- Livestock

### Project

A business initiative that collects costs, revenues, documents, and operational records.

Examples:

- Buying and developing a land asset
- A crop season for a farm
- A herd purchase and sale cycle

### Asset

An owned or controlled economic resource.

Examples:

- Land
- Farm
- Building
- Equipment
- Herd
- Animal group

### Partner

A person or company with ownership, funding, management, supply, sales, or liability relationship.

### Transaction

A financial movement.

Minimum fields:

- Date
- Direction: income or expense
- Amount
- Currency
- Counterparty
- Project
- Asset if applicable
- Document link if available
- Category
- Notes

### Document

A source artifact attached to a project, asset, transaction, or partner.

Examples:

- Contract
- Invoice
- Receipt
- Ownership document
- Medical or veterinary record
- Sales agreement

### Obligation

A payable or receivable record.

Core question:

- Who owes money?
- Who should be paid?
- What transaction or agreement caused this obligation?

## Profitability model

Profitability should be computed by project and can be rolled up to sector and company level.

Basic formula:

Profit = total income - total expense - open provisions if applicable

## Audit requirement

Any answer about profit, loss, receivables, or payables must be traceable to source transactions and documents.

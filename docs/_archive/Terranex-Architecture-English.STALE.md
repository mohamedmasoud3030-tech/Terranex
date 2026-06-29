# TERRANEX
## Investment Operating System

Real Estate • Agriculture • Livestock

# Complete Architecture Document
Version 1.0 — May 2026

## 1. System Vision

Terranex is not merely a data-recording application. It is the company's digital brain. Its purpose is to answer, at any moment, three fundamental questions:

| Question | Answer Provided by the System |
|----------|------------------------------|
| How much did we profit? | Actual profit per project, sector, and partner, supported by every transaction and document. |
| Who owes us, and whom do we owe? | A live view of receivables and payables linked to contracts and invoices. |
| What proves what we claim? | Every figure is linked to a document or decision that can be audited. |

### Core Product Principle
Every number in the system must be traceable back to its source: the transaction that created it, the document that supports it, and the partner associated with it.

## 2. The Three Sectors

The system is designed to manage three investment sectors with different operational characteristics while sharing the same accounting foundation:

### 2.1 Real Estate Investment
- Assets: Land, buildings, residential units
- Operations: Purchase, development, sale, leasing
- Costs: Construction, maintenance, legal fees
- Revenue: Sales, rent, profit sharing

### 2.2 Agricultural Investment
- Assets: Farms, agricultural land, equipment
- Seasons: Planting and harvesting cycles
- Crops: Wheat, vegetables, dates
- Profitability: Total sales minus total seasonal costs

### 2.3 Livestock Investment
- Herds: Cattle, sheep, camels
- Operating Costs: Feed, treatment, vaccinations
- Events: Birth, death, purchase, sale
- Profitability: Sales revenue minus care and feeding costs

## 3. Domain Model

### Entity Map

PROJECT
├── ASSET
├── TRANSACTION
├── PARTNER
├── DOCUMENT
└── OBLIGATION

Profitability Engine

### 3.1 Project Entity

The project is the primary container. Everything belongs to a project.

Fields:
- id
- name
- sector
- status
- start_date
- description

### Why is the Project Important?
Without linking transactions to projects, it is impossible to determine which investments generated profit and which generated losses.

### 3.2 Transaction Entity

A transaction represents an actual financial movement.

Fields:
- id
- project_id
- date
- direction (income / expense)
- amount
- currency
- category
- counterparty
- document_link
- notes

### 3.3 Asset Entity

An asset is anything owned by the company that remains over time.

Examples:
- Land
- Farm
- Herd

Fields:
- name
- type
- acquisition_date
- acquisition_cost
- current_value
- sector
- location

### 3.4 Partner Entity

A partner is any external party interacting financially with the company.

Fields:
- name
- type
- contact_info
- balance
- linked_projects
- linked_documents

### 3.5 Document Entity

A document is the legal or operational proof behind a transaction or decision.

Document Types:
- Contract
- Invoice
- Receipt
- Deed
- Report
- Decision

### 3.6 Obligation Entity

An obligation represents an unpaid amount.

Fields:
- type (Receivable / Payable)
- partner_id
- amount
- due_date
- source_document
- status

## 4. Profitability Engine

### Core Formula

Profit = Total Income − Total Expenses

Every income and expense entry must be linked to a project, transaction, and supporting document.

### Analysis Levels
- Project
- Sector
- Partner
- Time Period
- Asset

### Profitability Calculation Mechanism

For each project, the system automatically:
1. Sums all income transactions.
2. Sums all expense transactions.
3. Calculates the difference as net profit or loss.

### Accounts Receivable and Payable Management

The system automatically determines who owes whom based on outstanding obligations.

## 5. Data Flow

Example:

1. Feed is purchased for OMR 8,000.
2. Invoice INV-2026-0091 is uploaded.
3. An expense transaction is created.
4. A payable obligation is created.
5. Payment is recorded and linked to a receipt.
6. Profitability metrics are updated automatically.

## 6. User Interface — Main Screens

### 6.1 Dashboard
- KPIs
- Cash flow charts
- Asset allocation charts
- Latest projects
- Obligation alerts

### 6.2 Project Management
- Project list
- Detailed project pages
- Progress indicators
- Financial summaries

### 6.3 Transaction Ledger
- Chronological financial records
- Advanced filtering
- Linked document and partner details

### 6.4 Obligation Management
- Open receivables and payables
- Due-date tracking
- Partial payment support

### 6.5 Reports & Analytics
- Profitability reports
- Receivables/payables reports
- Asset performance reports
- Operational reports
- PDF and Excel export support

## 7. Technical Architecture

### 7.1 Technology Layers

| Layer | Responsibility | Technology |
|---------|---------------|------------|
| Frontend | User Interface | React + TypeScript + Tailwind CSS |
| Database | Data Storage | Supabase (PostgreSQL) |
| Business Logic | Profitability & Obligations | Supabase Edge Functions |
| Authentication | Access Control | Supabase Auth |
| Document Storage | Files & Documents | Supabase Storage |

### 7.2 Database Structure

Core Tables:
- projects
- transactions
- assets
- partners
- documents
- obligations
- sectors

### 7.3 Technical Design Principles

1. Every financial transaction must belong to at least one project.
2. Linked entities with active transactions cannot be deleted.
3. Every change is logged through an Audit Trail.
4. Financial figures are calculated in real time.
5. Access is role-based (Owner, Manager, Accountant, Read-only).

## 8. Roadmap

### Phase 1 — Foundation (4–6 Weeks)
- Database
- Authentication
- Projects
- Core Transactions

### Phase 2 — Financial Layer (4–5 Weeks)
- Profitability Engine
- Obligation Management
- Financial Document Linking

### Phase 3 — Reporting (3–4 Weeks)
- Analytical Dashboard
- Exportable Reports

### Phase 4 — Enhancements (Ongoing)
- Notifications
- Mobile Application
- External Integrations

### Success Criteria

The system is considered successful when a user can answer:
“How much profit did Project X generate?”
within 10 seconds, with complete traceability to the original transaction and supporting document.

## 9. Terminology

| Term | Meaning |
|------|---------|
| Domain Model | Map of entities and relationships |
| Entity | Any object stored by the system |
| Profitability Engine | Profit calculation layer |
| Audit Trail | Full change history |
| CRUD | Create, Read, Update, Delete |
| Obligation | Outstanding receivable or payable |
| KPI | Key Performance Indicator |
| Supabase | Open-source backend platform used by Terranex |

---

Terranex Architecture Document
Version 1.0 — May 2026
Living document, continuously updated with each development phase.

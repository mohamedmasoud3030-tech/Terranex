# Terranex Greenfield — 05 Finance & Accounting Model

**Status:** Foundational finance contract v1  
**Purpose:** Exact project financial attribution plus approved investor-capital behavior. Portfolio roll-ups are derived management views. This is an accounting design input, not a claim of IFRS, tax, or statutory compliance.

## 1. Accounting boundary

Terranex is the source of truth for project operations, project financial attribution, approved investment terms, operational obligations, and posted monetary events. Partner capital, allocations, and distributions are authoritative only to the extent that their governing business terms are explicitly approved. Portfolio is a management/reporting layer over projects, not a second ledger. It maintains a balanced double-entry **investment/operational subledger** so every balance is reproducible.

The customer’s statutory general ledger remains external in v1. Terranex exports approved journal batches and references the returned external IDs. There is no second editable “official” ledger competing with it.

## 2. Non-negotiable invariants

1. Monetary amounts are stored in integer minor units with ISO currency; calculations use decimal/rational arithmetic and explicit rounding.
2. Every posted batch balances: debits equal credits in transaction-currency handling and functional-currency amount.
3. Every material line has organization, project, account, date, source event, and posting-rule version.
4. Posted batches, allocation runs, and approved statements are immutable.
5. Corrections use linked reversal and replacement; reversal date follows period policy.
6. One source version posts once through an idempotency key and uniqueness constraint.
7. Cash, revenue, cost, commitment, valuation, allocation, payable, and payment are separate facts.
8. Ownership/allocation terms, when approved and used, are effective-dated; historical results use the historical version. Never infer them from portfolio membership, cash deployment, or contribution history.
9. A closed period rejects normal posting; late posting or reopen requires approval and leaves evidence.
10. No distribution payment can be created from a dashboard number; it requires an approved distribution liability.

## 3. Ledgers and books

| Book/view | Purpose | Source |
|---|---|---|
| Project subledger | Asset, liability, income, cost, cash, and equity movements by project/sector object | Posted journal lines |
| Partner capital ledger | Commitment, called, contributed, allocated income/loss, distributions, receivable/payable | Posted capital/accounting events |
| Cash/bank subledger | Book movements and bank reconciliation | Receipts/payments + statement matches |
| Obligation ledger | Supplier/customer/partner amounts due and settlement state | Obligations, invoices/claims, settlements |
| Operational inventory/asset rollforward | Quantity and cost linkage | Sector events + financial postings |
| Statutory export | Approved summarized/detailed batches for external GL | Posting projection, never manual re-entry |

## 4. Account taxonomy

Use organization-configurable accounts under locked semantic roles. Reports query semantic roles, not hard-coded account numbers.

| Class | Required semantic roles (examples) |
|---|---|
| Assets | cash, bank clearing, receivable, contribution receivable, inventory, biological asset, property inventory, development WIP, investment property/PPE bridge, prepaid cost |
| Liabilities | supplier payable, accrued cost, investor distribution payable, loan payable, customer advance, tax/withholding clearing |
| Equity/capital | contributed capital, partner current account, retained/allocated result, drawings/distributions contra |
| Income | property sale, crop sale, livestock sale, other project income, valuation gain bridge if policy permits |
| Costs | cost of asset/output sold, farm inputs, feed, health, labor/contractor, project overhead, selling cost, loss/mortality/spoilage, finance cost |
| Control | opening balance clearing, suspense, inter-project due-to/from, FX gain/loss, external-GL clearing |

Control/suspense balances must appear on close checklists and cannot be hidden in profit.

## 5. Dimensions

Required line dimensions:

- organization;
- project;
- semantic account;
- transaction and posting dates;
- currency and functional amount;
- source type/ID/version;
- counterparty when applicable;
- sector object (parcel/phase, cycle/field/lot, herd/cohort/animal) when applicable;
- investor/participant when capital-related;
- cost/revenue category;
- document and approval references.

Dimensions are normalized references with integrity constraints, not arbitrary tags for material balances.

## 6. Core posting events

Illustrative entries show economic intent. Final account mapping is selected by the organization’s approved policy.

| Business fact | Debit | Credit |
|---|---|---|
| Capital call approved | Contribution receivable/control (optional memorandum or recognized per policy) | Called capital/control |
| Contribution cash received | Cash | Contributed capital or contribution receivable |
| Supplier obligation for expensed service | Project expense | Supplier payable |
| Supplier obligation for capitalizable development | WIP/asset/inventory | Supplier payable |
| Supplier payment | Supplier payable | Cash |
| Input purchased into stock | Input inventory | Supplier payable/cash |
| Input issued to crop/herd | Cycle/cohort cost or biological asset per policy | Input inventory |
| Crop harvested | Produce inventory at approved measurement | Agriculture/biological recognition bridge per policy |
| Sale recognized on delivery/control transfer | Receivable/cash | Sector revenue |
| Output/asset cost derecognized | Cost of sales | Inventory/asset carrying amount |
| Customer collection | Cash | Receivable |
| Mortality/spoilage recognized | Loss/sector cost | Biological asset/inventory |
| Income/loss allocated to partner | Project result clearing | Partner capital (direction reverses for loss) |
| Distribution approved | Partner capital/distribution equity | Distribution payable |
| Distribution paid | Distribution payable | Cash |
| Posted event reversed | Exact inverse with linkage | Exact inverse with linkage |

Cash receipts never create revenue automatically unless the business event and posting rule explicitly represent cash sale. A bank-statement import never posts project economics by itself.

## 7. Currency and exchange

- Organization has one functional/reporting currency for v1, recommended EGP for Egypt launch.
- Source event retains transaction currency and original amount.
- Posting stores rate, source, rate timestamp/date, rate type, functional amount, and rounding residual.
- Rate changes never rewrite posted functional amounts.
- Settlement differences post to explicit realized FX gain/loss.
- Management reports may translate “as of” balances using a separate reporting-rate projection; translated report values never become ledger truth.

## 8. Commitments, ownership, capital, and entitlement

These values must not be collapsed:

- **commitment**: agreed maximum/schedule;
- **called capital**: approved request;
- **contribution receivable**: amount legally/operationally due under policy;
- **contributed capital**: accepted posted value received;
- **ownership interest**: economic/control percentage or units for an effective period;
- **profit/loss allocation**: agreement-driven entitlement to result;
- **distribution payable**: approved value due to participant;
- **cash paid**: settled distribution.

Partner capital rollforward:

$$
ClosingCapital = OpeningCapital + Contributions + AllocatedIncome - AllocatedLoss - Distributions + OtherApprovedCapitalAdjustments
$$

“Other adjustment” is a controlled transaction type, not a free-form balance edit.

### Portfolio capital deployment is not investor capital

Keep these concepts mechanically separate:

- **portfolio capital deployment**: approved management/funding decision to make value available to a project;
- **project funding/accounting mechanism**: the actual posted form of the movement, such as company cash deployment, inter-project due-to/from, loan, equity/current-account movement, or another approved treatment;
- **investor contribution**: value accepted from an identified participant under an approved investor/project agreement;
- **ownership interest**: legal/economic/control interest under approved terms;
- **result allocation**: assignment of realized income/loss under approved rules;
- **distribution**: approved payable/transfer of value to a participant;
- **payment**: settlement of the approved payable.

A single cash movement must never be relabeled across these concepts merely because the amounts happen to match. Cross-project movement, pooling, recycling, and netting require an explicit owner-approved business/accounting rule before implementation.

## 9. Allocation engine v1

### Mechanism vs business rule

The engine is a **mechanism for executing an already-approved rule**, not authority to invent the rule. The formulas below are capability patterns only; enabling one for a company/project requires documented governing terms and the hard-stop decisions in `docs/OPEN_BUSINESS_DECISIONS.md` where applicable.

### Supported when explicitly governed

- pro-rata by effective ownership units/percentage;
- fixed participant shares that sum to 100%;
- operator/manager share as an explicit expense, fee, or allocation based on signed policy;
- date-segmented allocation when agreement terms change;
- deterministic largest-remainder or nominated-residual rounding;
- allocation of realized income/loss and separately identified categories;
- loss carryforward at participant/project scope if the agreement requires it.

### Deferred / not inferable

Portfolio-level pooling or entitlement, cross-project netting/recycling, contribution-to-ownership inference, and any rule not evidenced by approved terms are deferred. Preferred return, hurdle tiers, GP catch-up, carried interest, European/American waterfalls, clawback, and tax withholding calculation also remain deferred. These need dedicated legal/accounting validation and, only when justified, an implementation mechanism; they are not hidden in generic formulas.

### Calculation snapshot

Every run stores:

- project and period;
- source close/snapshot ID;
- agreement/rule version;
- eligible participants and effective ranges;
- allocable categories and exact inputs;
- calculation algorithm version;
- line-level result and rounding residual;
- prepared/reviewed/approved actors and timestamps;
- content hash and reversal link.

Re-running with current data creates a comparison, never overwrites the approved run.

## 10. Profitability and performance

Portfolio profitability is a **derived roll-up of project-authoritative measures** with explicit currency, date, valuation, and completeness basis. It does not create a portfolio P&L ledger or a portfolio distributable balance by itself.

### Required project measures

| Measure | Definition |
|---|---|
| Cash position | Reconciled book cash by project/account plus visible unreconciled items |
| Realized operating result | Recognized income less recognized costs for the period/policy |
| Cost to date | Posted project costs, separated capitalized/expensed |
| Committed cost | Approved obligations not yet fully recognized/settled |
| Forecast at completion | Actual + open commitments + approved forecast remainder |
| Management valuation | Latest approved valuation with date/method/source; separate from realized result |
| Net asset view | Assets less liabilities under selected policy and data completeness |
| Distributable cash | Approved formula: available cash less restricted/reserve/near-term obligations |
| MOIC | Total value/distributions basis divided by contributed capital, with basis disclosed |
| IRR/XIRR | Dated cash-flow return using disclosed scope; never displayed without data-quality status |

Do not show one unlabeled “profit.” At minimum distinguish realized result, unrealized valuation movement, cash surplus, and distributable cash.

## 11. Asset and sector accounting policy matrix

| Area | Captured operational truth | Accounting decision owned by policy/accountant |
|---|---|---|
| Property | control, purpose, costs, phases, valuation, disposal | IAS 2 vs IAS 16 vs IAS 40 classification and measurement |
| Crops | biological transformation, inputs, harvest quantity/date/lot | IAS 41 measurement and gain/loss; IAS 2 after harvest |
| Livestock | birth/acquisition, count/weight, health, mortality, sale | biological asset classification/measurement under IAS 41 or other applicable policy |
| Revenue | contract/order, delivery/control event, collection | IFRS 15 recognition and variable consideration policy |
| Impairment/valuation | evidence, model, assumptions, reviewer | IAS 36/IFRS 13 or local GAAP treatment |

Terranex must collect enough evidence for a qualified accountant to apply the policy, but product copy must not claim automatic IFRS compliance.

## 12. Period close

Close gates:

1. all journal batches balance and have required dimensions;
2. bank lines are reconciled or explained;
3. suspense/control accounts are zero or approved exceptions;
4. payable/receivable aging reviewed;
5. inventory/headcount/asset rollforwards reconcile;
6. missing documents and pending material approvals resolved;
7. FX rates and posting rules complete;
8. sector cycle/milestone cut-off confirmed;
9. partner capital rollforward balances to equity/control totals;
10. close report and exception evidence approved.

Closing stores control results and locks through a database-enforced rule. Reopen records reason, approver, affected statements, and revised-close version.

## 13. Bank reconciliation

- Import statement lines as immutable external facts with account, date, amount, currency, description, and provider fingerprint.
- Detect duplicate imports using account + provider ID/hash.
- Match one-to-one, one-to-many, or many-to-one only through an explicit reconciliation group.
- Suggested matches are non-posting and show confidence/reasons.
- Unidentified cash goes to clearing/suspense only through approved posting; later reclassification uses a linked entry.
- Book and bank balances are shown separately with reconciling items.

## 14. External accounting and tax integration

When an external accounting adapter is actually implemented, its contract includes batch ID/version, lines, account mapping, dimensions, currency, source refs, document refs, and checksum. Export status is pending/sent/accepted/rejected/reversed. Durable outbox delivery is added in that integration slice, not scaffolded in advance.

Egypt’s ETA exposes e-invoicing/e-receipt APIs for taxpayer ERP/POS systems. Integration is a later adapter with pre-production certification, signing, document-version mapping, throttling, cancellation/rejection flows, and secure server-side credentials; browser code never holds tax-system secrets.

## 15. Financial acceptance tests

- randomized journal batches cannot post unbalanced;
- duplicate command/posting keys produce one material effect;
- historical allocation is unchanged after a new agreement version;
- concurrent distribution/payment requests cannot over-distribute;
- closed period rejects ordinary post and preserves approved late-post route;
- reversal exactly negates source and links replacement;
- cross-organization and cross-project references are rejected;
- partner capital statement rolls forward exactly from postings;
- currency/rounding property tests preserve totals;
- import/reconciliation retries are idempotent.

## Sources

- [IFRS IAS 40 — Investment Property](https://www.ifrs.org/issued-standards/list-of-standards/ias-40-investment-property/)
- [IFRS IAS 41 — Agriculture](https://www.ifrs.org/issued-standards/list-of-standards/ias-41-agriculture/)
- [IFRS 11 — Joint Arrangements](https://www.ifrs.org/issued-standards/list-of-standards/ifrs-11-joint-arrangements/)
- [IFRS 15 — Revenue from Contracts with Customers](https://www.ifrs.org/issued-standards/list-of-standards/ifrs-15-revenue-from-contracts-with-customers/)
- [IFRS IAS 2 — Inventories](https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/)
- [IFRS IAS 16 — Property, Plant and Equipment](https://www.ifrs.org/issued-standards/list-of-standards/ias-16-property-plant-and-equipment/)
- [ILPA Reporting Template](https://ilpa.org/industry-guidance/templates-standards-model-documents/ilpa-templates-hub/ilpa-reporting-template/)
- [Egyptian Tax Authority eInvoicing API](https://sdk.invoicing.eta.gov.eg/einvoicingapi/)

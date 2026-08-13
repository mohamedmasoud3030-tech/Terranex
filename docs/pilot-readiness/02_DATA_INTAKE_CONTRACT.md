# 02 — Real Customer Data Intake Contract (First Real Estate Pilot)

**Purpose:** the exact source artifacts the first Real Estate pilot customer must prepare, how each is validated, and how each enters Terranex **using only the existing S0–S7 capabilities**. This contract adds no import functionality; anything that cannot enter through an existing command is evidence-only and stays in the customer's systems.

**Scope:** one pilot organization, one or more selected Real Estate projects, all positions as of the agreed **opening freeze date** (gate PRM-03).

## 0. Global intake rules

| Rule | Requirement |
| --- | --- |
| Currency | All amounts in EGP, expressed as **integer minor units (piastres)** — `1,250.00 EGP` is `125000`. No decimals, no thousands separators in delivered files. |
| Dates | ISO 8601 (`YYYY-MM-DD`). Every balance dataset carries one explicit as-of date = the freeze date. |
| Encoding | UTF-8. Arabic and Latin digits are both tolerated by the product's normalizer, but delivered preparation files use Latin digits to avoid transcription ambiguity. |
| Identifiers | Every delivered row carries a stable customer-side reference (contract number, account number, call notice number). Terranex never invents identifiers for the customer. |
| Names | Person/legal-entity names as they appear on the governing documents (2–160 characters in the product; longer names must be abbreviated consistently and the full name kept as evidence). |
| Control totals | Every balance-bearing dataset ships with a customer-declared control total **in writing** (signed or emailed from the customer finance lead). A dataset without a declared total is rejected at gate PRM-04. |
| Documents | Source documents are **never delivered into this repository or into Terranex storage** (v1 has no document storage; evidence references are identifiers pointing at the customer's own systems — see `docs/runbooks/README.md`). |
| Rejection standard | A row failing any validation rule is returned to the customer for correction at source. There is no "import anyway" path: the S7 opening import refuses to post while any row is rejected. |

**Preparation worksheets** (blank, header-only): `templates/opening-import-worksheet.csv`, `templates/source-data-coverage-tracker.csv`, `templates/pilot-evidence-register.csv`.

**Dataset coverage legend:** `MANDATORY` — pilot cannot pass PRM-04 without it; `CONDITIONAL` — mandatory only when the fact exists for the selected project; `EVIDENCE-ONLY` — never imported, referenced only.

---

## DS-01 — Organization

| Item | Value |
| --- | --- |
| Enters Terranex via | Organization creation flow (S0) — configured, not imported |
| Authoritative source | Customer commercial registration / company constitutive document |
| Mandatory | MANDATORY |

| Field | Required | Format / validation |
| --- | --- | --- |
| Organization name | yes | 2–120 characters, as registered |
| Functional/reporting currency | yes | Fixed to `EGP` in v1 (product constraint, not customer choice) |

- **Control total:** none (configuration record).
- **Rejection condition:** name does not match the registered name the buyer will sign against.
- **Evidence:** commercial registration reference recorded in the pilot evidence register.

## DS-02 — Investment projects

| Item | Value |
| --- | --- |
| Enters Terranex via | Project shell creation flow (S0) |
| Authoritative source | Customer project list agreed in the pilot scope |
| Mandatory | MANDATORY (at least one) |

| Field | Required | Format / validation |
| --- | --- | --- |
| Project name | yes | 2–160 characters |
| Internal reference | optional | ≤ 80 characters customer code; unique within organization |
| Sector | yes | `REAL_ESTATE` only in v1 (product constraint) |
| Reporting currency | yes | `EGP` only in v1 (product constraint) |
| Description | optional | free text ≤ project form limit |

- **Control total:** count of pilot projects = count in the signed pilot scope.
- **Rejection condition:** a project outside the signed pilot scope; a project whose reporting currency the customer insists must be non-EGP (deferred capability — escalate, do not improvise).
- **Evidence:** signed pilot scope reference.

## DS-03 — Parties and project participants (investors)

| Item | Value |
| --- | --- |
| Enters Terranex via | S1 party and project-participant commands |
| Authoritative source | Governing agreements; national IDs/commercial registers for identity checks performed by the **customer** (Terranex performs no KYC decisioning) |
| Mandatory | MANDATORY |

| Field | Required | Format / validation |
| --- | --- | --- |
| Legal name | yes | 2–160 characters, exactly as in the agreement |
| Party type | yes | `PERSON` or `ORGANIZATION` |
| Project membership | yes | every investor party is attached to its project(s) as role `INVESTOR` (the only participant role in v1) |
| Contact details | optional | kept in customer systems (EVIDENCE-ONLY); not required for any S1–S7 flow |

- **Control total:** number of investor parties = number of participants in the governing agreement; each appears exactly once per project (product uniqueness constraint).
- **Rejection condition:** duplicate legal name for the same person/entity (create one party, reuse it); a "participant" who does not appear in any governing agreement.
- **Evidence:** agreement signature-page reference listing the participants.

## DS-04 — Signed agreements

| Item | Value |
| --- | --- |
| Enters Terranex via | S1 agreement version activation (immutable governing version) with its commitment/ownership/allocation terms |
| Authoritative source | The signed agreement effective at the freeze date |
| Mandatory | MANDATORY |

| Field | Required | Format / validation |
| --- | --- | --- |
| Agreement title/reference | yes | as named by the customer |
| Effective date | yes | ISO date; must be ≤ freeze date |
| Participants and commitments | yes | see DS-05 |
| Ownership/allocation basis | yes | shares must resolve to exactly 100% with a deterministic rounding policy (S5 allocation basis requires weights summing exactly to 100%) |
| Signed document | n/a | EVIDENCE-ONLY: document reference recorded; the signed PDF stays in the customer's systems |

- **Control total:** participant shares sum = 100.000…% exactly.
- **Rejection condition:** shares that do not sum to 100; side letters that modify entitlement but are not reflected in the activated terms — the customer must decide the governing content explicitly; Terranex does not merge unwritten terms.
- **Evidence:** signed agreement reference + activation record in the product (immutable version). Amendments/supersessions beyond the governing version are an explicitly deferred capability; a pilot project requiring a mid-pilot amendment is a scope decision, not a data-intake fix.

## DS-05 — Commitments

| Item | Value |
| --- | --- |
| Enters Terranex via | S1 commitment terms inside the governing agreement version |
| Authoritative source | Agreement schedule of commitments |
| Mandatory | MANDATORY |

| Field | Required | Format / validation |
| --- | --- | --- |
| Participant | yes | must match a DS-03 party |
| Committed amount | yes | integer minor units > 0 |
| Currency | yes | `EGP` |
| Schedule/due structure | optional | recorded as terms; v1 holds the commitment as maximum/scheduled value, not cash received |

- **Control total:** Σ commitments per participant = agreement schedule; Σ all commitments = total project commitment stated in the agreement.
- **Rejection condition:** commitment without participant; amount ≤ 0; commitment contradicting the signed schedule.
- **Evidence:** agreement schedule reference. Commitment ≠ called capital ≠ contributed capital; these are never collapsed (per `05_FINANCE_AND_ACCOUNTING.md` §8).

## DS-06 — Capital calls (history to freeze date)

| Item | Value |
| --- | --- |
| Enters Terranex via | S1 capital call commands (one call with lines per historical notice) |
| Authoritative source | Issued call notices |
| Mandatory | CONDITIONAL (when calls were issued before the freeze date) |

| Field | Required | Format / validation |
| --- | --- | --- |
| Call reference | yes | notice number |
| Due date | yes | ISO date ≤ freeze date |
| Line: participant | yes | DS-03 match |
| Line: amount | yes | integer minor units > 0, EGP |
| Status | yes | issued or cancelled (product states `ISSUED`/`CANCELLED`) |

- **Control total:** Σ call lines = Σ issued notice amounts − cancelled notices, per the customer's call register.
- **Rejection condition:** call line with no participant match; call dated after the freeze date (belongs to pilot live operation, not intake).
- **Evidence:** call notice references listed in the evidence register.

## DS-07 — Contributions (history to freeze date)

| Item | Value |
| --- | --- |
| Enters Terranex via | S1 contribution records against calls; cash effect via the S2 controlled contribution-to-cash attribution command — **or** via the S7 opening bank-cash row when the cash side is part of the opening bank position (choose one route per contribution; never both — see `03_OPENING_BALANCE_CONTROL_PACK.md` §3 mapping review) |
| Authoritative source | Bank advices / receipt records |
| Mandatory | CONDITIONAL (when contributions were received before the freeze date) |

| Field | Required | Format / validation |
| --- | --- | --- |
| Call reference | yes | must match DS-06 |
| Participant | yes | must match the call line's participant |
| Amount | yes | integer minor units > 0, EGP |
| Receipt date | yes | ISO date ≤ freeze date |

- **Control total:** Σ contributions per participant ≤ Σ call lines per participant (over-contribution must be explicitly justified and approved by the customer before entry — the product proves over-contribution behavior in tests; intake must not rely on accident).
- **Rejection condition:** contribution without matching call; amount exceeding remaining called amount without written customer justification; receipt after freeze date.
- **Evidence:** bank advice/receipt references per contribution.

## DS-08 — Bank and cash accounts

| Item | Value |
| --- | --- |
| Enters Terranex via | S2 project cash account creation |
| Authoritative source | Customer bank account list used for the pilot project(s) |
| Mandatory | MANDATORY (if any cash movement exists — always true for a live project) |

| Field | Required | Format / validation |
| --- | --- | --- |
| Account name | yes | 2–120 characters |
| Currency | yes | must equal the project reporting currency (`EGP` — single-currency by construction in v1) |
| Project | yes | one account belongs to exactly one project |
| Bank account number | n/a | EVIDENCE-ONLY — not stored in Terranex v1; statements carry the provider's own fingerprint |

- **Control total:** count of accounts = count in the customer's account list for the pilot projects.
- **Rejection condition:** an account in a currency other than EGP (escalate as deferred FX capability); one account used across projects.
- **Evidence:** customer account list reference.

## DS-09 — Opening balances

| Item | Value |
| --- | --- |
| Enters Terranex via | **S7 controlled opening import only** — `DRAFT → VALIDATED → READY_FOR_APPROVAL → APPROVED → POSTED`, schema `S7.OPENING.V1` |
| Authoritative source | Customer trial balance signed as of the freeze date |
| Mandatory | MANDATORY |

One row per balance, using **only** the six locked mapping codes:

| Field | Required | Format / validation |
| --- | --- | --- |
| mapping_code | yes | exactly one of `OPENING_BANK_CASH`, `OPENING_DEVELOPMENT_WIP`, `OPENING_CUSTOMER_RECEIVABLE`, `OPENING_SUPPLIER_PAYABLE`, `OPENING_CONTRIBUTED_CAPITAL`, `OPENING_DISTRIBUTION_PAYABLE` |
| party_reference | conditional | required for `OPENING_CUSTOMER_RECEIVABLE`, `OPENING_SUPPLIER_PAYABLE`, `OPENING_CONTRIBUTED_CAPITAL`, `OPENING_DISTRIBUTION_PAYABLE`; forbidden for `OPENING_BANK_CASH`/`OPENING_DEVELOPMENT_WIP`; party must exist in the organization |
| cash_account_reference | conditional | required for `OPENING_BANK_CASH`; forbidden otherwise; account must belong to the project |
| debit_minor_units / credit_minor_units | exactly one | non-negative integer minor units, 1–19 digits; both set = rejection (`BOTH_SIDES_SET`); neither set = rejection (`NO_AMOUNT`); side contradicting the mapping's natural side = rejection (`SIDE_CONTRADICTS_MAPPING`) |
| description | yes | 1–500 characters; unsafe control characters rejected |

- **Control totals (all exact to the minor unit):** declared debit total = computed debit total; declared credit total = computed credit total; debits = credits; variance = 0 or the import does not post.
- **Rejection conditions:** the twelve product reasons — `UNKNOWN_MAPPING_CODE`, `PARTY_REQUIRED`, `PARTY_NOT_ALLOWED`, `PARTY_NOT_IN_ORGANIZATION`, `CASH_ACCOUNT_REQUIRED`, `CASH_ACCOUNT_OUT_OF_SCOPE`, `INVALID_AMOUNT`, `BOTH_SIDES_SET`, `NO_AMOUNT`, `SIDE_CONTRADICTS_MAPPING`, `DUPLICATE_ROW_IN_FILE`, `DESCRIPTION_INVALID`. **Any** rejected row blocks posting (rejected-row atomicity).
- **Balances that fit no mapping code:** report them as a real modelling gap (ADR 0009 §1) and resolve commercially — do not force them into the nearest code.
- **Evidence:** source file name + SHA-256 checksum stored on the import record; signed trial balance reference in the evidence register. Full procedure: [`03_OPENING_BALANCE_CONTROL_PACK.md`](03_OPENING_BALANCE_CONTROL_PACK.md).

## DS-10 — Unpaid obligations (payables due at freeze date)

| Item | Value |
| --- | --- |
| Enters Terranex via | opening rows `OPENING_SUPPLIER_PAYABLE` (balance) — subsequent settlement during the pilot via normal S2 obligation/payment flows |
| Authoritative source | Supplier statements / accounts payable aging at freeze date |
| Mandatory | CONDITIONAL |

| Field | Required | Format / validation |
| --- | --- | --- |
| Supplier party | yes | DS-03 match (party type PERSON or ORGANIZATION) |
| Amount due | yes | integer minor units > 0, EGP |
| Underlying invoice/contract reference | yes | recorded in the row description (≤ 500 chars) and evidence register |

- **Control total:** Σ unpaid obligations = AP aging total at freeze date.
- **Rejection condition:** payable without a counterparty; payable already settled before freeze date; amount inconsistent with the supplier statement.
- **Evidence:** AP aging report reference; supplier statement references.

## DS-11 — Property assets and parcels

| Item | Value |
| --- | --- |
| Enters Terranex via | S3 commands: real-estate project profile → property assets → parcels → control records |
| Authoritative source | Title documents / cadastral records / sale contracts |
| Mandatory | MANDATORY for Real Estate projects |

| Field | Required | Format / validation |
| --- | --- | --- |
| Profile strategy | yes | the project's real-estate strategy (`ACQUIRE_HOLD`, `DEVELOP_SELL`, or `LAND_TRADE`) |
| Asset name | yes | 2–160 characters |
| Asset reference | optional | ≤ 80 characters |
| Parcel identifier | yes | 1–100 characters, unique per asset |
| Cadastral reference | optional | ≤ 120 characters |
| Legal description | optional | ≤ 1000 characters |
| Area quantity | yes | decimal > 0 (product precision numeric(20,6)) |
| Area unit | yes | `M2`, `HECTARE`, or `FEDDAN` |
| Control/title evidence | n/a | EVIDENCE-ONLY: title document references; "no 'owned' state without acquisition/control evidence" is a product control (04_SECTOR_MODELS.md §2) |

- **Control total:** Σ parcel areas per asset = total area in the acquisition/title document; asset count = project asset list.
- **Rejection condition:** parcel with zero/negative area; unit outside the three allowed; asset claimed "owned" with no control/acquisition evidence reference.
- **Evidence:** title/cadastral references per parcel in the evidence register.

## DS-12 — Acquisition basis

| Item | Value |
| --- | --- |
| Enters Terranex via | S3 acquisition command (one acquisition per asset) |
| Authoritative source | Acquisition contracts |
| Mandatory | CONDITIONAL (assets already acquired at freeze date) |

| Field | Required | Format / validation |
| --- | --- | --- |
| Seller party | yes | DS-03 match |
| Contract reference | yes | 2–120 characters |
| Consideration | yes | integer minor units > 0, EGP |
| Closing costs | optional | integer minor units ≥ 0, EGP |
| Contract date | yes | ISO date |
| Evidence reference | yes | 3–200 characters; mandatory product field |

- **Control total:** Σ (consideration + closing costs) per asset = contract totals; ties to the development-WIP/carrying position the opening import expresses.
- **Rejection condition:** acquisition without contract reference or evidence reference (product-mandatory); consideration contradicting the signed contract.
- **Evidence:** signed contract reference; payment history (if pre-freeze) reconciled through DS-07/DS-09.

## DS-13 — Development costs

| Item | Value |
| --- | --- |
| Enters Terranex via | S3 budget versions/lines, development phases/milestones; cumulative cost-to-date at freeze date enters as `OPENING_DEVELOPMENT_WIP` opening rows; post-freeze costs via S2 obligations/payments and S3 cost items |
| Authoritative source | Approved budgets; cost ledgers at freeze date |
| Mandatory | CONDITIONAL (projects with development activity) |

| Field | Required | Format / validation |
| --- | --- | --- |
| Budget lines (category, amount) | yes | integer minor units > 0, EGP; budget versions are immutable once approved |
| Development phases | optional | planned dates, budget, milestones per phase |
| Cost-to-date at freeze | yes | per asset/phase, integer minor units; must equal Σ `OPENING_DEVELOPMENT_WIP` opening rows |
| Cost treatment | yes | every post-freeze obligation declares `EXPENSE` or `CAPITALIZABLE_WIP` explicitly — never guessed (S2 policy) |

- **Control total:** Σ opening WIP rows = cost ledger total at freeze date; budget total = approved budget document total.
- **Rejection condition:** cost-to-date ≠ opening WIP rows; budget with no approval evidence reference; cost items dated before the acquisition of their asset (chronology check).
- **Evidence:** approved budget reference; cost ledger extract reference.

## DS-14 — Sales and dispositions (if applicable)

| Item | Value |
| --- | --- |
| Enters Terranex via | post-freeze: S4 disposition → control transfer → recognition → selling costs → collection. Pre-freeze completed sales: **not recreated** — their residual effects enter only as opening rows (cash, receivables, capital position) |
| Authoritative source | Sale contracts |
| Mandatory | CONDITIONAL |

| Field (live dispositions) | Required | Format / validation |
| --- | --- | --- |
| Buyer party | yes | DS-03 match |
| Asset scope | yes | asset/parcel under disposition |
| Contract reference and date | yes | signed contract reference |
| Proceeds | yes | integer minor units > 0, EGP |
| Collection state at freeze | yes | open receivable → `OPENING_CUSTOMER_RECEIVABLE` row; collected → included in opening cash |

- **Control total:** Σ open sale receivables at freeze = Σ `OPENING_CUSTOMER_RECEIVABLE` rows. Disposal profit, when recognized live, uses recognized proceeds minus carrying amount and selling costs — never cash received alone (04_SECTOR_MODELS.md §2).
- **Rejection condition:** receivable without buyer; proceeds contradicting contract; a pre-freeze completed sale presented as if it should be re-recognized.
- **Evidence:** sale contract references.

## DS-15 — Historical distributions (if relevant)

| Item | Value |
| --- | --- |
| Enters Terranex via | approved-but-unpaid at freeze → `OPENING_DISTRIBUTION_PAYABLE` rows; already-paid history → EVIDENCE-ONLY, reflected in the opening capital/cash positions |
| Authoritative source | Distribution approval records / partner resolutions |
| Mandatory | CONDITIONAL |

| Field | Required | Format / validation |
| --- | --- | --- |
| Participant | yes | DS-03 match |
| Approved unpaid amount | yes | integer minor units > 0, EGP |
| Approval reference and date | yes | partner resolution reference |

- **Control total:** Σ unpaid distributions = partner resolution total still payable at freeze.
- **Rejection condition:** payable distribution without an approval reference; a "distribution" that is actually a loan or advance (the customer must classify it correctly — Terranex has no loan-payable opening mapping in v1, which is a modelling-gap report, not a workaround).
- **Evidence:** resolution references.

## DS-16 — Bank statements

| Item | Value |
| --- | --- |
| Enters Terranex via | S2 bank statement import (immutable external facts; duplicate detection by account + provider fingerprint) |
| Authoritative source | Bank-issued statements for every pilot account |
| Mandatory | MANDATORY from go-live; historical statements covering the pilot period's opening weeks are strongly recommended |

| Field | Required | Format / validation |
| --- | --- | --- |
| Account | yes | DS-08 match |
| Statement period | yes | contiguous, no gaps, ending dates aligned to weekly reconciliation dates |
| Line: date | yes | ISO date |
| Line: amount | yes | integer minor units, signed semantics per provider (debit/credit column preferred over sign) |
| Line: description | yes | as printed by the bank |
| Line: provider reference | yes | whatever stable ID the bank prints (used as the fingerprint) |

- **Control total:** statement closing balance per account = bank-confirmed balance; Σ imported lines per statement = closing − opening.
- **Rejection condition:** gaps in statement periods; duplicated provider references (the product detects and refuses duplicates); statement not issued by the bank (customer-reconstructed lists are not bank statements).
- **Evidence:** statements remain with the customer; import fingerprint references recorded.

## DS-17 — Supporting documents

| Item | Value |
| --- | --- |
| Enters Terranex via | **never imported** — evidence references (identifiers) only |
| Authoritative source | Customer document management / physical archive |
| Mandatory | MANDATORY as references for every material fact above |

| Field | Required | Format / validation |
| --- | --- | --- |
| Evidence identifier | yes | 3–200 characters, stable, unique within the engagement |
| Linked fact | yes | which dataset row/record it supports |
| Location | yes | where the customer stores it (system + reference) |

- **Control total:** every mandatory evidence reference in DS-01…DS-16 resolves to a real retrievable document on the customer side (spot-checked at PRM-05).
- **Rejection condition:** a material fact with no evidence reference; a reference that cannot be retrieved during the spot check.
- **Evidence:** `templates/pilot-evidence-register.csv` maintained by `<PILOT_OPS_OWNER>`.

---

## Intake sequence (binding order)

1. DS-01 organization → DS-02 projects (configuration).
2. DS-03 parties/participants → DS-04/DS-05 agreement and commitments → DS-06 calls → DS-07 contributions.
3. DS-08 cash accounts.
4. DS-11 assets/parcels → DS-12 acquisitions → DS-13 development baseline.
5. DS-09 opening balances (all remaining positions: cash, WIP, receivables, payables, capital, unpaid distributions) — one S7 import.
6. DS-10/DS-14/DS-15 residuals are expressed **inside** DS-09; they are separate preparation datasets, not separate imports.
7. DS-16 statements from go-live onward.

Gate mapping: PRM-04 (delivery), PRM-05 (quality), PRM-06 (opening import), PRM-07 (opening reconciliation).

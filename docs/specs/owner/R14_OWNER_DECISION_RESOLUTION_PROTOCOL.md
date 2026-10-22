# Terranex — R14 Owner Decision Resolution Protocol

**Status:** ACTIVE — owner-decision resolution gate  
**Effective:** 2026-08-17  
**Base state:** `main@c61672d72278878fba6392df66d64c15490e581f`  
**Target company:** المجموعة العربية المتحدة  
**Canonical register:** `docs/OPEN_BUSINESS_DECISIONS.md`  
**Owner questionnaire:** `docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md`  
**Technical impact analysis:** `docs/R14_POLICY_IMPACT_MATRIX.md`

## 1. Purpose

R1–R13 and the pre-owner policy-safety corrective engineering are complete for their authorized scopes. The remaining R14 work is not software invention; it is the controlled conversion of the target company's actual legal, funding, investor, allocation, distribution, tax, and lifecycle facts into explicit canonical decisions.

This protocol defines how BD-001…BD-012 may move from `OPEN` to `RESOLVED` without turning code, demo data, common market practice, or AI recommendations into company policy.

R15 remains **NOT STARTED / BLOCKED** until this protocol's admission gate passes.

## 2. Non-negotiable rules

1. A repository implementation fact is not business authority.
2. Existing S1/S5 mechanics, UI labels, fixtures, historical percentages, and synthetic scenarios cannot resolve a BD item.
3. External standards or common industry patterns may explain options but do not establish the target company's optional rule.
4. A BD item is resolved only by an explicit authorized decision with scope, effective context, evidence, and the required professional review.
5. If an answer differs by Project, Portfolio, agreement, investor class, jurisdiction, or effective period, the resolution must say so. Do not generalize it.
6. If part of an item is still undefined, do not mark the whole item `RESOLVED` unless the unresolved residue is explicitly outside the implementation being authorized and recorded under `Still deferred / not implied`.
7. No R15 implementation may activate target-company investor economics before `npm run r15:admission` passes.
8. This gate blocks only R15 policy-dependent scope. Security, data-integrity, bug fixes, and other policy-independent work remain allowed.

## 3. Resolution sequence

Resolve the decisions in three passes. The order reduces rework; it does not fabricate dependencies that the company has not approved.

### Pass A — Legal and funding foundation

| Decision | Required fact | Minimum resolving evidence | Professional review |
|---|---|---|---|
| BD-001 | Whether Portfolio is management-only or corresponds to a real legal/contractual vehicle | Explicit owner statement for management-only, otherwise registration/entity/pooled-contract evidence | Legal + accounting if not management-only |
| BD-002 | Actual Project capital sources | Contracts, loan documents, capital/current-account records, or equivalent owner-approved evidence | Accounting; legal for external investor/lender structures |
| BD-003 | Participation scope: Project, Portfolio, both, and whether terms vary | Actual investment contract/template or executed examples | Legal; accounting if Portfolio-level participation exists |
| BD-004 | Legal/economic meaning of ownership/interest | Corporate/partner register, agreement, title evidence, or other authoritative instrument | Legal primary + accounting |
| BD-005 | Actual funding mechanisms and which may coexist | Funding agreements, capital-call evidence, current-account ledgers, loan/intercompany evidence | Accounting + relevant legal review |

### Pass B — Economics, accounting, distribution and cross-Project rules

| Decision | Required fact | Minimum resolving evidence | Professional review |
|---|---|---|---|
| BD-006 | Realized profit and loss assignment rule, including whether loss differs from profit | Signed agreement or signed percentage/rule schedule | Accounting + legal |
| BD-007 | Treatment of unrealized valuations | Written accounting policy and any agreement clause creating valuation-linked rights | Accounting; legal if rights are valuation-linked |
| BD-008 | Actual distributable-cash deductions/reserves/liquidity rule | Written distribution policy or worked historical distribution examples | Accounting mandatory; legal where contract controls distribution |
| BD-009 | Operator/management fees, shares or other economics, or explicit absence | Contract clauses or documented management decision with calculation basis | Accounting + legal for any applicable economics |
| BD-010 | Terranex role for each applicable tax/withholding type | Accountant/tax-adviser statement of applicable taxes and computation responsibility | Accounting/tax mandatory; legal as applicable |
| BD-011 | Whether Project cash/capital may move, how, and whether any profits/losses/cash may be pooled or netted | Historical transfer/accounting evidence and relevant contract clauses | Accounting; legal where investor rights are affected |

### Pass C — Investor lifecycle

BD-012 is resolved last because entry, exit, transfer, withdrawal, default, succession and amendment behavior can depend on the meaning of the interest, participation scope, funding form, valuation treatment and economic rules already established above.

The resolution must address, at minimum:

- new investor entry to an existing investment;
- additional investment;
- partial withdrawal;
- early full exit;
- interest transfer/assignment;
- external sale/transfer;
- funding default and cure/consequence;
- death/incapacity/succession;
- legal-identity change;
- contractual notices and delivery evidence;
- statements/certificates and their contractual effect;
- approval authority for each applicable lifecycle event;
- agreement amendment/supersession behavior where lifecycle changes contract terms.

**Evidence:** the applicable contract/template and documented fixed management procedures.  
**Review:** legal primary; accounting for valuation, withdrawal, settlement and other financial consequences.

## 4. Canonical resolution procedure

For each BD item:

1. Read the matching section in `docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md` and `docs/R14_POLICY_IMPACT_MATRIX.md`.
2. Obtain the authorized target-company decision and identify its exact scope.
3. Attach/reference the supporting business evidence.
4. Obtain the accounting/legal review explicitly required for that decision. A review may state that no further review is required, but that conclusion must itself be attributable to the authorized reviewer where the canonical matrix requires professional input.
5. Update the BD row in `docs/OPEN_BUSINESS_DECISIONS.md` from `OPEN` to `RESOLVED` only when the record is complete.
6. Append a resolution record using the exact field names below.
7. Re-check that the authorized implementation is narrower than, or equal to, the evidence. Never let code imply rights the decision did not grant.
8. Run `npm run r15:admission`.

Required record shape:

```text
Decision ID: BD-00X
Status: RESOLVED
Decision date: <YYYY-MM-DD>
Decision owner: <authorized person/role>
Business decision: <explicit rule/fact>
Applies to: <organization / portfolio / project / agreement scope>
Effective date or version: <date/version/context>
Business evidence/reference: <document/decision reference>
Accounting review required? yes/no + reference: <yes/no and evidence/reference>
Legal review required? yes/no + reference: <yes/no and evidence/reference>
Affected canonical docs/ADRs: <references>
Implementation explicitly authorized: <bounded behavior now allowed>
Still deferred / not implied: <what this decision does not authorize>
```

## 5. R15 admission gate

Run:

```bash
npm run r15:admission
```

The gate fails if:

- any of BD-001…BD-012 has no canonical status row;
- any item remains `OPEN`;
- a `RESOLVED` row has no matching `Decision ID` record;
- the record does not state `Status: RESOLVED`;
- any required resolution field is missing, blank, placeholder-only, or still marked pending/unknown.

A passing gate proves only that the repository contains complete decision records. It does **not** independently prove that a lawyer/accountant actually approved a matter; the referenced evidence must exist and be truthful.

## 6. Current expected gate result

At `main@c61672d72278878fba6392df66d64c15490e581f`:

- BD-001…BD-012: `OPEN`;
- approved `policy_authority` for target-company investor economics: absent by design;
- R15: `NOT STARTED`;
- expected `npm run r15:admission`: **BLOCKED**.

That blocked result is correct until the authorized company decisions are recorded.

## 7. Definition of R14 decision-resolution complete

R14 owner-decision resolution is complete only when:

- all twelve BD rows are `RESOLVED`;
- each item has a complete canonical resolution record;
- evidence and required professional reviews are referenced truthfully;
- any scoped exceptions/deferred cases are explicit;
- `npm run r15:admission` passes;
- the resulting PR is reviewed for policy invention, accounting ambiguity, legal-scope overreach and cross-document consistency.

Only then may an R15 implementation branch begin from the merged, CI-green decision baseline.

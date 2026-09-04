# Terranex Implementation Plan Template

# Title

## 1. Intent

Describe the observable outcome and why it matters now.

## 2. Canonical authority

- AGENTS.md
- Relevant product/domain documents
- Relevant ADRs
- Relevant OPEN_BUSINESS_DECISIONS items

## 3. Current-state evidence

List current owners:
- code paths;
- database objects/migrations;
- tests/gates;
- runtime behavior;
- exact package versions.

## 4. Invariants

List the behaviors that must remain true.

## 5. Non-goals

List intentionally excluded work.

## 6. Implementation units

### IU-01 — Name

**Purpose**

**Depends on**

**Likely files / bounded locations**

**Contract or behavior**

**Migration / data impact**

**Verification**

**Cleanup / retirement**

**Rollback / recovery**

Repeat for each unit.

## 7. Review routing

| Surface | Required reviewer lens | Why |
| --- | --- | --- |

## 8. Verification matrix

| Layer | Evidence / command | Required |
| --- | --- | --- |

## 9. Risks and unresolved dependencies

Separate:
- implementation risks;
- external/version risks;
- unresolved business decisions.

## 10. Delivery notes

State:
- expected diff boundary;
- artifacts that must not be introduced;
- documentation/ADR updates;
- PR evidence required.

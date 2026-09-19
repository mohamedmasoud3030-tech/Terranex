# Terranex Threat Model Template

# Scope

**In scope**

**Out of scope**

**Repository evidence**

## System model

| Component | Role | Entry points | Data/assets |
| --- | --- | --- | --- |

## Trust boundaries

| ID | Boundary | Authentication | Authorization | Validation | Existing evidence |
| --- | --- | --- | --- | --- | --- |

## Assets

| Asset | Why it matters | Owner/boundary |
| --- | --- | --- |

## Attacker model

### Capabilities

### Non-capabilities

### Assumptions that affect ranking

## Abuse paths

### TM-01 — Short title

**Goal**

**Preconditions**

**Path**

**Assets impacted**

**Existing controls with evidence**

**Likelihood:** Low | Medium | High

**Impact:** Low | Medium | High

**Priority:** Low | Medium | High | Critical

**Reasoning**

**Mitigations**

**Verification**

Repeat for each material abuse path.

## Cross-tenant isolation summary

Describe:
- identity to organization mapping;
- RLS/server authorization enforcement;
- cross-tenant reference integrity;
- privileged bypass paths;
- negative tests.

## Residual risk

List accepted or unresolved risks and the evidence still needed.

## Recommended next verification

Prioritized tests, gates, or focused reviews.

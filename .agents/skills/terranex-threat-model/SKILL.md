---
name: terranex-threat-model
description: Use when the user explicitly asks for a Terranex threat model or when a proposed architecture materially changes authentication, authorization, RLS/tenant isolation, private storage/uploads, secret handling, privileged database functions, or an external trust boundary.
---

# Terranex Threat Model

Produce a repository-grounded AppSec threat model for the exact Terranex scope. Do not substitute a generic security checklist.

## Scope rules

- Evidence must come from the repository, deployment/config facts the user supplied, or authoritative documentation.
- Separate runtime behavior from CI/dev tooling and tests.
- Do not invent internet exposure, scale, attacker access, production topology, or data sensitivity.
- Treat tenant isolation as a first-class security boundary.
- Treat authentication artifacts, authorization state, private evidence/files, financial records, audit trails, secrets, and integrity-critical command state as candidate assets.
- A code review is not a threat model; a threat model is not a code review.

## Workflow

### 1. Build the system model

Identify:
- in-scope components;
- entry points;
- data stores;
- private storage;
- privileged database functions;
- external integrations;
- authentication/session flow;
- authorization/RLS path;
- deployment boundary only if evidenced.

Record excluded components explicitly.

### 2. Map trust boundaries

Describe concrete edges such as:
- browser to Next.js server runtime;
- server runtime to Supabase/PostgreSQL;
- authenticated identity to organization membership/authorization;
- application role to privileged database function;
- application to private storage.

For each edge, record evidenced authentication, authorization, validation, encryption, rate limiting, and logging controls. Do not assume a control exists because it is conventional.

### 3. Identify assets and attacker capabilities

List only assets that materially drive risk.

Describe realistic attacker capabilities and important non-capabilities. Where repository evidence cannot resolve context, state the assumption and show how it changes priority rather than blocking the analysis.

### 4. Enumerate abuse paths

Prefer concrete attacker goals:
- cross-tenant read/write;
- authorization bypass;
- session/token abuse;
- privileged-function escalation;
- financial-state tampering or replay;
- private-file disclosure;
- integrity compromise of audit/posting data;
- secret exposure;
- denial of critical operations.

Tie every threat to an asset and boundary.

### 5. Prioritize

Use qualitative likelihood and impact with concise evidence.

Adjust priority for existing controls that are proven in code/tests. Do not credit undocumented or untested controls.

### 6. Recommend mitigations

Each mitigation must:
- map to a specific component/boundary;
- identify the control type;
- distinguish existing control from new work;
- include a verification method;
- avoid inventing product/business policy.

Prefer database/server enforcement for authorization and integrity boundaries.

### 7. Quality check

Confirm:
- every in-scope entry point is considered;
- each material trust boundary appears in at least one threat or justified exclusion;
- tenant isolation is covered;
- privileged functions/storage are covered when present;
- assumptions are explicit;
- mitigations are testable;
- risk is not inflated by unsupported attacker capabilities.

## Output

Use references/threat-model-template.md.

Persist a threat-model file only when the user requests a repository artifact. Otherwise return the model in the conversation.

## Exit criteria

The model is complete when the architecture is evidence-backed, abuse paths are concrete, tenant and integrity boundaries are explicit, priorities explain likelihood and impact, and every recommended control has a verification path.

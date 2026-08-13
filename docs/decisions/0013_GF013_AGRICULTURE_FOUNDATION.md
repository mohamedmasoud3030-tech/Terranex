# ADR 0013 — GF-013 Agriculture Sector Foundation

**Status:** Accepted
**Date:** 2026-08-13
**Decision owner:** Mohamed

## Context

Terranex is implementing its authorized Agriculture bounded context as
the second sector after Real Estate (ADR 0012). The first batch
delivers `Farm → Field → CropCycle` as a thin vertical slice. This
document records the material decisions made by that slice; it does not
reopen the Real Estate path.

## Decision

### 1. Sector-aware project identity is added, never replaced

The authoritative `investment_projects.sector` constraint is expanded
from `REAL_ESTATE` to `REAL_ESTATE | AGRICULTURE`. The existing
4-argument `create_investment_project(uuid, uuid, text, text, text)`
RPC is preserved as a thin Real Estate compatibility wrapper. The new
5-argument `create_investment_project(uuid, uuid, text, text, text,
text)` RPC takes the explicit sector and is the canonical path for
the application.

The browser and server code use only the new RPC. The old signature
is retained solely so the S0 isolation suite and any older callers
keep working without modification. No overload ambiguity exists in
PostgREST because the new function has a different signature.

The actual selected sector is recorded in the immutable `audit_events`
payload for every `PROJECT_CREATED` event, and `sector` is now a
first-class column on the project row used by every application
projection.

### 2. Agriculture is a new bounded context under `src/features/agriculture`

A new feature folder `src/features/agriculture/{schema,actions,queries,labels}.ts`
holds all Agriculture code. Nothing Agriculture-related is placed
inside `src/features/real-estate`. The application route
`/projects/[projectId]/agriculture` is the sector workspace; the
existing nine-section Real Estate workspace is preserved untouched
and is reached by the same `/operations` path it has always used.

### 3. Aggregate boundaries are minimal and explicit

The Agriculture slice introduces exactly the data required by the
GF-013 mission:

* `farms` — operating location, tenure, IANA timezone, optional map
  reference, no GIS provider or external integration.
* `fields` — positive numeric area, explicit area unit drawn from the
  canonical `M2 | HECTARE | FEDDAN` vocabulary, optional soil /
  irrigation notes.
* `crop_cycles` — crop, variety, season reference, planned start and
  end dates, optional target yield quantity + unit, with one or more
  field assignments.
* `crop_cycle_field_assignments` — relational support row for the
  field-area invariant. It is implementation, not a separate sector
  entity.

No `FieldActivity`, `InputItem`, `InputLot`, `InputApplication`,
`HarvestEvent`, `HarvestLot`, `StorageLocation`, `InventoryMovement`,
agronomy observation, weather provider, map provider, offline/PWA, or
Livestock primitive is introduced. No placeholders or empty modules
are left behind for the deferred entities.

### 4. Field-area invariant is database-enforced

Three independent layers guarantee the invariant:

1. The server-authoritative `assign_crop_cycle_to_field` RPC takes a
   `FOR UPDATE` lock on the Field row plus a per-command advisory
   lock keyed on the idempotency key, then re-evaluates the
   overlapping total inside the same transaction.
2. A row-level `BEFORE INSERT` trigger
   `crop_cycle_field_assignments_capacity_check` re-checks the same
   invariant at the table boundary so direct SQL (including test
   fixtures and future migrations) cannot bypass it.
3. The check explicitly requires:
   * positive `assigned_area_quantity`;
   * `assigned_area_unit = field.area_unit`;
   * overlapping (half-open `[start, end)`) ranges whose
     `coalesce(agriculture_current_cycle_state(cycle), 'PLANNED') <>
     'CANCELLED'` are summed; their total must not exceed the field
     area;
   * boundary-touching ranges (`a.end = b.start`) are NOT considered
     overlapping.

### 5. Lifecycle model and concurrency control

The CropCycle lifecycle is exactly the six transitions documented in
`docs/greenfield/04_SECTOR_MODELS.md`:

* `PLANNED → ESTABLISHED`
* `ESTABLISHED → GROWING`
* `GROWING → HARVESTING`
* `HARVESTING → CLOSED`
* `PLANNED → CANCELLED`
* `GROWING → FAILED`

Every other transition, including skips, backward moves, and same-
state re-assertions, is rejected at the database boundary.

History is causal and append-only. The current state is derived from
the unique unconsumed chain tip
(`agriculture_current_cycle_history_tip_id`) — the same pattern the
S3 lifecycle chain-tip migration introduced — not from a
`changed_at`/UUID ordering that can choose an ancestor under
same-transaction writes. `UPDATE` and `DELETE` on
`crop_cycle_state_history` are refused by a trigger guard.

`transition_crop_cycle` is the only path that mutates lifecycle state.
Browser table updates are denied because the table is `REVOKE`d from
`anon` and `authenticated` and has no INSERT/UPDATE/DELETE policy;
only the security_invoker read view `crop_cycle_timeline_read` is
exposed to the `authenticated` role.

### 6. Authorization decision

Every Agriculture command:

* requires `auth.uid()`;
* requires `public.is_active_member(organization_id)`;
* requires the target `investment_projects.sector = 'AGRICULTURE'`;
* validates inputs at the database boundary;
* uses an 8-120 character idempotency key with a deterministic
  `sha256` request hash, refuses payload mismatch, and is
  `pg_advisory_xact_lock`-serialized per `(organization, command,
  key)`;
* writes an `audit_events` row in the same transaction.

OWNER remains authoritative for any action deliberately classified as
approval or activation; this slice does not invent a new role. The
default agriculture commands (create profile, farm, field, cycle;
assign; transition) are executable by any active member, exactly as
the S3 sector commands are. The slice does not add a new
maker/checker step; if a future slice needs OWNER approval, it will
be modeled as a separate command and not by silently downgrading
membership.

### 7. Sector-aware navigation, not a redesign

The Real Estate workspace keeps its nine sections untouched. The
Agriculture workspace is `/projects/[projectId]/agriculture` and is
shown as the truthful entry "المزرعة والمحاصيل". The project home
and the project cards display a truthful sector label
(`عقارات | زراعة`) and link to the sector-correct destination
(`/operations` for Real Estate, `/agriculture` for Agriculture). No
synthetic revenue / profitability / inventory / harvest / financial
KPI is fabricated.

## Consequences

* Real Estate creation, tests, and behavior are unchanged. The
  forward-upgrade test proves the pre-existing Real Estate row
  survives the migration untouched.
* Agriculture is a sibling feature, not a layered extension of
  Real Estate.
* The investment, finance, control, audit, authorization, idempotency,
  and workspace primitives are reused without change. No new ledger,
  payment engine, approval framework, or audit system is introduced.
* The deferred entities remain documented options, not installed
  infrastructure. Empty modules are not left behind.
* The local PostgreSQL 16 database gate is the canonical verification
  for this slice. The slice is intentionally a thin vertical slice;
  no real-customer evidence is required and none is fabricated.

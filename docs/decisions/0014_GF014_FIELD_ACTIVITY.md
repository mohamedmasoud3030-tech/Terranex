# ADR 0014 — GF-014 Field Activity Foundation

**Status:** Accepted
**Date:** 2026-08-13
**Decision owner:** Mohamed

## Context

GF-013 delivered `Farm → Field → CropCycle` and CropCycle-to-Field
assignments. Operators still cannot record what actually happened in
the field. This batch adds that operational fact only. It does not
open harvest, inventory, inputs, accounting, or CropCycle automation.

## Decision

### 1. Field Activity is an append-only operational fact

A `field_activities` row is tenant-owned and project-scoped. It must
reference:

* the Agriculture `investment_projects` row;
* an existing `crop_cycles` row;
* an existing `fields` row;
* the existing `crop_cycle_field_assignments` row that proves the
  Field belongs to the Cycle.

The composite foreign key on
`(assignment_id, organization_id, project_id, crop_cycle_id, field_id)`
is the coherence guarantee. A guessed Field or a Field from another
cycle cannot attach.

### 2. Controlled activity vocabulary

Only `PREPARE | PLANT | IRRIGATE | FERTILIZE | SPRAY | SCOUT | WEED | OTHER`
are accepted. The sector document also lists harvest as a later
activity kind; harvest is deferred with `HarvestEvent` and is not
admitted here.

Quantity and unit are optional but paired: both present and valid, or
both omitted. Recording an activity never transitions CropCycle state.

### 3. One command, one read view, existing audit

`create_field_activity` is the only mutation. It is
security-definer, membership-checked, sector-checked, idempotent
(`organization_id + key`, sha256 request hash, advisory lock), and
writes `FIELD_ACTIVITY_CREATED` to the existing `audit_events` table.

`field_activities_read` is the security-invoker read model. Direct
authenticated INSERT/UPDATE/DELETE is revoked. A BEFORE UPDATE/DELETE
trigger refuses mutation even for privileged SQL.

### 4. UI stays inside the Agriculture workspace

Arabic/RTL listing and recording live on
`/projects/[projectId]/agriculture#activities`. Navigation adds a
truthful "أنشطة الحقل" entry. Real Estate labels and queries are not
used. No raw UUIDs are shown to operators (assignment is labeled by
crop, season, and field identifier).

## Consequences

* GF-013 rows, Real Estate behavior, and existing commands are
  unchanged.
* Inputs, harvest, inventory, IAS 41, weather, GIS, livestock, and
  generic workflow remain deferred.
* The local PostgreSQL 16 gate is canonical. Absence of `psql`/Docker
  is reported as unresolved, never simulated.

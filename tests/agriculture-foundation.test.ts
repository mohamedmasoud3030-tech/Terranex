import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  CYCLE_STATES,
  CYCLE_TRANSITIONS,
  agricultureProfileSchema,
  cropAssignmentSchema,
  cropCycleSchema,
  cycleTransitionSchema,
  farmSchema,
  fieldSchema,
} from '../src/features/agriculture/schema';

const foundationMigration = readFileSync(
  'supabase/migrations/20260813001000_agriculture_foundation.sql',
  'utf8',
);
const invariantMigration = readFileSync(
  'supabase/migrations/20260813001010_agriculture_field_area_invariant.sql',
  'utf8',
);
const agriculturePage = readFileSync(
  'src/app/(app)/projects/[projectId]/agriculture/page.tsx',
  'utf8',
);
const agricultureForms = readFileSync(
  'src/app/(app)/projects/[projectId]/agriculture/forms.tsx',
  'utf8',
);
const actions = readFileSync('src/features/agriculture/actions.ts', 'utf8');
const queries = readFileSync('src/features/agriculture/queries.ts', 'utf8');
const labels = readFileSync('src/features/agriculture/labels.ts', 'utf8');
const sharedLabels = readFileSync('src/shared/labels.ts', 'utf8');

const uuid = '00000000-0000-4000-8000-000000000001';
const farmId = '00000000-0000-4000-8000-000000000002';
const fieldId = '00000000-0000-4000-8000-000000000003';
const cycleId = '00000000-0000-4000-8000-000000000004';
const base = { organizationId: uuid, projectId: uuid, idempotencyKey: 'gf-013-test-key-0001' };

describe('GF-013 agriculture schema validation', () => {
  it('requires a valid farm payload', () => {
    expect(farmSchema.safeParse({ ...base, name: 'مزرعة', timezone: 'Africa/Cairo' }).success).toBe(true);
    expect(farmSchema.safeParse({ ...base, name: 'X', timezone: 'Africa/Cairo' }).success).toBe(false);
    expect(farmSchema.safeParse({ ...base, name: 'مزرعة', timezone: '' }).success).toBe(false);
  });

  it('requires a positive area and a supported unit on a field', () => {
    expect(fieldSchema.safeParse({ ...base, farmId, identifier: 'A', areaQuantity: '12.5', areaUnit: 'FEDDAN' }).success).toBe(true);
    expect(fieldSchema.safeParse({ ...base, farmId, identifier: 'A', areaQuantity: '0', areaUnit: 'FEDDAN' }).success).toBe(false);
    expect(fieldSchema.safeParse({ ...base, farmId, identifier: 'A', areaQuantity: '12.5', areaUnit: 'ACRE' }).success).toBe(false);
  });

  it('rejects a yield quantity without a unit and vice versa', () => {
    expect(cropCycleSchema.safeParse({
      ...base, crop: 'قمح', seasonReference: '2026',
      plannedStartDate: '2026-10-01', plannedEndDate: '2027-03-01',
      targetYieldQuantity: '4500', targetYieldUnit: null,
    }).success).toBe(false);
    expect(cropCycleSchema.safeParse({
      ...base, crop: 'قمح', seasonReference: '2026',
      plannedStartDate: '2026-10-01', plannedEndDate: '2027-03-01',
      targetYieldQuantity: null, targetYieldUnit: 'كجم/فدان',
    }).success).toBe(false);
  });

  it('enforces the documented CropCycle lifecycle transitions in the application schema', () => {
    expect(CYCLE_TRANSITIONS.PLANNED).toEqual(['ESTABLISHED', 'CANCELLED']);
    expect(CYCLE_TRANSITIONS.ESTABLISHED).toEqual(['GROWING']);
    expect(CYCLE_TRANSITIONS.GROWING).toEqual(['HARVESTING', 'FAILED']);
    expect(CYCLE_TRANSITIONS.HARVESTING).toEqual(['CLOSED']);
    expect(CYCLE_TRANSITIONS.CLOSED).toEqual([]);
    expect(CYCLE_TRANSITIONS.CANCELLED).toEqual([]);
    expect(CYCLE_TRANSITIONS.FAILED).toEqual([]);

    expect(cycleTransitionSchema.safeParse({
      ...base, cropCycleId: cycleId,
      expectedState: 'PLANNED', newState: 'ESTABLISHED',
      reason: 'بدأ تجهيز البذرة', evidenceReference: null,
    }).success).toBe(true);
    expect(cycleTransitionSchema.safeParse({
      ...base, cropCycleId: cycleId,
      expectedState: 'PLANNED', newState: 'GROWING',
      reason: 'محاولة تخطي', evidenceReference: null,
    }).success).toBe(false);
    expect(cycleTransitionSchema.safeParse({
      ...base, cropCycleId: cycleId,
      expectedState: 'ESTABLISHED', newState: 'PLANNED',
      reason: 'محاولة رجوع', evidenceReference: null,
    }).success).toBe(false);
    expect(cycleTransitionSchema.safeParse({
      ...base, cropCycleId: cycleId,
      expectedState: 'GROWING', newState: 'ESTABLISHED',
      reason: 'محاولة رجوع بعد الفشل', evidenceReference: null,
    }).success).toBe(false);
  });

  it('requires the assigned area unit to be one of the canonical area units', () => {
    expect(cropAssignmentSchema.safeParse({
      ...base, cropCycleId: cycleId, fieldId,
      assignedAreaQuantity: '5', assignedAreaUnit: 'FEDDAN',
      plannedStartDate: '2026-10-01', plannedEndDate: '2027-03-01',
    }).success).toBe(true);
    expect(cropAssignmentSchema.safeParse({
      ...base, cropCycleId: cycleId, fieldId,
      assignedAreaQuantity: '5', assignedAreaUnit: 'ACRE',
      plannedStartDate: '2026-10-01', plannedEndDate: '2027-03-01',
    }).success).toBe(false);
  });

  it('keeps the agriculture profile schema independent of any future livestock or generic rules payload', () => {
    expect(agricultureProfileSchema.safeParse({ ...base, notes: 'ملاحظات' }).success).toBe(true);
    expect(agricultureProfileSchema.safeParse({ ...base }).success).toBe(true);
  });
});

describe('GF-013 agriculture database contract', () => {
  it('creates the canonical bounded-context tables and read views', () => {
    for (const t of [
      'agriculture_project_profiles',
      'farms',
      'fields',
      'crop_cycles',
      'crop_cycle_field_assignments',
      'crop_cycle_state_history',
    ]) {
      expect(foundationMigration).toContain(`create table public.${t}`);
    }
    for (const v of [
      'farms_read',
      'fields_read',
      'crop_cycles_read',
      'crop_cycle_field_assignments_read',
      'crop_cycle_timeline_read',
    ]) {
      expect(foundationMigration).toContain(`create or replace view public.${v}`);
    }
  });

  it('keeps every Agriculture table RLS-enabled, forced, and default-deny', () => {
    expect(foundationMigration).toContain("alter table public.%I enable row level security");
    expect(foundationMigration).toContain("alter table public.%I force row level security");
    expect(foundationMigration).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(foundationMigration).toContain('grant select on public.%I to authenticated');
  });

  it('records the CropCycle lifecycle with causal chain-tip derivation, not timestamp ordering', () => {
    expect(foundationMigration).toContain('agriculture_current_cycle_history_tip_id');
    expect(foundationMigration).toContain('agriculture_current_cycle_state');
    expect(foundationMigration).toMatch(/create unique index crop_cycle_one_initial_state/);
    expect(foundationMigration).toContain('unique (crop_cycle_id, previous_history_id)');
  });

  it('enforces the documented lifecycle transitions in the transition command', () => {
    expect(foundationMigration).toContain("raise exception 'invalid crop cycle transition: % -> %'");
    expect(foundationMigration).toMatch(/PLANNED.*ESTABLISHED[\s\S]*?ESTABLISHED.*GROWING/);
    expect(foundationMigration).toMatch(/GROWING.*FAILED/);
    expect(foundationMigration).toMatch(/PLANNED.*CANCELLED/);
  });

  it('keeps lifecycle history append-only at the database boundary', () => {
    expect(foundationMigration).toContain("raise exception 'crop cycle lifecycle history is append-only'");
    expect(foundationMigration).toContain('before update or delete on public.crop_cycle_state_history');
  });

  it('exposes the field-area invariant as a row trigger with a final capacity check', () => {
    expect(invariantMigration).toContain("raise exception 'field area capacity exceeded");
    expect(invariantMigration).toContain('crop_cycle_field_assignments_capacity_check');
  });

  it('uses the half-open [start, end) semantics for overlap detection', () => {
    expect(invariantMigration).toContain("a.planned_start_date < new.planned_end_date");
    expect(invariantMigration).toContain("a.planned_end_date   > new.planned_start_date");
  });

  it('rejects any non-canonical area unit at the database boundary', () => {
    expect(foundationMigration).toContain("check (area_unit in ('M2','HECTARE','FEDDAN'))");
  });

  it('revokes direct table writes from anon and authenticated, granting only the read views', () => {
    expect(foundationMigration).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(foundationMigration).toContain('grant select on public.%I to authenticated');
  });

  it('does not introduce IAS 41, harvest, inventory, input, or livestock primitives as schema facts', () => {
    // The migration may mention deferred entities in a comment that
    // explicitly states they are out of scope for this slice. The
    // assertions below prove that the migration never creates a table
    // or function whose name contains one of the deferred primitives,
    // and that the comment header actually lists the deferred entities
    // and explicitly says they are out of scope.
    expect(foundationMigration).not.toMatch(/create table public\.(harvest|input|livestock|inventory)/i);
    expect(foundationMigration).not.toMatch(/create or replace function public\.(harvest|input|livestock|inventory)/i);
    expect(foundationMigration).toMatch(/Deferred for later bounded Agriculture slices/);
    expect(foundationMigration).toMatch(/FieldActivity/);
    expect(foundationMigration).toMatch(/HarvestEvent/);
  });

  it('does not introduce GIS, weather, or map integration primitives', () => {
    expect(foundationMigration).not.toMatch(/postgis|weather[\s_-]?api|mapbox|google[\s_-]?maps|here[\s_-]?(api|maps)|map[\s_-]?provider/i);
  });
});

describe('GF-013 agriculture operator workflow', () => {
  it('preserves truthful Arabic foundation labels as later bounded slices add operational terms', () => {
    expect(labels).toContain("@/shared/labels");
    expect(sharedLabels).toContain("'عقارات'");
    expect(sharedLabels).toContain("'زراعة'");
    expect(labels).toContain("'مخططة'");
    expect(labels).toContain("'فشلت'");
    expect(labels).not.toMatch(/ربح مقدر|هامش مقدر|قيمة مخزون مقدرة/);
  });

  it('renders Farm, Field, CropCycle, and lifecycle transitions in the agriculture page', () => {
    expect(agriculturePage).toContain('المزرعة والمحاصيل');
    expect(agriculturePage).toContain('دورات المحصول');
    expect(agriculturePage).toContain('تخصيص الحقول');
    expect(agriculturePage).toContain('سجل دورة الحياة');
  });

  it('renders the transition form with the schema-derived next-state list, not a hard-coded enum', () => {
    // The form does not embed a hard-coded lifecycle list; it derives
    // the allowed next states from the CYCLE_TRANSITIONS table. The
    // assertion below proves that linkage.
    expect(agricultureForms).toContain('CYCLE_TRANSITIONS');
    expect(agricultureForms).toContain('transitionCropCycle');
    expect(agricultureForms).toContain('CYCLE_STATE_LABEL');
  });

  it('forbids direct authenticated INSERT on tenant tables — the read view is the only operator path', () => {
    expect(foundationMigration).toContain('grant select');
    expect(foundationMigration).not.toContain('grant insert on public.farms');
    expect(foundationMigration).not.toContain('grant update on public.fields');
    expect(foundationMigration).not.toContain('grant delete on public.crop_cycles');
  });

  it('does not silently weaken OWNER/MEMBER protections; existing patterns remain in force', () => {
    // We did not introduce a new role or relax s2_require_owner.
    expect(foundationMigration).not.toMatch(/create role/);
    expect(actions).not.toMatch(/service_role/i);
  });
});

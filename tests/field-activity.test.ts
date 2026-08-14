import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fieldActivitySchema, FIELD_ACTIVITY_TYPES } from '../src/features/agriculture/schema';

const migration = readFileSync(
  'supabase/migrations/20260813001100_agriculture_field_activity.sql',
  'utf8',
);
const page = readFileSync('src/app/(app)/projects/[projectId]/agriculture/page.tsx', 'utf8');
const forms = readFileSync('src/app/(app)/projects/[projectId]/agriculture/forms.tsx', 'utf8');
const actions = readFileSync('src/features/agriculture/actions.ts', 'utf8');
const queries = readFileSync('src/features/agriculture/queries.ts', 'utf8');
const labels = readFileSync('src/features/agriculture/labels.ts', 'utf8');
const nav = readFileSync('src/features/workspace/nav.tsx', 'utf8');
const operationsPage = readFileSync('src/app/(app)/projects/[projectId]/operations/page.tsx', 'utf8');

const uuid = '00000000-0000-4000-8000-000000000001';
const base = {
  organizationId: uuid,
  projectId: uuid,
  cropCycleId: uuid,
  fieldId: uuid,
  assignmentId: uuid,
  activityDate: '2026-11-15',
  activityType: 'IRRIGATE' as const,
  idempotencyKey: 'gf-014-test-key-0001',
};

describe('GF-014 field activity schema', () => {
  it('accepts a valid controlled activity with optional quantity pair omitted', () => {
    expect(fieldActivitySchema.safeParse(base).success).toBe(true);
    expect(FIELD_ACTIVITY_TYPES).toEqual([
      'PREPARE', 'PLANT', 'IRRIGATE', 'FERTILIZE', 'SPRAY', 'SCOUT', 'WEED', 'OTHER',
    ]);
  });

  it('requires quantity and unit together', () => {
    expect(fieldActivitySchema.safeParse({ ...base, quantity: '12.5' }).success).toBe(false);
    expect(fieldActivitySchema.safeParse({ ...base, unit: 'م³' }).success).toBe(false);
    expect(fieldActivitySchema.safeParse({ ...base, quantity: '12.5', unit: 'م³' }).success).toBe(true);
  });

  it('rejects unknown activity types and harvest', () => {
    expect(fieldActivitySchema.safeParse({ ...base, activityType: 'HARVEST' }).success).toBe(false);
    expect(fieldActivitySchema.safeParse({ ...base, activityType: 'PLOW' }).success).toBe(false);
  });
});

describe('GF-014 command and read contracts', () => {
  it('creates the tenant-owned table, invoker view, and single command', () => {
    expect(migration).toContain('create table public.field_activities');
    expect(migration).toContain('create or replace view public.field_activities_read');
    expect(migration).toContain('create or replace function public.create_field_activity');
    expect(migration).toContain("security_invoker=on");
  });

  it('binds the activity to assignment, cycle, field, org, and project', () => {
    expect(migration).toContain('foreign key (assignment_id, organization_id, project_id, crop_cycle_id, field_id)');
    expect(migration).toContain('raise exception \'crop cycle field assignment not found\'');
    expect(migration).toContain('raise exception \'agriculture project not found\'');
  });

  it('qualifies pgcrypto digest with the proven 00500 replacement, not an over-escaped backref', () => {
    expect(migration).toContain("E'\\\\1' || quote_ident(v_pgcrypto_schema) || '.digest('");
    expect(migration).not.toContain("E'\\\\\\\\1'");
  });

  it('is idempotent and auditable through the existing audit_events table', () => {
    expect(migration).toContain('idempotency key payload mismatch');
    expect(migration).toContain('insert into public.audit_events');
    expect(migration).toContain('FIELD_ACTIVITY_CREATED');
    expect(migration).not.toMatch(/create table public\.field_activity_audit/i);
  });

  it('does not advance CropCycle lifecycle', () => {
    expect(migration).not.toContain('transition_crop_cycle');
    expect(migration).not.toContain('crop_cycle_state_history');
  });

  it('default-denies direct writes and is append-only', () => {
    expect(migration).toContain('enable row level security');
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.field_activities from public, anon, authenticated');
    expect(migration).toContain('field activities are append-only');
  });

  it('application uses only the command RPC and the read view', () => {
    expect(actions).toContain("rpc(\n    'create_field_activity'");
    expect(queries).toContain('field_activities_read');
    expect(actions).not.toMatch(/service_role/i);
    expect(queries).not.toMatch(/service_role/i);
  });
});

describe('GF-014 labels and sector navigation', () => {
  it('uses Arabic activity labels and never shows Real Estate copy in Agriculture views', () => {
    expect(labels).toContain("'ري'");
    expect(labels).toContain("'تسميد'");
    expect(labels).toContain("'معاينة'");
    expect(page).toContain('أنشطة الحقل');
    expect(page).not.toMatch(/أصول عقارية|تصرف عقاري|عقار للبيع/);
    expect(forms).toContain('FIELD_ACTIVITY_TYPES');
    expect(forms).not.toContain('property_assets');
  });

  it('links field activities from the Agriculture workspace nav', () => {
    expect(nav).toContain('أنشطة الحقل');
    expect(nav).toContain('/agriculture#activities');
    expect(nav).toContain('AGRICULTURE_SECTIONS');
  });

  it('does not execute Real Estate queries from the agriculture page', () => {
    expect(page).not.toMatch(/getProperty|property_assets|real_estate/i);
    expect(operationsPage).not.toContain('create_field_activity');
  });

  it('does not scaffold forbidden agriculture or livestock scope', () => {
    // The GF-014 migration itself must remain free of every later
    // primitive. Inputs arrived later in their own GF-015 migration and
    // are asserted there; harvest, inventory and livestock stay deferred.
    expect(migration).not.toMatch(/create table public\.(input_|harvest_|inventory_|livestock)/i);
    expect(actions).not.toMatch(/createHarvest|createInventoryMovement|IAS ?41/i);
    expect(page).not.toMatch(/ماشية|حصاد آلي|IAS 41/);
  });
});

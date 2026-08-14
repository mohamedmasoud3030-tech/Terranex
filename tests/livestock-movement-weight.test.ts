import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { livestockErrorMessage } from '../src/features/livestock/errors';
import {
  movementRpcArguments,
  weightEventRpcArguments,
} from '../src/features/livestock/rpc';
import {
  WEIGHT_METHODS,
  livestockMovementSchema,
  livestockWeightEventSchema,
} from '../src/features/livestock/schema';
import {
  PLACEMENT_SOURCE_LABEL,
  WEIGHT_MEANING_LABEL,
  WEIGHT_METHOD_LABEL,
  movementChangeLabel,
} from '../src/features/livestock/labels';

const migration = readFileSync(
  'supabase/migrations/20260814001800_livestock_movement_quantity_weight.sql',
  'utf8',
);

/**
 * The executable migration with `--` comment lines removed.
 *
 * Absence assertions must be made against SQL that actually runs; a comment
 * that merely NAMES a forbidden concept ("never LIMIT 1", "no IAS 41") is
 * documentation, not a violation.
 */
const migrationSql = migration
  .split('\n')
  .filter((line) => !line.trim().startsWith('--'))
  .join('\n');
const page = readFileSync(
  'src/app/(app)/projects/[projectId]/livestock/page.tsx',
  'utf8',
);
const forms = readFileSync(
  'src/app/(app)/projects/[projectId]/livestock/forms.tsx',
  'utf8',
);

const org = '10000000-0000-4000-8000-000000000001';
const project = '10000000-0000-4000-8000-000000000002';
const cohort = '10000000-0000-4000-8000-000000000003';
const siteA = '10000000-0000-4000-8000-000000000004';
const siteB = '10000000-0000-4000-8000-000000000005';
const herdA = '10000000-0000-4000-8000-000000000006';
const herdB = '10000000-0000-4000-8000-000000000007';

const movementBase = {
  organizationId: org,
  projectId: project,
  idempotencyKey: 'gf21-move-0001',
  cohortId: cohort,
  sourceSiteId: siteA,
  sourceHerdId: herdA,
  destinationSiteId: siteB,
  destinationHerdId: herdA,
  effectiveAt: '2026-08-20T09:00',
  reason: 'نقل إلى حظيرة التسمين',
  evidenceReference: null,
  notes: null,
};

const weightBase = {
  organizationId: org,
  projectId: project,
  idempotencyKey: 'gf21-weight-0001',
  cohortId: cohort,
  effectiveAt: '2026-08-20T09:00',
  method: 'COHORT_TOTAL' as const,
  weightValue: '9600',
  weightUnit: 'KG' as const,
  measuredAnimalCount: null,
  sampleSize: null,
  evidenceReference: null,
  notes: null,
};

describe('GF-021 movement command contract', () => {
  it('accepts a site-only, herd-only, and combined movement', () => {
    expect(livestockMovementSchema.safeParse(movementBase).success).toBe(true);
    expect(livestockMovementSchema.safeParse({
      ...movementBase,
      destinationSiteId: siteA,
      destinationHerdId: herdB,
    }).success).toBe(true);
    expect(livestockMovementSchema.safeParse({
      ...movementBase,
      destinationSiteId: siteB,
      destinationHerdId: herdB,
    }).success).toBe(true);
  });

  it('rejects a no-op movement before it reaches the database', () => {
    const result = livestockMovementSchema.safeParse({
      ...movementBase,
      destinationSiteId: siteA,
      destinationHerdId: herdA,
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toContain('يجب أن يتغير الموقع أو القطيع');
  });

  it('requires a reason and an effective time', () => {
    expect(livestockMovementSchema.safeParse({ ...movementBase, reason: 'أ' }).success)
      .toBe(false);
    expect(livestockMovementSchema.safeParse({ ...movementBase, effectiveAt: '' }).success)
      .toBe(false);
  });

  it('maps every movement argument onto the canonical RPC parameters', () => {
    const parsed = livestockMovementSchema.parse(movementBase);
    expect(movementRpcArguments(parsed)).toEqual({
      p_organization_id: org,
      p_project_id: project,
      p_idempotency_key: 'gf21-move-0001',
      p_cohort_id: cohort,
      p_source_site_id: siteA,
      p_source_herd_id: herdA,
      p_destination_site_id: siteB,
      p_destination_herd_id: herdA,
      p_effective_at: '2026-08-20T09:00',
      p_reason: 'نقل إلى حظيرة التسمين',
      p_evidence_reference: null,
      p_notes: null,
    });
  });
});

describe('GF-021 weight event command contract', () => {
  it('supports exactly the four canonical measurement methods', () => {
    expect([...WEIGHT_METHODS]).toEqual([
      'INDIVIDUAL_MEASURED',
      'COHORT_TOTAL',
      'SAMPLED_AVERAGE',
      'ESTIMATED',
    ]);
    for (const method of WEIGHT_METHODS) {
      expect(WEIGHT_METHOD_LABEL[method]).toBeTruthy();
    }
  });

  it('accepts a valid cohort total, individual, sampled and estimated event', () => {
    expect(livestockWeightEventSchema.safeParse(weightBase).success).toBe(true);
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'INDIVIDUAL_MEASURED',
      measuredAnimalCount: '5',
    }).success).toBe(true);
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'SAMPLED_AVERAGE',
      weightValue: '242.750',
      sampleSize: '8',
      evidenceReference: 'كشف عينة',
    }).success).toBe(true);
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'ESTIMATED',
    }).success).toBe(true);
  });

  it('rejects zero, negative and non-numeric weights', () => {
    for (const weightValue of ['0', '-5', 'abc', '']) {
      expect(livestockWeightEventSchema.safeParse({ ...weightBase, weightValue }).success)
        .toBe(false);
    }
  });

  it('requires sample size and evidence for a sampled average', () => {
    const noSize = livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'SAMPLED_AVERAGE',
      evidenceReference: 'كشف عينة',
    });
    expect(noSize.success).toBe(false);
    expect(noSize.error?.issues[0]?.message).toContain('حجم العينة');

    const noEvidence = livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'SAMPLED_AVERAGE',
      sampleSize: '8',
    });
    expect(noEvidence.success).toBe(false);
  });

  it('requires a measured animal count for an individual measurement', () => {
    const result = livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'INDIVIDUAL_MEASURED',
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toContain('عدد الحيوانات');
  });

  it('rejects incompatible method metadata', () => {
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'SAMPLED_AVERAGE',
      sampleSize: '8',
      measuredAnimalCount: '3',
      evidenceReference: 'كشف',
    }).success).toBe(false);
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'COHORT_TOTAL',
      sampleSize: '8',
    }).success).toBe(false);
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'ESTIMATED',
      measuredAnimalCount: '3',
    }).success).toBe(false);
    expect(livestockWeightEventSchema.safeParse({
      ...weightBase,
      method: 'INDIVIDUAL_MEASURED',
      measuredAnimalCount: '3',
      sampleSize: '2',
    }).success).toBe(false);
  });

  it('sends numeric population metadata as integers or null', () => {
    const sampled = livestockWeightEventSchema.parse({
      ...weightBase,
      method: 'SAMPLED_AVERAGE',
      sampleSize: '8',
      evidenceReference: 'كشف عينة',
    });
    expect(weightEventRpcArguments(sampled)).toMatchObject({
      p_method: 'SAMPLED_AVERAGE',
      p_sample_size: 8,
      p_measured_animal_count: null,
      p_weight_unit: 'KG',
    });
    expect(weightEventRpcArguments(livestockWeightEventSchema.parse(weightBase)))
      .toMatchObject({ p_sample_size: null, p_measured_animal_count: null });
  });
});

describe('GF-021 database invariants', () => {
  it('keeps movement, quantity and weight events append-only', () => {
    for (const table of [
      'livestock_cohort_movements',
      'livestock_quantity_events',
      'livestock_weight_events',
    ]) {
      expect(migration).toContain(
        `before update or delete on public.${table}`,
      );
      expect(migration).toContain(`alter table public.%I force row level security`);
    }
  });

  it('makes a no-op movement impossible at the database boundary', () => {
    expect(migration).toContain('constraint livestock_movement_not_a_no_op');
    expect(migration).toContain(
      'source_site_id <> destination_site_id or source_herd_id <> destination_herd_id',
    );
  });

  it('permits exactly one successor per placement predecessor', () => {
    expect(migration).toContain('unique (previous_movement_id)');
    expect(migration).toContain('livestock_movement_one_root_per_cohort');
  });

  it('validates the declared movement source against the real predecessor', () => {
    expect(migration).toContain('livestock movement source is not the current placement');
    expect(migration).toContain('gf021_validate_movement_link');
  });

  it('rejects placement ambiguity instead of masking it with LIMIT 1', () => {
    expect(migration).toContain('invalid livestock placement chain tip count');
    expect(migrationSql).not.toMatch(/limit\s+1/i);
  });

  it('stores no mutable authoritative derived state', () => {
    const tableDefinitions = migrationSql.split('create view')[0];
    expect(tableDefinitions).not.toMatch(
      /\b(current_site_id|current_herd_id|current_headcount|current_weight|available_animals|mortality_total|births_total)\s+(uuid|integer|numeric)/,
    );
  });

  it('keeps headcount exact integer arithmetic', () => {
    expect(migration).toContain('quantity integer not null check (quantity > 0)');
    expect(migration).toContain('as current_quantity');
    expect(migration).not.toMatch(/quantity\s+(real|double precision|float)/i);
  });

  it('registers no GF-022 quantity event type in GF-021', () => {
    expect(migration).toContain('create table public.livestock_quantity_event_types');
    for (const code of ['BIRTH', 'MORTALITY', 'SPLIT_OUT', 'MERGE_IN']) {
      expect(migrationSql).not.toContain(`'${code}'`);
    }
  });

  it('enforces method-specific weight metadata in the database', () => {
    expect(migration).toContain('constraint livestock_weight_method_metadata');
    expect(migration).toContain('livestock sampled average requires a sample size');
    expect(migration).toContain('livestock sample size exceeds current derived quantity');
  });

  it('binds every command to auth.uid(), membership and the LIVESTOCK sector', () => {
    for (const command of [
      'record_livestock_movement',
      'record_livestock_weight_event',
    ]) {
      const body = migration.split(`create function public.${command}`)[1] ?? '';
      expect(body).toContain('auth.uid()');
      expect(body).toContain('public.is_active_member(p_organization_id)');
      expect(body).toContain('public.gf020_require_project');
      expect(body).toContain('idempotency key payload mismatch');
      expect(body).toContain('pg_advisory_xact_lock');
      expect(body).toContain('set search_path=pg_catalog,public');
    }
  });

  it('creates no Finance, valuation or IAS 41 artifact', () => {
    expect(migrationSql).not.toMatch(
      /journal_batches|journal_lines|project_payments|carrying_value|fair_value|ias\s*41|cogs/i,
    );
  });

  it('does not scaffold deferred Livestock domains', () => {
    expect(migrationSql).not.toMatch(
      /create table public\.(livestock_animals|livestock_health|livestock_feed|livestock_sales|livestock_reproduction)/i,
    );
  });
});

describe('GF-021 operator language', () => {
  it('distinguishes opening facts from derived current facts', () => {
    expect(page).toContain('الموقع الحالي');
    expect(page).toContain('الموقع الحالي المشتق');
    expect(page).toContain('العدد الافتتاحي');
    expect(page).toContain('العدد الحالي المشتق');
    expect(page).toContain('موقع الوضع الافتتاحي');
  });

  it('offers the required operator sections', () => {
    expect(page).toContain('العدد التشغيلي الحالي');
    expect(page).toContain('سجل الأوزان');
    expect(page).toContain('تسجيل وزن');
    expect(forms).toContain('تسجيل نقل الدفعة');
  });

  it('separates measured, sampled and estimated weight wording', () => {
    expect(WEIGHT_METHOD_LABEL.INDIVIDUAL_MEASURED).toContain('مقاس');
    expect(WEIGHT_METHOD_LABEL.COHORT_TOTAL).toContain('مقاس');
    expect(WEIGHT_METHOD_LABEL.SAMPLED_AVERAGE).toContain('بالعينة');
    expect(WEIGHT_METHOD_LABEL.ESTIMATED).toContain('تقديري');
    expect(WEIGHT_METHOD_LABEL.ESTIMATED).not.toContain('مقاس');
    expect(WEIGHT_MEANING_LABEL.AVERAGE_PER_ANIMAL_SAMPLED).toContain('العينة');
    expect(WEIGHT_MEANING_LABEL.COHORT_TOTAL_ESTIMATED).toContain('تقدير');
  });

  it('shows the sample size explicitly for a sampled weight', () => {
    expect(page).toContain('حجم العينة');
    expect(forms).toContain('حجم العينة إلزامي');
  });

  it('never presents a derived fact as editable master data', () => {
    expect(page).toContain('وليست بيانًا أساسيًا قابلًا للتحرير');
    expect(forms).toContain('غير قابل للتحرير');
  });

  it('labels the source of the derived placement', () => {
    expect(PLACEMENT_SOURCE_LABEL.OPENING).toContain('الوضع الافتتاحي');
    expect(PLACEMENT_SOURCE_LABEL.MOVEMENT).toContain('حركة');
    expect(movementChangeLabel(true, false)).toContain('مواقع');
    expect(movementChangeLabel(false, true)).toContain('القطعان');
    expect(movementChangeLabel(true, true)).toContain('الموقع');
    expect(movementChangeLabel(true, true)).toContain('القطيع');
  });

  it('does not call the headcount an inventory valuation', () => {
    expect(page).not.toContain('تقييم المخزون');
    expect(page).not.toContain('المخزون الحالي');
  });
});

describe('GF-021 operator error messages', () => {
  it('translates every new database invariant into Arabic guidance', () => {
    expect(livestockErrorMessage('livestock movement source is not the current placement'))
      .toContain('تغيّر الموقع الحالي');
    expect(livestockErrorMessage('livestock movement must change site or herd'))
      .toContain('بدون تغيير');
    expect(livestockErrorMessage('livestock sampled average requires a sample size'))
      .toContain('حجم العينة');
    expect(livestockErrorMessage('livestock sample size exceeds current derived quantity'))
      .toContain('العدد الحالي المشتق');
    expect(livestockErrorMessage('livestock cohort is not active'))
      .toContain('غير نشطة');
    expect(livestockErrorMessage('invalid livestock placement chain tip count: 2'))
      .toContain('غير متسقة');
  });
});

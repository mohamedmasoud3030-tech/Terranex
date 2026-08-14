import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  DISPOSAL_METHODS,
  WEIGHT_CONFIDENCE_LEVELS,
  livestockMortalitySchema,
  livestockWeightEventSchema,
} from '../src/features/livestock/schema';
import { mortalityRpcArguments, weightEventRpcArguments } from '../src/features/livestock/rpc';
import {
  DISPOSAL_METHOD_LABEL,
  WEIGHT_CONFIDENCE_LABEL,
} from '../src/features/livestock/labels';
import { livestockErrorMessage } from '../src/features/livestock/errors';

const migration = readFileSync(
  'supabase/migrations/20260814002000_livestock_review_hardening.sql',
  'utf8',
);
const inceptionMigration = readFileSync(
  'supabase/migrations/20260814002100_livestock_cohort_inception.sql',
  'utf8',
);
const page = readFileSync(
  'src/app/(app)/projects/[projectId]/livestock/page.tsx',
  'utf8',
);
const forms = readFileSync(
  'src/app/(app)/projects/[projectId]/livestock/forms.tsx',
  'utf8',
);

const base = {
  organizationId: '10000000-0000-4000-8000-000000000001',
  projectId: '10000000-0000-4000-8000-000000000002',
  idempotencyKey: 'gf-review-0001',
  cohortId: '10000000-0000-4000-8000-000000000003',
  quantity: '2',
  effectiveAt: '2026-08-01T10:00',
  causeCategory: 'DISEASE' as const,
  causeDetail: null,
  disposalMethod: 'BURIAL' as const,
  evidenceReference: 'محضر',
  notes: null,
};

const weight = {
  organizationId: base.organizationId,
  projectId: base.projectId,
  idempotencyKey: 'gf-review-weight',
  cohortId: base.cohortId,
  effectiveAt: base.effectiveAt,
  method: 'SAMPLED_AVERAGE' as const,
  weightValue: '220.5',
  weightUnit: 'KG' as const,
  measuredAnimalCount: null,
  sampleSize: '5',
  confidenceLevel: 'HIGH' as const,
  evidenceReference: 'كشف عينة',
  notes: null,
};

describe('GF-022 review hardening database contract', () => {
  it('resolves current quantity through an explicit as-of resolver and timestamp buckets', () => {
    expect(migration).toContain('livestock_cohort_quantity_as_of');
    expect(migration).toContain('q.effective_at <= p_as_of_at');
    expect(migration).toContain('group by q.effective_at');
    expect(migration).toContain('Events sharing one');
    expect(migration).toContain('livestock as-of quantity cannot go below zero');
  });

  it('uses the as-of balance in mortality, split, merge and weight commands', () => {
    for (const command of [
      'record_livestock_mortality',
      'split_livestock_cohort',
      'merge_livestock_cohorts',
      'record_livestock_weight_event',
    ]) {
      const body = migration.split(`create or replace function public.${command}`)[1] ?? '';
      expect(body).toContain('livestock_cohort_quantity_as_of');
    }
  });

  it('guards species continuity at Cohort, Herd, movement and lineage boundaries', () => {
    for (const guard of [
      'livestock_cohorts_species_guard',
      'livestock_herds_species_update_guard',
      'livestock_movements_species_guard',
      'livestock_lineage_species_guard',
    ]) {
      expect(migration).toContain(guard);
    }
    expect(migration).toContain('Herd species must match the Cohort species');
    expect(migration).toContain('operation Cohorts require a compatible species');
  });

  it('enforces exact split and merge shape in a deferred database invariant', () => {
    expect(migration).toContain('livestock_lineage_shape_validate');
    expect(migration).toContain('exactly one SPLIT_OUT leg and one SPLIT_IN leg');
    expect(migration).toContain('SPLIT lineage does not match its legs');
    expect(migration).toContain('at least two MERGE_OUT legs and exactly one MERGE_IN leg');
    expect(migration).toContain('MERGE_IN quantity must equal the source total');
    expect(migration).toContain('MERGE lineage does not match its legs');
    expect(migration).toContain('deferrable initially deferred');
  });

  it('defines date-only normal inception and exact derived-operation inception', () => {
    expect(inceptionMigration).toContain('gf022_cohort_inception_at');
    expect(inceptionMigration).toContain("origin_date::timestamp without time zone at time zone 'UTC'");
    expect(inceptionMigration).toContain('derived Cohort inception is not established');
    expect(inceptionMigration).toContain('livestock_quantity_events_inception_guard');
    expect(inceptionMigration).toContain('livestock_movements_inception_guard');
    expect(inceptionMigration).toContain('livestock_derived_cohort_provenance_validate');
    expect(inceptionMigration).toContain('operational_inception_at');
  });

  it('keeps zero ACTIVE bounded without inventing a later lifecycle state', () => {
    expect(migration).toContain('has no positive quantity at the weight effective time');
    expect(page).toContain('operationalActiveCohorts');
    expect(page).toContain('positiveQuantityCohorts');
    expect(forms).toContain('لا يمكن تسجيل النفوق على دفعة مستنفدة');
    expect(forms).toContain('لا يمكن تسجيل وزن لدفعة مستنفدة');
    expect(migration).not.toMatch(/insert into public\.livestock_cohort_state_history[\s\S]{0,180}(CLOSED|LOST)/);
  });
});

describe('GF-022 mortality disposal contract', () => {
  it('has a constrained disposal vocabulary and maps it to the RPC', () => {
    expect(DISPOSAL_METHODS).toEqual([
      'BURIAL', 'INCINERATION', 'RENDERING', 'COMPOSTING', 'OTHER', 'PENDING',
    ]);
    for (const method of DISPOSAL_METHODS) expect(DISPOSAL_METHOD_LABEL[method]).toBeTruthy();
    expect(livestockMortalitySchema.safeParse(base).success).toBe(true);
    expect(livestockMortalitySchema.safeParse({ ...base, disposalMethod: 'DUMP' }).success).toBe(false);
    expect(mortalityRpcArguments(livestockMortalitySchema.parse(base))).toMatchObject({
      p_disposal_method: 'BURIAL',
    });
  });

  it('records legacy missing disposal as explicit PENDING rather than null', () => {
    expect(migration).toContain("new.disposal_method := 'PENDING'");
    expect(migration).toContain("'BURIAL', 'INCINERATION', 'RENDERING', 'COMPOSTING', 'OTHER', 'PENDING'");
    expect(migration).toContain('Constrained mortality disposal state');
  });
});

describe('GF-022 weight quality contract', () => {
  it('stores qualitative confidence without fabricating a statistical interval', () => {
    expect(WEIGHT_CONFIDENCE_LEVELS).toEqual(['UNASSESSED', 'LOW', 'MEDIUM', 'HIGH']);
    for (const level of WEIGHT_CONFIDENCE_LEVELS) expect(WEIGHT_CONFIDENCE_LABEL[level]).toBeTruthy();
    expect(livestockWeightEventSchema.safeParse(weight).success).toBe(true);
    expect(livestockWeightEventSchema.safeParse({ ...weight, confidenceLevel: '95_PERCENT' }).success)
      .toBe(false);
    expect(weightEventRpcArguments(livestockWeightEventSchema.parse(weight))).toMatchObject({
      p_confidence_level: 'HIGH',
      p_sample_size: 5,
    });
    expect(migration).toContain('not a statistical confidence interval');
    expect(forms).toContain('وليست فاصلًا إحصائيًا');
  });
});

describe('GF-022 review errors', () => {
  it('translates temporal, shape, species, disposal and quality failures', () => {
    for (const [databaseMessage, expected] of [
      ['livestock as-of quantity cannot go below zero at 2026-08-01 (−1)', 'الرصيد المشتق'],
      ['livestock SPLIT operation requires exactly one SPLIT_OUT leg and one SPLIT_IN leg', 'التقسيم'],
      ['livestock MERGE_IN quantity must equal the source total', 'مجموع المصادر'],
      ['livestock movement Herd species must match the Cohort species', 'نوع القطيع'],
      ['invalid livestock mortality disposal method', 'طريقة التخلص'],
      ['invalid livestock weight confidence level', 'درجة الثقة'],
      ['livestock movement effective time precedes Cohort inception', 'بداية تشغيل'],
      ['livestock derived Cohort inception is not established', 'لم تثبت'],
    ] as const) {
      expect(livestockErrorMessage(databaseMessage)).toContain(expected);
    }
  });
});

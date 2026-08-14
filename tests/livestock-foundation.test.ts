import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { livestockErrorMessage } from '../src/features/livestock/errors';
import {
  cohortRpcArguments,
  herdRpcArguments,
  transitionRpcArguments,
} from '../src/features/livestock/rpc';
import {
  WEIGHT_BASES,
  livestockCohortSchema,
  livestockHerdSchema,
  livestockSiteSchema,
  livestockTransitionSchema,
} from '../src/features/livestock/schema';

const foundationMigration = readFileSync(
  'supabase/migrations/20260814001700_livestock_foundation.sql',
  'utf8',
);
const hardeningMigration = readFileSync(
  'supabase/migrations/20260814001710_livestock_placement_lifecycle_hardening.sql',
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

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const herdId = '00000000-0000-4000-8000-000000000003';
const initialSiteId = '00000000-0000-4000-8000-000000000004';
const cohortId = '00000000-0000-4000-8000-000000000005';
const context = { organizationId, projectId, idempotencyKey: 'gf020-test-key' };
const validCohort = {
  ...context,
  herdId,
  initialSiteId,
  cohortReference: 'AUG-2026',
  originType: 'PURCHASED' as const,
  originDate: '2026-08-01',
  openingHeadcount: '60',
};

describe('GF-020 validation behavior', () => {
  it('accepts bounded Site and Herd inputs without making Site part of Herd identity', () => {
    expect(livestockSiteSchema.safeParse({
      ...context,
      name: 'مزرعة التسمين',
      internalReference: 'S1',
      siteType: 'FARM',
    }).success).toBe(true);
    const herd = livestockHerdSchema.parse({
      ...context,
      name: 'قطيع أبقار التسمين',
      internalReference: 'H1',
      species: 'CATTLE',
      purpose: 'MEAT',
    });
    expect(herd).not.toHaveProperty('siteId');
  });

  it.each(['OWNED_LAND', 'DAIRY_UNIT'])('rejects unsupported Site type %s', (siteType) => {
    expect(livestockSiteSchema.safeParse({
      ...context,
      name: 'موقع',
      internalReference: 'S1',
      siteType,
    }).success).toBe(false);
  });

  it.each([
    ['CAMEL', 'MEAT'],
    ['CATTLE', 'DAIRY'],
  ])('rejects unsupported Herd species/purpose %s/%s', (species, purpose) => {
    expect(livestockHerdSchema.safeParse({
      ...context,
      name: 'قطيع',
      internalReference: 'H1',
      species,
      purpose,
    }).success).toBe(false);
  });

  it('requires a same-workflow opening placement identifier', () => {
    expect(livestockCohortSchema.safeParse(validCohort).success).toBe(true);
    expect(livestockCohortSchema.safeParse({
      ...validCohort,
      initialSiteId: undefined,
    }).success).toBe(false);
  });

  it.each(['0', '-1', '1.5'])('rejects invalid opening headcount %s', (openingHeadcount) => {
    expect(livestockCohortSchema.safeParse({
      ...validCohort,
      openingHeadcount,
    }).success).toBe(false);
  });

  it('requires all optional opening-weight fields together', () => {
    expect(livestockCohortSchema.safeParse({
      ...validCohort,
      openingWeightValue: '180',
    }).success).toBe(false);
    expect(livestockCohortSchema.safeParse({
      ...validCohort,
      openingWeightValue: '180',
      openingWeightUnit: 'KG',
      openingWeightBasis: 'ESTIMATED',
    }).success).toBe(true);
  });

  it('supports only defensible GF-020 opening-weight bases', () => {
    expect(WEIGHT_BASES).toEqual([
      'INDIVIDUAL_MEASURED',
      'COHORT_TOTAL',
      'ESTIMATED',
    ]);
    expect(livestockCohortSchema.safeParse({
      ...validCohort,
      openingWeightValue: '180',
      openingWeightUnit: 'KG',
      openingWeightBasis: 'SAMPLED_AVERAGE',
    }).success).toBe(false);
  });

  it('allows only PLANNED to ACTIVE', () => {
    const valid = {
      ...context,
      cohortId,
      expectedState: 'PLANNED',
      newState: 'ACTIVE',
      reason: 'بدء التشغيل',
    };
    expect(livestockTransitionSchema.safeParse(valid).success).toBe(true);
    expect(livestockTransitionSchema.safeParse({
      ...valid,
      expectedState: 'ACTIVE',
      newState: 'SOLD',
    }).success).toBe(false);
  });
});

describe('GF-020 command mapping behavior', () => {
  it('does not send a Site argument when creating a Herd', () => {
    const args = herdRpcArguments(livestockHerdSchema.parse({
      ...context,
      name: 'قطيع أبقار التسمين',
      internalReference: 'H1',
      species: 'CATTLE',
      purpose: 'MEAT',
    }));
    expect(args).not.toHaveProperty('p_site_id');
  });

  it('sends initial Site and integer headcount when creating a Cohort', () => {
    const args = cohortRpcArguments(livestockCohortSchema.parse(validCohort));
    expect(args.p_site_id).toBe(initialSiteId);
    expect(args.p_opening_headcount).toBe(60);
    expect(args.p_opening_weight_basis).toBeNull();
  });

  it('maps lifecycle expected/new states without browser authority expansion', () => {
    const args = transitionRpcArguments(livestockTransitionSchema.parse({
      ...context,
      cohortId,
      expectedState: 'PLANNED',
      newState: 'ACTIVE',
      reason: 'بدء التشغيل',
    }));
    expect(args).toMatchObject({
      p_cohort_id: cohortId,
      p_expected_state: 'PLANNED',
      p_new_state: 'ACTIVE',
    });
  });
});

describe('GF-020 Arabic domain error behavior', () => {
  it.each([
    ['idempotency key payload mismatch', 'مفتاح العملية'],
    ['forbidden', 'صلاحية'],
    ['livestock project not found', 'مشروع الثروة الحيوانية'],
    ['livestock site not found', 'موقع التشغيل'],
    ['livestock herd not found', 'القطيع'],
    ['livestock cohort not found', 'الدفعة الحيوانية'],
    ['invalid livestock opening headcount', 'العدد عند بداية الدفعة'],
    ['invalid livestock opening weight', 'الوزن الافتتاحي'],
    ['invalid livestock cohort transition', 'انتقال حالة الدفعة'],
  ])('maps %s to an operator-safe Arabic message', (databaseMessage, expected) => {
    expect(livestockErrorMessage(databaseMessage)).toContain(expected);
  });

  it('does not expose unknown database details', () => {
    expect(livestockErrorMessage('constraint livestock_internal_x failed'))
      .not.toContain('livestock_internal_x');
  });
});

describe('GF-020 database and UX boundary', () => {
  it('keeps the reviewed foundation migration immutable and repairs it forward', () => {
    expect(foundationMigration).toContain('create table public.livestock_herds');
    expect(hardeningMigration).toContain('alter table public.livestock_herds drop column site_id');
    expect(hardeningMigration).toContain('create table public.livestock_cohort_initial_placements');
  });

  it('enforces one causal lifecycle chain without LIMIT 1 masking', () => {
    expect(hardeningMigration).toContain('livestock_history_one_root_per_cohort');
    expect(hardeningMigration).toContain('livestock_history_predecessor_same_cohort_fk');
    expect(hardeningMigration).toContain('livestock lifecycle previous state mismatch');
    expect(hardeningMigration).toContain('invalid livestock lifecycle tip count');
    const tipDefinition = hardeningMigration.match(
      /create or replace function public\.livestock_current_cohort_tip[\s\S]*?end \$\$;/,
    )?.[0];
    expect(tipDefinition).not.toMatch(/limit 1/i);
  });

  it('keeps direct writes denied and new placement RLS forced', () => {
    expect(hardeningMigration).toContain(
      'alter table public.livestock_cohort_initial_placements force row level security',
    );
    expect(hardeningMigration).toContain(
      'revoke all on public.livestock_cohort_initial_placements from public, anon, authenticated',
    );
  });

  it('renders honest opening placement and quantity language', () => {
    expect(page).toContain('موقع الوضع الافتتاحي');
    expect(page).toContain('ليس ادعاءً بالموقع الحالي');
    expect(forms).toContain('موقع التشغيل ليس جزءًا دائمًا من هويته');
    expect(forms).toContain('المتوسط بالعينة مؤجل');
    expect(page).not.toContain('المخزون الحالي');
  });

  it('does not scaffold deferred domains', () => {
    expect(hardeningMigration).not.toMatch(
      /create table public\.(animals|health|feed|mortality|livestock_sales|weight_events)/i,
    );
    expect(hardeningMigration).not.toMatch(/current_(site|headcount)_id/i);
  });
});

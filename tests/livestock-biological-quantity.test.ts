import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { livestockErrorMessage } from '../src/features/livestock/errors';
import {
  birthRpcArguments,
  mergeRpcArguments,
  mortalityRpcArguments,
  splitRpcArguments,
} from '../src/features/livestock/rpc';
import {
  MORTALITY_CAUSES,
  livestockBirthSchema,
  livestockMergeSchema,
  livestockMortalitySchema,
  livestockSplitSchema,
} from '../src/features/livestock/schema';
import {
  MORTALITY_CAUSE_LABEL,
  OPERATION_TYPE_LABEL,
  ORIGIN_LABEL,
  QUANTITY_EVENT_LABEL,
} from '../src/features/livestock/labels';

const migration = readFileSync(
  'supabase/migrations/20260814001900_livestock_biological_quantity_events.sql',
  'utf8',
);

/** Executable SQL only: a comment naming a forbidden concept is documentation. */
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
const cohortA = '10000000-0000-4000-8000-000000000003';
const cohortB = '10000000-0000-4000-8000-000000000004';
const herd = '10000000-0000-4000-8000-000000000005';
const site = '10000000-0000-4000-8000-000000000006';

const ctx = { organizationId: org, projectId: project };

const birthBase = {
  ...ctx,
  idempotencyKey: 'gf22-birth-0001',
  cohortId: cohortA,
  quantity: '12',
  effectiveAt: '2026-09-01T06:00',
  evidenceReference: null,
  notes: null,
};

const mortalityBase = {
  ...ctx,
  idempotencyKey: 'gf22-mort-0001',
  cohortId: cohortA,
  quantity: '7',
  effectiveAt: '2026-09-05T06:00',
  causeCategory: 'DISEASE' as const,
  causeDetail: null,
  evidenceReference: null,
  notes: null,
};

const splitBase = {
  ...ctx,
  idempotencyKey: 'gf22-split-0001',
  sourceCohortId: cohortA,
  quantity: '30',
  effectiveAt: '2026-09-10T06:00',
  destinationCohortReference: 'دفعة التقسيم أ',
  destinationHerdId: herd,
  destinationSiteId: site,
  destinationSexComposition: null,
  destinationBreedDescriptor: null,
  reason: 'فصل مجموعة التسمين',
  evidenceReference: null,
  notes: null,
};

const mergeBase = {
  ...ctx,
  idempotencyKey: 'gf22-merge-0001',
  sourceCohortIds: [cohortA, cohortB],
  quantities: ['25', '40'],
  effectiveAt: '2026-09-15T06:00',
  destinationCohortReference: 'دفعة الدمج الموحدة',
  destinationHerdId: herd,
  destinationSiteId: site,
  destinationSexComposition: null,
  destinationBreedDescriptor: null,
  reason: 'توحيد مجموعتين',
  evidenceReference: null,
  notes: null,
};

describe('GF-022 birth contract', () => {
  it('accepts a positive integer quantity', () => {
    expect(livestockBirthSchema.safeParse(birthBase).success).toBe(true);
  });

  it('rejects zero, negative and fractional quantities', () => {
    for (const quantity of ['0', '-3', '2.5', '', 'abc']) {
      expect(livestockBirthSchema.safeParse({ ...birthBase, quantity }).success).toBe(false);
    }
  });

  it('sends an integer quantity to the canonical RPC', () => {
    expect(birthRpcArguments(livestockBirthSchema.parse(birthBase))).toEqual({
      p_organization_id: org,
      p_project_id: project,
      p_idempotency_key: 'gf22-birth-0001',
      p_cohort_id: cohortA,
      p_quantity: 12,
      p_effective_at: '2026-09-01T06:00',
      p_evidence_reference: null,
      p_notes: null,
    });
  });
});

describe('GF-022 mortality contract', () => {
  it('requires a valid cause category', () => {
    expect(livestockMortalitySchema.safeParse(mortalityBase).success).toBe(true);
    expect(livestockMortalitySchema.safeParse({
      ...mortalityBase,
      causeCategory: 'SPONTANEOUS',
    }).success).toBe(false);
  });

  it('labels every cause category in Arabic', () => {
    for (const cause of MORTALITY_CAUSES) {
      expect(MORTALITY_CAUSE_LABEL[cause]).toBeTruthy();
    }
  });

  it('rejects a non-positive quantity', () => {
    for (const quantity of ['0', '-1']) {
      expect(livestockMortalitySchema.safeParse({ ...mortalityBase, quantity }).success)
        .toBe(false);
    }
  });

  it('maps the cause onto the canonical RPC', () => {
    expect(mortalityRpcArguments(livestockMortalitySchema.parse(mortalityBase)))
      .toMatchObject({ p_quantity: 7, p_cause_category: 'DISEASE', p_cause_detail: null });
  });
});

describe('GF-022 split contract', () => {
  it('accepts a valid split and requires an explicit destination', () => {
    expect(livestockSplitSchema.safeParse(splitBase).success).toBe(true);
    expect(livestockSplitSchema.safeParse({
      ...splitBase,
      destinationCohortReference: '',
    }).success).toBe(false);
    expect(livestockSplitSchema.safeParse({ ...splitBase, reason: 'أ' }).success).toBe(false);
  });

  it('rejects a non-positive split quantity', () => {
    expect(livestockSplitSchema.safeParse({ ...splitBase, quantity: '0' }).success).toBe(false);
  });

  it('maps the destination placement onto the canonical RPC', () => {
    expect(splitRpcArguments(livestockSplitSchema.parse(splitBase))).toMatchObject({
      p_source_cohort_id: cohortA,
      p_quantity: 30,
      p_destination_herd_id: herd,
      p_destination_site_id: site,
      p_destination_cohort_reference: 'دفعة التقسيم أ',
    });
  });
});

describe('GF-022 merge contract', () => {
  it('accepts two or more distinct sources with matching quantities', () => {
    expect(livestockMergeSchema.safeParse(mergeBase).success).toBe(true);
  });

  it('requires at least two sources', () => {
    const result = livestockMergeSchema.safeParse({
      ...mergeBase,
      sourceCohortIds: [cohortA],
      quantities: ['10'],
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toContain('دفعتين');
  });

  it('rejects merging a cohort with itself', () => {
    const result = livestockMergeSchema.safeParse({
      ...mergeBase,
      sourceCohortIds: [cohortA, cohortA],
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues.some((i) => i.message.includes('دفعات مختلفة'))).toBe(true);
  });

  it('rejects a quantity list that does not match the sources', () => {
    const result = livestockMergeSchema.safeParse({
      ...mergeBase,
      quantities: ['25', '40', '10'],
    });
    expect(result.success).toBe(false);
  });

  it('sends positional integer quantities to the canonical RPC', () => {
    expect(mergeRpcArguments(livestockMergeSchema.parse(mergeBase))).toMatchObject({
      p_source_cohort_ids: [cohortA, cohortB],
      p_quantities: [25, 40],
      p_destination_cohort_reference: 'دفعة الدمج الموحدة',
    });
  });
});

describe('GF-022 database invariants', () => {
  it('registers exactly the six operational classes with correct signs', () => {
    for (const [code, direction] of [
      ['BIRTH', '1'],
      ['MORTALITY', '-1'],
      ['SPLIT_OUT', '-1'],
      ['SPLIT_IN', '1'],
      ['MERGE_OUT', '-1'],
      ['MERGE_IN', '1'],
    ]) {
      expect(migrationSql).toMatch(new RegExp(`'${code}',\\s*${direction},`));
    }
  });

  it('introduces no sale or removal class in this slice', () => {
    for (const code of ['SALE', 'SOLD', 'REMOVAL', 'CULL', 'TRANSFER_OUT']) {
      expect(migrationSql).not.toContain(`('${code}',`);
    }
  });

  it('is additive on the GF-021 ledger rather than a rebuild', () => {
    expect(migrationSql).toContain('alter table public.livestock_quantity_events');
    expect(migrationSql).not.toMatch(/drop table[\s\S]{0,80}livestock_quantity_events/i);
  });

  it('binds both sides of a split or merge to one operation identity', () => {
    expect(migrationSql).toContain('create table public.livestock_quantity_operations');
    expect(migrationSql).toContain('livestock_quantity_events_operation_fk');
    expect(migrationSql).toContain('requires an operation identity');
  });

  it('enforces exact conservation with a deferred constraint trigger', () => {
    expect(migrationSql).toContain('livestock_operation_conserves_quantity');
    expect(migrationSql).toContain('does not conserve quantity');
    expect(migrationSql).toContain('requires both an outgoing and an incoming leg');
    expect(migrationSql).toContain('deferrable initially deferred');
  });

  it('makes a negative derived quantity unreachable', () => {
    expect(migrationSql).toContain('livestock_quantity_never_negative');
    expect(migrationSql).toContain('cannot go below zero');
    expect(migrationSql).toContain('exceeds the current derived quantity');
  });

  it('serializes every quantity command on a per-cohort lock', () => {
    expect(migrationSql).toContain('gf022_lock_cohort_quantity');
    expect(migrationSql).toContain("':livestock-quantity'");
    for (const command of [
      'record_livestock_birth',
      'record_livestock_mortality',
      'split_livestock_cohort',
      'merge_livestock_cohorts',
    ]) {
      const body = migrationSql.split(`create function public.${command}`)[1] ?? '';
      expect(body).toContain('gf022_lock_cohort_quantity');
      expect(body).toContain('auth.uid()');
      expect(body).toContain('public.is_active_member(p_organization_id)');
      expect(body).toContain('public.gf020_require_project');
      expect(body).toContain('idempotency key payload mismatch');
      expect(body).toContain('set search_path=pg_catalog,public');
    }
  });

  it('requires a compatible species for a merge', () => {
    expect(migrationSql).toContain('compatible species');
    expect(migrationSql).toContain('at least two source cohorts');
    expect(migrationSql).toContain('must be distinct');
  });

  it('gives an operation-derived cohort a zero opening headcount', () => {
    expect(migrationSql).toContain('SPLIT_FROM_COHORT');
    expect(migrationSql).toContain('MERGED_FROM_COHORTS');
    expect(migrationSql).toContain('then opening_headcount = 0');
  });

  it('keeps the rollforward exact integer arithmetic', () => {
    for (const column of [
      'births', 'mortality', 'split_in', 'split_out', 'merge_in', 'merge_out',
    ]) {
      expect(migrationSql).toContain(`as ${column}`);
    }
    expect(migrationSql).toContain('as current_quantity');
    expect(migrationSql).not.toMatch(/quantity\s+(real|double precision|float)/i);
  });

  it('does not mutate lifecycle state when quantity reaches zero', () => {
    expect(migrationSql).not.toMatch(/livestock_cohort_state_history[\s\S]{0,200}(CLOSED|LOST)/);
  });

  it('adds no mutable authoritative derived counter', () => {
    const tableDefinitions = migrationSql.split('create view')[0];
    expect(tableDefinitions).not.toMatch(
      /\b(current_headcount|mortality_total|births_total|available_animals)\s+(integer|numeric|uuid)/,
    );
  });

  it('keeps every new material table forced-RLS and command-only', () => {
    expect(migrationSql).toContain('force row level security');
    expect(migrationSql).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(migrationSql).toContain('livestock_quantity_operations');
    expect(migrationSql).toContain('livestock_cohort_lineage');
  });

  it('creates no Finance, valuation or IAS 41 artifact', () => {
    expect(migrationSql).not.toMatch(
      /journal_batches|journal_lines|project_payments|carrying_value|fair_value|ias\s*41|cogs/i,
    );
  });

  it('does not scaffold deferred Livestock domains', () => {
    expect(migrationSql).not.toMatch(
      /create table public\.(livestock_animals|livestock_health|livestock_feed|livestock_sales|livestock_reproduction|livestock_treatments)/i,
    );
  });
});

describe('GF-022 operator language', () => {
  it('offers the required Arabic workflows', () => {
    expect(page).toContain('تسجيل ولادات');
    expect(page).toContain('تسجيل نفوق');
    expect(page).toContain('تقسيم دفعة');
    expect(page).toContain('دمج دفعات');
    expect(page).toContain('حركة العدد');
    expect(page).toContain('الرصيد العددي الحالي');
  });

  it('shows the rollforward arithmetic transparently', () => {
    expect(page).toContain('عدد افتتاحي');
    expect(page).toContain('+ ولادات');
    expect(page).toContain('− نفوق');
    expect(page).toContain('وارد من تقسيم');
    expect(page).toContain('صادر إلى دمج');
    expect(page).toContain('= العدد الحالي المشتق');
  });

  it('never calls the headcount an inventory valuation', () => {
    expect(page).not.toContain('تقييم المخزون');
    expect(page).not.toContain('المخزون الحالي');
    expect(page).toContain('وليست تقييمًا للمخزون');
  });

  it('labels every quantity class and operation type', () => {
    for (const code of [
      'BIRTH', 'MORTALITY', 'SPLIT_OUT', 'SPLIT_IN', 'MERGE_OUT', 'MERGE_IN',
    ]) {
      expect(QUANTITY_EVENT_LABEL[code]).toBeTruthy();
    }
    expect(OPERATION_TYPE_LABEL.SPLIT).toContain('تقسيم');
    expect(OPERATION_TYPE_LABEL.MERGE).toContain('دمج');
  });

  it('explains that an operation-derived cohort has no opening headcount', () => {
    expect(ORIGIN_LABEL.SPLIT_FROM_COHORT).toContain('لا يوجد عدد افتتاحي');
    expect(ORIGIN_LABEL.MERGED_FROM_COHORTS).toContain('لا يوجد عدد افتتاحي');
  });

  it('states the conservation guarantee to the operator', () => {
    expect(forms).toContain('لا يُفقد أو يُستحدث أي رأس');
    expect(forms).toContain('مجموعها بالضبط');
  });

  it('warns that mortality cannot exceed the derived balance', () => {
    expect(forms).toContain('لا يمكن أن يتجاوز العدد الرصيد العددي الحالي المشتق');
  });

  it('states that these events post nothing to Finance', () => {
    expect(forms).toContain('لا ينشأ عنها أي قيد محاسبي');
  });
});

describe('GF-022 operator error messages', () => {
  it('translates every new database invariant into Arabic guidance', () => {
    expect(livestockErrorMessage('livestock quantity exceeds the current derived quantity (5 available)'))
      .toContain('أكبر من الرصيد العددي الحالي');
    expect(livestockErrorMessage('livestock derived quantity cannot go below zero (-3)'))
      .toContain('عن صفر');
    expect(livestockErrorMessage('livestock merge requires a compatible species'))
      .toContain('أنواع حيوانية مختلفة');
    expect(livestockErrorMessage('livestock merge requires at least two source cohorts'))
      .toContain('دفعتين');
    expect(livestockErrorMessage('livestock merge sources must be distinct'))
      .toContain('دفعات مختلفة');
    expect(livestockErrorMessage('livestock quantity operation does not conserve quantity: out=5, in=3'))
      .toContain('لا تحافظ على العدد');
    expect(livestockErrorMessage('invalid livestock mortality cause'))
      .toContain('سبب النفوق');
  });
});

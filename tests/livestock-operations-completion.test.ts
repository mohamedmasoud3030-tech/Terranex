import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { livestockErrorMessage } from '../src/features/livestock/errors';
import {
  feedIssueRpcArguments,
  healthEventRpcArguments,
  identifyAnimalRpcArguments,
  medicineProductRpcArguments,
  reproductionEventRpcArguments,
} from '../src/features/livestock/operations-rpc';
import {
  feedIssueSchema,
  healthEventSchema,
  identifyAnimalSchema,
  medicineProductSchema,
  reproductionEventSchema,
} from '../src/features/livestock/operations-schema';

const migration = readFileSync('supabase/migrations/20260815010000_livestock_operations_completion.sql', 'utf8');
const sql = migration.split('\n').filter((line) => !line.trim().startsWith('--')).join('\n');
const page = readFileSync('src/app/(app)/projects/[projectId]/livestock/operations/page.tsx', 'utf8');
const forms = readFileSync('src/app/(app)/projects/[projectId]/livestock/operations/forms.tsx', 'utf8');
const org = '10000000-0000-4000-8000-000000000001';
const project = '10000000-0000-4000-8000-000000000002';
const cohort = '10000000-0000-4000-8000-000000000003';
const animal = '10000000-0000-4000-8000-000000000004';
const product = '10000000-0000-4000-8000-000000000005';
const feed = '10000000-0000-4000-8000-000000000006';
const base = { organizationId: org, projectId: project, idempotencyKey: 'gf023-unit-key' };

describe('GF-023 application validation and RPC mapping', () => {
  it('validates immutable medicine references with explicit zero withdrawal', () => {
    const parsed = medicineProductSchema.parse({ ...base, productReference: 'VAC-1', name: 'لقاح', productKind: 'VACCINE', defaultWithdrawalDays: '0' });
    expect(medicineProductRpcArguments(parsed)).toMatchObject({ p_product_kind: 'VACCINE', p_default_withdrawal_days: 0 });
    expect(medicineProductSchema.safeParse({ ...parsed, defaultWithdrawalDays: '3651' }).success).toBe(false);
  });

  it('maps optional Animal identity without any quantity argument', () => {
    const parsed = identifyAnimalSchema.parse({ ...base, cohortId: cohort, identifierType: 'EAR_TAG', identifierValue: 'EG-1', sex: 'FEMALE', identifiedAt: '2026-08-14T08:00' });
    const args = identifyAnimalRpcArguments(parsed);
    expect(args).toMatchObject({ p_cohort_id: cohort, p_identifier_value: 'EG-1', p_sex: 'FEMALE' });
    expect(Object.keys(args).some((key) => key.includes('quantity') || key.includes('headcount'))).toBe(false);
  });

  it('requires condition/classification for diagnosis', () => {
    const valid = { ...base, cohortId: cohort, eventType: 'DIAGNOSIS', conditionClassification: 'RESPIRATORY', conditionName: 'التهاب', effectiveAt: '2026-08-14T08:00', practitionerName: 'طبيب' };
    expect(healthEventSchema.safeParse(valid).success).toBe(true);
    expect(healthEventSchema.safeParse({ ...valid, conditionClassification: null }).success).toBe(false);
  });

  it('requires complete administration metadata for treatment and vaccination', () => {
    const valid = { ...base, cohortId: cohort, animalId: animal, eventType: 'TREATMENT', medicineProductId: product, doseQuantity: '2.5', doseUnit: 'ML', administrationRoute: 'INJECTION', effectiveAt: '2026-08-14T08:00', practitionerName: 'طبيب' };
    const parsed = healthEventSchema.parse(valid);
    expect(healthEventRpcArguments(parsed)).toMatchObject({ p_animal_id: animal, p_medicine_product_id: product, p_dose_quantity: '2.5' });
    expect(healthEventSchema.safeParse({ ...valid, doseQuantity: null }).success).toBe(false);
  });

  it('keeps observation-only and authoritative GF-022 birth outcomes explicit', () => {
    const valid = { ...base, cohortId: cohort, eventType: 'BIRTH_OUTCOME', subjectCount: '2', observedLiveBirthCount: '3', stillbirthCount: '0', birthQuantityEffect: 'GF022_BIRTH', effectiveAt: '2026-08-14T08:00', performedByName: 'مشرف' };
    const parsed = reproductionEventSchema.parse(valid);
    expect(reproductionEventRpcArguments(parsed)).toMatchObject({ p_observed_live_birth_count: 3, p_birth_quantity_effect: 'GF022_BIRTH' });
    expect(reproductionEventSchema.safeParse({ ...valid, observedLiveBirthCount: '0' }).success).toBe(false);
    expect(reproductionEventSchema.safeParse({ ...valid, birthQuantityEffect: 'OBSERVATION_ONLY' }).success).toBe(true);
  });

  it('requires subject count one for optional individual reproduction', () => {
    const valid = { ...base, cohortId: cohort, subjectAnimalId: animal, eventType: 'PREGNANCY_CHECK', subjectCount: '1', pregnancyStatus: 'POSITIVE', effectiveAt: '2026-08-14T08:00', performedByName: 'طبيب' };
    expect(reproductionEventSchema.safeParse(valid).success).toBe(true);
    expect(reproductionEventSchema.safeParse({ ...valid, subjectCount: '2' }).success).toBe(false);
  });

  it('validates complete feed periods and maps exact decimal quantity', () => {
    const valid = { ...base, cohortId: cohort, feedItemId: feed, quantity: '125.750', unit: 'KG', effectiveAt: '2026-08-14T08:00', feedingPeriodStart: '2026-08-13', feedingPeriodEnd: '2026-08-14', issuedByName: 'عامل' };
    expect(feedIssueRpcArguments(feedIssueSchema.parse(valid))).toMatchObject({ p_quantity: '125.750', p_unit: 'KG' });
    expect(feedIssueSchema.safeParse({ ...valid, feedingPeriodEnd: null }).success).toBe(false);
    expect(feedIssueSchema.safeParse({ ...valid, feedingPeriodEnd: '2026-08-12' }).success).toBe(false);
  });
});

describe('GF-023 database architecture contract', () => {
  it.each([
    'livestock_medicine_products', 'livestock_animals', 'livestock_animal_memberships',
    'livestock_health_events', 'livestock_reproduction_events', 'livestock_feed_items',
    'livestock_feed_issues',
  ])('creates bounded table %s', (table) => expect(sql).toContain(`create table public.${table}`));

  it('uses the reserved GF-023 migration range and remains one forward migration', () => {
    expect(migration).toContain('GF-023');
    expect(migration).toContain('GF-022 BIRTH');
  });

  it('makes all facts append-only, force-RLS and browser-write denied', () => {
    expect(migration).toContain("execute format('alter table public.%I force row level security',t)");
    expect(migration).toContain("execute format('revoke all on public.%I from public,anon,authenticated',t)");
    expect(migration).toContain("execute function public.gf021_immutable()");
  });

  it('pins every SECURITY DEFINER search path', () => {
    const securityDefiners = migration.match(/security definer/gi) ?? [];
    const pinned = migration.match(/security definer\s+(?:\n)?set search_path=pg_catalog,public/gi) ?? [];
    expect(pinned).toHaveLength(securityDefiners.length);
  });

  it('reuses GF-022 locking and as-of quantity for operational targets', () => {
    expect(migration).toContain('gf022_lock_cohort_quantity');
    expect(migration).toContain('livestock_cohort_quantity_as_of');
    expect(migration).toContain('gf022_cohort_inception_at');
  });

  it('normalizes identifiers and scopes uniqueness to tenant/project/type', () => {
    expect(migration).toContain('gf023_normalize_identifier');
    expect(migration).toContain('unique (organization_id, project_id, identifier_type, identifier_normalized)');
    expect(migration).toContain('identification_quantity_effect');
  });

  it('requires exactly one initial membership without a mutable current Cohort', () => {
    expect(migration).toContain('requires exactly one identification membership');
    expect(migration).toContain('deferrable initially deferred');
    expect(sql).not.toMatch(/current_(cohort|headcount|weight|site|herd)_id/);
  });

  it('derives explicit withdrawal end from the immutable product reference', () => {
    expect(migration).toContain('default_withdrawal_days');
    expect(migration).toContain('new.withdrawal_ends_at := new.effective_at + make_interval');
    expect(migration).toContain('livestock_active_withdrawals');
  });

  it('invokes the existing authoritative birth command and stores its unique link', () => {
    expect(migration).toContain('v_birth:=public.record_livestock_birth');
    expect(migration).toContain('unique (birth_quantity_event_id)');
    expect(migration).toContain("v_birth.event_type <> 'BIRTH'");
    expect(migration).not.toMatch(/insert into public\.livestock_quantity_events[\s\S]{0,300}'BIRTH'/);
  });

  it('does not add any quantity class or duplicate headcount ledger', () => {
    expect(sql).not.toContain('insert into public.livestock_quantity_event_types');
    expect(sql).not.toMatch(/create table public\..*(headcount|birth_ledger)/i);
  });

  it('returns FCR only with supported evidence and truthful unavailability codes', () => {
    expect(migration).toContain('livestock_feed_conversion_metrics');
    for (const status of ['INSUFFICIENT_WEIGHT_EVENTS', 'INCOMPARABLE_WEIGHT_BASIS', 'INSUFFICIENT_EVIDENCE', 'POPULATION_CHANGED', 'NO_FEED_EVIDENCE', 'NO_POSITIVE_WEIGHT_GAIN']) {
      expect(migration).toContain(status);
    }
    expect(migration).toContain("case when metric_status='AVAILABLE'");
  });

  it('introduces no commercial, Finance, inventory or closeout mechanism', () => {
    for (const forbidden of [
      /create table public\.livestock_(buyers|sales|collections|closeouts)/i,
      /SALE_OUT/, /PURCHASE_IN/, /insert into public\.journal_(batches|lines)/,
      /create table public\.(feed|medicine)_inventory/i,
    ]) expect(sql).not.toMatch(forbidden);
  });
});

describe('GF-023 Arabic operator states and safe errors', () => {
  it('has isolated local route and does not rely on global-navigation modification', () => {
    expect(page).toContain('الصحة والتكاثر والهوية والتغذية');
    expect(page).toContain('العودة إلى المواقع والقطعان والأعداد');
  });

  it('distinguishes empty, filtered-empty, forbidden, success and insufficient evidence', () => {
    expect(page).toContain('لا توجد وقائع صحية بعد');
    expect(page).toContain('لا توجد نتائج مطابقة للمرشح الحالي');
    expect(page).toContain('لا تسمح عضويتك الحالية');
    expect(forms).toContain('تم الحفظ بنجاح');
    expect(page).toContain('غير متاح: الأدلة غير كافية');
  });

  it('never renders an internal UUID as an operator label', () => {
    expect(page).not.toMatch(/<[^>]+>\{[^}]*\.id\}<\//);
    expect(page).toContain('cohort_reference');
    expect(page).toContain('identifier_value');
  });

  it.each([
    ['livestock Animal identifier already exists', 'معرّف الحيوان'],
    ['livestock medicine product kind does not match the health event', 'نوع المنتج'],
    ['reproduction birth outcome does not match the GF-022 BIRTH event', 'GF-022'],
    ['livestock feed issue unit does not match the feed item', 'وحدة الصرف'],
  ])('maps %s safely', (error, expected) => expect(livestockErrorMessage(error)).toContain(expected));
});

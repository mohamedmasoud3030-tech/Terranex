import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { livestockErrorMessage } from '../src/features/livestock/errors';

const hardening = readFileSync(
  'supabase/migrations/20260814001910_livestock_gf022_review_hardening.sql',
  'utf8',
);
const weightPolicy = readFileSync(
  'supabase/migrations/20260814001920_livestock_weight_temporal_policy.sql',
  'utf8',
);
const page = readFileSync(
  'src/app/(app)/projects/[projectId]/livestock/page.tsx',
  'utf8',
);
const adr = readFileSync(
  'docs/decisions/0022_GF022_LIVESTOCK_BIOLOGICAL_QUANTITY_EVENTS.md',
  'utf8',
);

describe('GF-021/GF-022 review hardening contract', () => {
  it('derives quantity as of the requested business instant under the cohort lock', () => {
    expect(hardening).toContain('livestock_cohort_quantity_as_of');
    expect(hardening).toContain('q.effective_at <= p_as_of');
    expect(hardening).toContain('gf022_lock_cohort_quantity_as_of');
    expect(hardening).toContain("':livestock-quantity'");
  });

  it('rejects future quantity/movement actual facts and preserves operation business time', () => {
    expect(hardening).toContain('future livestock actual event is not allowed');
    expect(hardening).toContain('p_effective_at > clock_timestamp()');
    expect(hardening).toMatch(/livestock_cohort_initial_placements[\s\S]*placed_at[\s\S]*p_effective_at/);
  });

  it('makes species continuity and post-use herd species immutable DB rules', () => {
    expect(hardening).toContain('livestock movement must preserve cohort species');
    expect(hardening).toContain('livestock quantity operation must preserve species');
    expect(hardening).toContain('livestock herd species is immutable after cohort use');
  });

  it('checks exact split/merge operation shape at deferred commit time', () => {
    expect(hardening).toContain('livestock split requires exactly one out leg, one in leg and one lineage row');
    expect(hardening).toContain('livestock merge requires distinct out legs, one in leg and one lineage row per source');
    expect(hardening).toContain('deferrable initially deferred');
  });

  it('keeps WeightEvent as a dated log while retaining as-of population validation', () => {
    expect(weightPolicy).not.toContain('gf022_review_reject_future_actual(new.effective_at)');
    expect(weightPolicy).toContain('gf022_lock_cohort_quantity_as_of');
    expect(adr).toContain('do not derive one authoritative `current_weight`');
  });

  it('filters zero-population cohorts from consuming workflows but keeps Birth additive', () => {
    expect(page).toContain('positiveActiveCohorts');
    expect(page).toContain('cohorts={activeCohorts}');
    expect(page.match(/cohorts=\{positiveActiveCohorts\}/g)?.length).toBeGreaterThanOrEqual(4);
    expect(page).toContain('eligibleCohortIds={positiveActiveCohortIds}');
  });

  it('filters movement destination herds to the cohort species and explains the rule in Arabic', () => {
    expect(page).toContain('herd.species === placement.species');
    expect(page).toContain('تظهر فقط القطعان من نفس النوع الحيواني');
  });

  it('maps hardening failures to operator-safe Arabic messages', () => {
    expect(livestockErrorMessage('future livestock actual event is not allowed')).toContain('مستقبلية');
    expect(livestockErrorMessage('livestock movement must preserve cohort species')).toContain('نوع حيواني مختلف');
    expect(livestockErrorMessage('livestock cohort has zero quantity for this operation')).toContain('رصيد الدفعة صفر');
    expect(livestockErrorMessage('livestock quantity exceeds quantity as of effective time (10 available)')).toContain('وقت الواقعة');
  });

  it('records canonical fields that remain explicitly deferred instead of overclaiming them', () => {
    expect(adr).toContain('Sampled-weight confidence');
    expect(adr).toContain('Mortality disposal method');
    expect(page).toContain('ثقة الوزن بالعينة وطريقة التخلص من النافق مؤجلتان صراحة');
  });
});
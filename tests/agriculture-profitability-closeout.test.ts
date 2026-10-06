import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  cropCycleCloseoutSchema,
  cropCycleCostAttributionSchema,
} from '../src/features/agriculture/schema';
import { formatCostCategory, formatEvidenceCompleteness } from '../src/features/agriculture/labels';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260814001600_agriculture_profitability_closeout.sql');
const dbTest = read('supabase/tests/55_gf019_agriculture_profitability_closeout.sql');
const concurrency = read('supabase/tests/56_gf019_cost_attribution_concurrency.sh');
const forward = read('supabase/tests/57_gf019_agriculture_forward_upgrade.sh');
const actions = read('src/features/agriculture/actions.ts');
const queries = read('src/features/agriculture/queries.ts');
const forms = read('src/app/(app)/projects/[projectId]/agriculture/forms.tsx');
const page = read('src/app/(app)/projects/[projectId]/agriculture/page.tsx');
const nav = read('src/features/workspace/nav.tsx');
const loading = read('src/app/(app)/projects/[projectId]/agriculture/loading.tsx');
const error = read('src/app/(app)/projects/[projectId]/agriculture/error.tsx');
const routeError = read('src/shared/ui/route-error.tsx');
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

describe('GF-019 application validation and Arabic errors', () => {
  it('validates positive posted-cost attribution inputs and required evidence', () => {
    const valid = {
      organizationId: id(1), projectId: id(2), cropCycleId: id(3), fieldId: '',
      sourceJournalLineId: id(4), amount: '1250.50', currency: 'EGP', costCategory: 'LABOR',
      policyReference: 'سياسة تكلفة التشغيل', evidenceReference: 'كشف عمالة موثق',
      idempotencyKey: 'gf019-cost-test-001',
    };
    expect(cropCycleCostAttributionSchema.safeParse(valid).success).toBe(true);
    expect(cropCycleCostAttributionSchema.safeParse({ ...valid, amount: '0' }).success).toBe(false);
    expect(cropCycleCostAttributionSchema.safeParse({ ...valid, costCategory: 'LAND' }).success).toBe(false);
    expect(cropCycleCostAttributionSchema.safeParse({ ...valid, evidenceReference: '' }).success).toBe(false);
  });

  it('requires a close reason and evidence', () => {
    const valid = {
      organizationId: id(1), projectId: id(2), cropCycleId: id(3),
      closeReason: 'اكتملت أعمال الدورة', evidenceReference: 'محضر إغلاق 19',
      idempotencyKey: 'gf019-close-test-001',
    };
    expect(cropCycleCloseoutSchema.safeParse(valid).success).toBe(true);
    expect(cropCycleCloseoutSchema.safeParse({ ...valid, closeReason: '' }).success).toBe(false);
    expect(cropCycleCloseoutSchema.safeParse({ ...valid, evidenceReference: '' }).success).toBe(false);
  });

  it('maps operator labels without database or architecture jargon', () => {
    expect(formatCostCategory('LABOR')).toBe('عمالة');
    expect(formatCostCategory('INPUTS')).toBe('مدخلات زراعية');
    expect(formatEvidenceCompleteness('PARTIAL')).toContain('الأدلة');
    expect(actions).toContain('مقابل شراء الأرض أصل استثماري ولا يدخل في تكلفة تشغيل دورة المحصول');
    expect(actions).toContain('الإغلاق موقوف لأن كمية البيع لا تتطابق مع صرف المخزون');
  });
});

describe('GF-019 Finance and result architecture', () => {
  it('attributes only active Finance Core PROJECT_EXPENSE facts with a protected ceiling', () => {
    expect(migration).toContain("v_batch.source_type<>'COST_OBLIGATION'");
    expect(migration).toContain("v_role<>'PROJECT_EXPENSE'");
    expect(migration).toContain('source_journal_line_id uuid not null');
    expect(migration).toContain('crop cycle cost attribution exceeds authoritative source amount');
    expect(migration).toContain('for update');
    expect(migration).not.toMatch(/create table public\.(agriculture_expense_ledger|agriculture_journal|crop_cycle_profit_balances)/);
  });

  it('keeps land acquisition and non-owned land outside seasonal operating cost', () => {
    expect(migration).toContain('land acquisition consideration is not eligible for crop cycle operating cost');
    expect(migration).toContain("'EXCLUDED_FROM_CROP_CYCLE_OPERATING_COST'");
    expect(migration).not.toMatch(/depreciation_minor_units|amortization_minor_units|fair_value_minor_units/);
    expect(dbTest).toContain('s19_purchased_land_consideration_excluded');
    expect(dbTest).toContain('s19_no_land_depreciation_amortization_fair_value');
  });

  it('derives revenue, cash, receivable, physical inventory and result separately', () => {
    for (const field of [
      'recognized_revenue_minor_units', 'cash_collected_minor_units',
      'receivable_outstanding_minor_units', 'attributed_operating_cost_minor_units',
      'operating_result_to_date_minor_units', 'remaining_physical_inventory',
    ]) expect(queries).toContain(field);
    expect(migration).toContain("'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'");
    expect(migration).toContain("'NOT_GUESSED'");
    expect(migration).not.toMatch(/inventory_value_minor_units|cogs_minor_units|editable_profit/);
  });

  it('uses exact proportional cash allocation for the rare multi-cycle sale without duplicating cash', () => {
    expect(migration).toContain('floor(ct.collected::numeric*sca.cycle_amount/sca.sale_amount)');
    expect(migration).toContain('fraction_rank<=cr.remainder');
    expect(migration).toContain('collected-sum(base_amount) over(partition by sale_id)');
  });

  it('keeps cost correction append-only and protects the shared source reversal order', () => {
    expect(migration).toContain('reversal_of_attribution_id uuid');
    expect(migration).toContain('reverse active crop cycle cost attributions before reversing the Finance source');
    expect(actions).toContain("'attribute_crop_cycle_cost'");
    expect(dbTest).toContain('s19_append_only_cost_correction');
  });
});

describe('GF-019 closeout and technical controls', () => {
  it('reuses HARVESTING -> CLOSED and records immutable close metadata', () => {
    const fn = migration.split('create or replace function public.close_crop_cycle(')[1].split('end $$')[0];
    expect(fn).toContain("public.transition_crop_cycle(");
    expect(fn).toContain("'HARVESTING','CLOSED'");
    expect(fn).toContain('crop_cycle_integrity_issues_read');
    expect(migration).toContain('crop_cycle_closeouts_immutable');
  });

  it('allows outstanding inventory and receivable but blocks hard integrity issues', () => {
    expect(migration).toContain("'OPEN_INVENTORY','WARN'");
    expect(migration).toContain("'OPEN_RECEIVABLE','WARN'");
    for (const code of [
      'NO_HARVEST', 'NEGATIVE_INVENTORY', 'BROKEN_HARVEST_RECEIPT',
      'BROKEN_SALE_ISSUE', 'BROKEN_REVENUE_SOURCE', 'COLLECTION_CEILING_BROKEN',
      'COST_ATTRIBUTION_CEILING_BROKEN',
    ]) expect(migration).toContain(code);
    expect(dbTest).toContain('s19_close_allows_inventory_and_receivable');
  });

  it('uses stable replay before mutable state checks and emits one lifecycle audit', () => {
    const fn = migration.split('create or replace function public.close_crop_cycle(')[1].split('end $$')[0];
    expect(fn.indexOf('where organization_id=p_organization_id and idempotency_key')).toBeLessThan(fn.indexOf("<>'HARVESTING'"));
    expect(fn).toContain('Do not append a redundant success audit');
    expect(dbTest).toContain('s19_no_duplicate_transition_or_audit');
  });

  it('enforces tenant security and command-only writes', () => {
    expect(migration).toContain('force row level security');
    expect(migration).toContain('from public,anon,authenticated');
    expect(migration).toContain('with (security_invoker=on)');
    expect(migration).toContain('set search_path=pg_catalog,public');
    expect(dbTest).toContain('s19_tenant_b_result_rls');
    expect(dbTest).toContain('s19_rls_force_grants');
    expect(dbTest).toContain('s19_revenue_obeys_closed_period');
    expect(dbTest).toContain('s19_collection_obeys_closed_period');
    expect(dbTest).toContain('s19_authoritative_cost_source_obeys_closed_period');
  });

  it('retains real two-session harvest, sale, collection and new cost races', () => {
    expect(concurrency).toContain('expected exactly one success');
    expect(concurrency).toContain('run_session');
    expect(concurrency).toContain('& pa=$!');
    expect(read('supabase/tests/48_gf016_harvest_concurrency.sh')).toContain('run_session');
    expect(read('supabase/tests/53_gf018_sale_concurrency.sh')).toContain('collection ceiling race');
  });

  it('forward upgrades the exact GF-018 boundary and fingerprints the complete chain', () => {
    expect(forward).toContain('"20260814001600"');
    expect(forward).toContain("< '55_'");
    for (const key of ['land', 'farms', 'fields', 'cycles', 'activities', 'applications', 'harvest_events', 'movements', 'sales', 'recognitions', 'collections', 'batches', 'lines']) {
      expect(forward).toContain(`'${key}'`);
    }
    expect(forward).toContain('fixture is not genuinely pre-GF-019');
  });
});

describe('GF-019 Arabic RTL result UX', () => {
  it('answers the restrained operator result questions from canonical queries', () => {
    for (const label of [
      'النتائج والإغلاق', 'المساحة المزروعة/المشغلة', 'إجمالي الحصاد',
      'الإيراد المعترف به', 'المحصل', 'المتبقي للتحصيل', 'تكلفة التشغيل',
      'النتيجة التشغيلية الحالية', 'المخزون المتبقي', 'الأرض كأصل استثماري',
    ]) expect(page).toContain(label);
    expect(page).toContain('getCropCycleResults');
    expect(page).toContain('getCropCycleIntegrityIssues');
  });

  it('provides accessible blocked/successful close and cost forms', () => {
    expect(forms).toContain('aria-describedby');
    expect(forms).toContain('<output className="error">');
    expect(forms).toContain('الإغلاق موقوف حتى معالجة استثناءات السلامة الجوهرية');
    expect(forms).toContain('جارٍ فحص السلامة والإغلاق');
    expect(forms).toContain('هذا الربط لا ينشئ مصروفًا جديدًا');
  });

  it('states the input-stock deferral and no fake valuation/COGS boundary', () => {
    expect(page).toContain('تطبيق المدخل لا يدّعي التحقق من رصيد مخزون متاح');
    expect(page).toContain('قيمته غير متاحة وغير معترف بها');
    expect(page).toContain('ولا نحسب تكلفة بضاعة مباعة تخمينية');
  });

  it('adds shallow navigation and preserves honest loading/error/mobile contracts', () => {
    expect(nav).toContain("label: 'النتائج والإغلاق'");
    expect(nav).toContain('/agriculture#results-closeout');
    expect(loading).toContain('role="status"');
    // The boundary delegates its markup to the shared RouteError body, so the
    // alert semantics live there now. Assert the whole chain rather than one
    // link: this route wires the component up, and the component announces
    // itself. Asserting only this file would pass on a boundary that renders
    // nothing at all.
    expect(error).toContain("from '@/shared/ui/route-error'");
    expect(routeError).toContain('role="alert"');
    expect(page).toContain('overview-kpis');
    expect(page).toContain('table-wrap');
  });
});

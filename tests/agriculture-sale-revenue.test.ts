import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  agricultureSaleApprovalSchema,
  agricultureSaleCollectionSchema,
  agricultureSaleRecognitionSchema,
  agricultureSaleSchema,
} from '../src/features/agriculture/schema';
import { formatAgricultureSaleState, formatHarvestMovementType } from '../src/features/agriculture/labels';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260814001500_agriculture_sale_revenue.sql');
const dbTest = read('supabase/tests/52_gf018_agriculture_sale_revenue.sql');
const concurrency = read('supabase/tests/53_gf018_sale_concurrency.sh');
const forward = read('supabase/tests/54_gf018_sale_forward_upgrade.sh');
const actions = read('src/features/agriculture/actions.ts');
const queries = read('src/features/agriculture/queries.ts');
const forms = read('src/app/(app)/projects/[projectId]/agriculture/forms.tsx');
const page = read('src/app/(app)/projects/[projectId]/agriculture/page.tsx');
const nav = read('src/features/workspace/nav.tsx');

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const sale = {
  organizationId: id(1), projectId: id(2), buyerPartyId: id(3),
  saleReference: 'SALE-AG-001', agreementReference: 'PO-11', saleDate: '2026-08-14',
  currency: 'EGP', terms: 'تسليم من المخزن', evidenceReference: 'عقد موثق',
  linesJson: JSON.stringify([
    { harvestLotId: id(4), sourceStorageId: id(5), quantity: '12.5', unitPrice: '450.00' },
    { harvestLotId: id(6), sourceStorageId: id(5), quantity: '3', unitPrice: '510.00' },
  ]),
  idempotencyKey: 'gf018-sale-test-001',
};

describe('GF-018 application validation', () => {
  it('accepts bounded multi-line sales and rejects malformed, empty or non-positive lines', () => {
    const parsed = agricultureSaleSchema.safeParse(sale);
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.linesJson).toHaveLength(2);
    expect(agricultureSaleSchema.safeParse({ ...sale, linesJson: 'not-json' }).success).toBe(false);
    expect(agricultureSaleSchema.safeParse({ ...sale, linesJson: '[]' }).success).toBe(false);
    expect(agricultureSaleSchema.safeParse({
      ...sale,
      linesJson: JSON.stringify([{ harvestLotId: id(4), sourceStorageId: id(5), quantity: '0', unitPrice: '1.00' }]),
    }).success).toBe(false);
  });

  it('validates approval, delivery evidence, and collection evidence/money separately', () => {
    const base = { organizationId: id(1), projectId: id(2), saleId: id(3), idempotencyKey: 'gf018-approve-1' };
    expect(agricultureSaleApprovalSchema.safeParse(base).success).toBe(true);
    expect(agricultureSaleRecognitionSchema.safeParse({ ...base, controlTransferDate: '2026-08-14', evidenceReference: 'إذن تسليم' }).success).toBe(true);
    expect(agricultureSaleRecognitionSchema.safeParse({ ...base, controlTransferDate: '2026-08-14', evidenceReference: '' }).success).toBe(false);
    expect(agricultureSaleCollectionSchema.safeParse({
      organizationId: id(1), projectId: id(2), recognitionId: id(3), cashAccountId: id(4),
      amount: '1200.00', currency: 'EGP', collectionDate: '2026-08-14', evidenceReference: 'إيصال بنكي',
      idempotencyKey: 'gf018-collect-1',
    }).success).toBe(true);
  });
});

describe('GF-018 sale, dispatch and Finance Core boundary', () => {
  it('creates sector-specific commercial facts and extends inventory with a sale-line reference', () => {
    for (const table of ['agriculture_sales', 'agriculture_sale_lines', 'agriculture_sale_recognitions', 'agriculture_sale_collections']) {
      expect(migration).toContain(`create table public.${table}`);
    }
    expect(migration).toContain("'SALE_ISSUE'");
    expect(migration).toContain('agriculture_sale_line_id uuid');
    expect(migration).not.toMatch(/create table public\.(agriculture_journals|agriculture_receivable_ledger|agriculture_cash_ledger|agriculture_inventory_valuations)/);
  });

  it('makes control transfer one atomic dispatch plus revenue/receivable command', () => {
    const fn = migration.split('create or replace function public.recognize_agriculture_sale(')[1].split('end $$')[0];
    expect(fn).toContain("'SALE_ISSUE'");
    expect(fn).toContain("'AGRICULTURE_SALE_RECOGNITION'");
    expect(fn).toContain("role='CUSTOMER_RECEIVABLE'");
    expect(fn).toContain("role='AGRICULTURE_SALE_REVENUE'");
    expect(fn).toContain('harvest_lot_storage_balance');
    expect(fn).toContain('insert into public.journal_batches');
  });

  it('never guesses COGS or harvest inventory value', () => {
    expect(migration).not.toMatch(/role='REAL_ESTATE_COST_OF_SALE'|role='DEVELOPMENT_WIP'/);
    expect(migration).not.toMatch(/cogs_minor_units|inventory_value_minor_units|cost_of_goods_minor_units/);
    expect(dbTest).toContain('s18_no_invented_cogs_valuation');
    expect(page).toContain('لا توجد تكلفة بضاعة/مخزون مخمّنة');
  });

  it('protects partial/multiple collections with a locked immutable ceiling and shared cash account', () => {
    const fn = migration.split('create or replace function public.collect_agriculture_sale_receivable(')[1].split('end $$')[0];
    expect(fn).toContain('for update');
    expect(fn).toContain('collection exceeds outstanding agriculture receivable');
    expect(fn).toContain("role='BANK_CASH'");
    expect(migration).toContain('agriculture sale recognition, line and collection facts are immutable');
    for (const proof of ['s18_partial_multiple_collection', 's18_over_collection_rejected', 's18_collection_idempotent', 's18_settlement_is_derived_from_collections']) {
      expect(dbTest).toContain(proof);
    }
  });

  it('enforces tenant scope, command-only writes, forced RLS, audit and idempotent replay', () => {
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(migration).toContain('set search_path=pg_catalog,public');
    for (const proof of [
      's18_cross_tenant_rejected', 's18_tenant_b_rls', 's18_direct_dml_denied',
      's18_recognition_replay_after_collection_and_stock_change', 's18_revenue_and_audit_not_duplicated',
      's18_insufficient_inventory_atomic_rollback', 's18_no_duplicate_agriculture_ledger',
    ]) expect(dbTest).toContain(proof);
  });

  it('has genuine two-session oversell and collection-ceiling races', () => {
    expect(concurrency).toContain('expected exactly one success');
    expect(concurrency).toContain('concurrent oversell');
    expect(concurrency).toContain('collection ceiling race');
    expect(concurrency).toContain('harvest_lot_storage_balance');
  });

  it('forward-upgrades a full GF-017 boundary without changing historical rows', () => {
    expect(forward).toContain("10#${BASH_REMATCH[1]} < 52");
    expect(forward).toContain('genuinely pre-GF-018');
    for (const key of ['land', 'farm_land', 'harvest_events', 'movements', 'batches', 'lines', 'cash']) {
      expect(forward).toContain(`'${key}'`);
    }
  });
});

describe('GF-018 Arabic/RTL operator experience', () => {
  it('provides draft, approval, control-transfer and collection actions with Arabic errors', () => {
    for (const command of [
      'create_agriculture_sale', 'approve_agriculture_sale', 'recognize_agriculture_sale',
      'collect_agriculture_sale_receivable',
    ]) expect(actions).toContain(`'${command}'`);
    expect(actions).toContain('الرصيد المتاح لا يكفي لتسليم هذا البيع');
    expect(actions).toContain('مبلغ التحصيل يتجاوز الذمة المدينة المتبقية');
  });

  it('uses invoker read models and exposes lot-to-sale traceability', () => {
    for (const model of [
      'agriculture_sales_read', 'agriculture_sale_lines_read', 'agriculture_sale_collections_read',
      'harvest_lot_sale_traceability_read',
    ]) expect(queries).toContain(`'${model}'`);
    expect(migration).toContain('with (security_invoker=on)');
  });

  it('keeps operational and financial wording separate and derives the line unit from lot stock', () => {
    expect(forms).toContain('حفظ المسودة لا يصرف مخزونًا ولا يعترف بإيراد');
    expect(forms).toContain('وحدة البيع تأتي من تشغيلة الحصاد');
    expect(forms).toContain('صرف SALE_ISSUE من المخزون + إثبات البيع + إيراد وذمة مدينة');
    expect(page).toContain('النقد المحصل ليس هو الإيراد');
    expect(page).toContain('الذمة المتبقية');
    expect(page).toContain('خطوة واحدة للأمام من التشغيلة');
  });

  it('adds truthful Arabic navigation and lifecycle labels', () => {
    expect(nav).toContain('المبيعات والتحصيل');
    expect(nav).toContain('/agriculture#sales');
    expect(formatHarvestMovementType('SALE_ISSUE')).toBe('صرف بيع/تسليم');
    expect(formatAgricultureSaleState('DRAFT')).toBe('مسودة — لا مخزون ولا إيراد');
    expect(formatAgricultureSaleState('CONTROL_TRANSFERRED')).toBe('تم التسليم والاعتراف بالإيراد');
  });
});

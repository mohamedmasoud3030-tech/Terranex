import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  livestockCloseoutSchema,
  livestockCostAttributionSchema,
  livestockPurchaseSchema,
  livestockSaleApprovalSchema,
  livestockSaleCollectionSchema,
  livestockSaleRecognitionSchema,
  livestockSaleSchema,
} from '../src/features/livestock/schema';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260815020000_livestock_commercial_profitability_closeout.sql');
const dbTest = read('supabase/tests/71_gf024_livestock_commercial.sql');
const concurrency = read('supabase/tests/72_gf024_commercial_concurrency.sh');
const forward = read('supabase/tests/73_gf024_forward_upgrade.sh');
const page = read('src/app/(app)/projects/[projectId]/livestock/page.tsx');
const forms = read('src/app/(app)/projects/[projectId]/livestock/forms.tsx');
const queries = read('src/features/livestock/queries.ts');
const adr = read('docs/decisions/0024_GF024_LIVESTOCK_COMMERCIAL_PROFITABILITY_CLOSEOUT.md');

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

describe('GF-024 application validation', () => {
  it('accepts bounded multi-line purchases and sales, and rejects empty or non-positive lines', () => {
    const purchase = {
      organizationId: id(1),
      projectId: id(2),
      supplierPartyId: id(3),
      purchaseReference: 'PURCH-LS-001',
      agreementReference: 'PO-24',
      effectiveAt: '2026-08-05T08:00',
      evidenceReference: 'محضر استلام',
      linesJson: JSON.stringify([
        { cohortId: id(4), quantity: '20', agreedUnitPrice: '50000.00' },
        { cohortId: id(5), quantity: '3', agreedUnitPrice: null },
      ]),
      idempotencyKey: 'gf024-purchase-test-1',
    };
    expect(livestockPurchaseSchema.safeParse(purchase).success).toBe(true);
    expect(livestockPurchaseSchema.safeParse({ ...purchase, linesJson: '[]' }).success).toBe(false);
    expect(livestockPurchaseSchema.safeParse({
      ...purchase,
      linesJson: JSON.stringify([{ cohortId: id(4), quantity: '0', agreedUnitPrice: null }]),
    }).success).toBe(false);

    const sale = {
      organizationId: id(1),
      projectId: id(2),
      buyerPartyId: id(6),
      saleReference: 'SALE-LS-001',
      saleDate: '2026-08-14',
      currency: 'EGP',
      linesJson: JSON.stringify([
        { cohortId: id(4), quantity: '60', unitPrice: '8000.00' },
      ]),
      idempotencyKey: 'gf024-sale-test-1',
    };
    expect(livestockSaleSchema.safeParse(sale).success).toBe(true);
    expect(livestockSaleSchema.safeParse({ ...sale, linesJson: 'not-json' }).success).toBe(false);
    expect(livestockSaleSchema.safeParse({ ...sale, currency: 'usd' }).success).toBe(false);
  });

  it('validates approval, control transfer, collection, cost attribution and closeout separately', () => {
    const approval = { organizationId: id(1), projectId: id(2), saleId: id(3), idempotencyKey: 'gf024-approve-1' };
    expect(livestockSaleApprovalSchema.safeParse(approval).success).toBe(true);
    expect(livestockSaleRecognitionSchema.safeParse({
      ...approval, controlTransferDate: '2026-08-14', evidenceReference: 'إذن تسليم',
    }).success).toBe(true);
    expect(livestockSaleRecognitionSchema.safeParse({
      ...approval, controlTransferDate: '2026-08-14', evidenceReference: '',
    }).success).toBe(false);
    expect(livestockSaleCollectionSchema.safeParse({
      organizationId: id(1), projectId: id(2), recognitionId: id(3), cashAccountId: id(4),
      amount: '1200.00', currency: 'EGP', collectionDate: '2026-08-14',
      evidenceReference: 'إيصال بنكي', idempotencyKey: 'gf024-collect-1',
    }).success).toBe(true);
    expect(livestockSaleCollectionSchema.safeParse({
      organizationId: id(1), projectId: id(2), recognitionId: id(3), cashAccountId: id(4),
      amount: '0.00', currency: 'EGP', collectionDate: '2026-08-14',
      evidenceReference: 'إيصال بنكي', idempotencyKey: 'gf024-collect-1',
    }).success).toBe(false);
    expect(livestockCostAttributionSchema.safeParse({
      organizationId: id(1), projectId: id(2), cohortId: id(5), sourceJournalLineId: id(7),
      amount: '300000.00', currency: 'EGP', costCategory: 'FEED',
      policyReference: 'سياسة تحميل', evidenceReference: 'مذكرة', idempotencyKey: 'gf024-cost-1',
    }).success).toBe(true);
    expect(livestockCloseoutSchema.safeParse({
      organizationId: id(1), projectId: id(2), cohortId: id(5),
      closeReason: 'اكتمال النشاط', evidenceReference: 'مذكرة إقفال', idempotencyKey: 'gf024-close-1',
    }).success).toBe(true);
  });
});

describe('GF-024 schema, Finance Core reuse and honest accounting boundary', () => {
  it('registers PURCHASE_IN / SALE_OUT forward-only through the GF-021/022 registry', () => {
    expect(migration).toContain("'PURCHASE_IN'");
    expect(migration).toContain("'SALE_OUT'");
    expect(migration).toContain("introduced_in, requires_operation, requires_cause, requires_disposal");
    expect(migration).toContain('on conflict (code) do nothing');
    expect(migration).not.toMatch(/alter table public\.livestock_quantity_events[^;]*drop column|drop table public\.livestock_quantity_events/);
  });

  it('creates sector commercial facts and never a second ledger or mutable balances', () => {
    for (const table of [
      'livestock_purchases', 'livestock_purchase_lines',
      'livestock_sales', 'livestock_sale_lines', 'livestock_sale_recognitions',
      'livestock_sale_collections', 'livestock_cohort_cost_attributions',
      'livestock_cohort_closeouts',
    ]) expect(migration).toContain(`create table public.${table}`);
    expect(migration).not.toMatch(/create table public\.(livestock_journals|livestock_receivable_ledger|livestock_cash_ledger|livestock_valuation_ledger)/);
    expect(migration).not.toMatch(/current_headcount|available_animals|outstanding_receivable_minor_units\s+bigint\s+not null/);
  });

  it('extends the shared registries only with LIVESTOCK_SALE_REVENUE', () => {
    expect(migration).toContain("'LIVESTOCK_SALE_REVENUE'");
    expect(migration).toContain('role in (');
    expect(migration).not.toMatch(/LIVESTOCK_COST_OF_SALE|LIVESTOCK_SUPPLIER_PAYABLE|LIVESTOCK_BANK_CASH/);
  });

  it('makes control transfer one atomic SALE_OUT + revenue/receivable transaction', () => {
    const fn = migration.split('create function public.recognize_livestock_sale(')[1].split('end $$')[0];
    expect(fn).toContain("'SALE_OUT'");
    expect(fn).toContain("'LIVESTOCK_SALE_RECOGNITION'");
    expect(fn).toContain("role = 'CUSTOMER_RECEIVABLE'");
    expect(fn).toContain("role = 'LIVESTOCK_SALE_REVENUE'");
    expect(fn).toContain('livestock_cohort_quantity_as_of');
    expect(fn).toContain('insert into public.journal_batches');
    expect(fn).toContain("at time zone 'UTC'");
  });

  it('never guesses COGS, biological value, or IAS 41 fair value', () => {
    expect(migration).not.toMatch(/cogs_minor_units|inventory_value_minor_units|biological_asset_value_minor_units/);
    expect(migration).not.toMatch(/IAS_41|fair_value|fair value/i);
    expect(migration).toContain("'NOT_GUESSED'");
    expect(migration).toContain("'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'");
    expect(page).toContain('لا توجد تكلفة بضاعة مباعة');
    expect(adr).toContain('IAS 41');
  });

  it('enforces tenant scope, command-only writes, forced RLS, audit and idempotent replay', () => {
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(migration).toContain('set search_path=pg_catalog,public');
    for (const proof of [
      'gf24_cross_tenant_purchase_rejected', 'gf24_direct_dml_denied', 'gf24_inactive_member_rejected',
      'gf24_purchase_replay_idempotent', 'gf24_recognition_replay_idempotent',
      'gf24_collection_replay_idempotent', 'gf24_generic_sale_reversal_blocked',
      'gf24_sale_header_immutable_outside_transition', 'gf24_collection_facts_immutable',
    ]) expect(dbTest).toContain(proof);
  });

  it('has genuine two-session sale, collection, idempotency and ordering races', () => {
    expect(concurrency).toContain('expected exactly one success');
    expect(concurrency).toContain('concurrent oversell');
    expect(concurrency).toContain('collection ceiling race');
    expect(concurrency).toContain('idempotent duplicate purchase');
    expect(concurrency).toContain('same-day sale was supplied by a later-dated purchase');
    expect(concurrency).toContain('livestock_cohort_quantity_rollforward');
  });

  it('forward-upgrades a full GF-022 boundary without fabricating commercial facts', () => {
    expect(forward).toContain('20260815020000');
    expect(forward).toContain('genuinely pre-GF-024');
    expect(forward).toContain('NO_FABRICATED_COMMERCIAL');
    expect(forward).toContain('count(*)=8');
    expect(forward).toContain("'PURCHASE_IN'");
    expect(forward).toContain("'SALE_OUT'");
  });

  it('exposes the five Arabic commercial areas and honest metric status', () => {
    for (const label of ['المشتريات والإضافات', 'المبيعات', 'التحصيل', 'الربحية', 'الإقفال']) {
      expect(page).toContain(label);
    }
    expect(forms).toContain('تسجيل الشراء');
    expect(forms).toContain('حفظ مسودة البيع');
    expect(queries).toContain('livestock_cohort_results_read');
    expect(queries).toContain('cogs_status');
  });
});

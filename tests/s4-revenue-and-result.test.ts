import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  propertyAssetSchema,
  dispositionSchema,
  recognizeSaleSchema,
  collectionSchema,
  obligationSchema,
  propertyCostItemSchema,
  propertyValuationSchema,
} from '../src/features/real-estate/schema';

const s2 = readFileSync('supabase/migrations/20260811000300_s2_cost_and_cash.sql', 'utf8');
const s3 = readFileSync('supabase/migrations/20260811000400_s3_real_estate_sector.sql', 'utf8');
const s4 = readFileSync('supabase/migrations/20260811000500_s4_revenue_and_result.sql', 'utf8');

const orgId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const assetId = '00000000-0000-4000-8000-000000000003';
const partyId = '00000000-0000-4000-8000-000000000004';
const dispId = '00000000-0000-4000-8000-000000000005';
const receivableId = '00000000-0000-4000-8000-000000000006';
const accountId = '00000000-0000-4000-8000-000000000007';

describe('S4 schema validation', () => {
  it('validates property asset input', () => {
    expect(propertyAssetSchema.safeParse({
      organizationId: orgId,
      projectId,
      displayName: 'قطعة أرض النخيل',
      strategy: 'DEVELOP_SELL',
      currency: 'EGP',
      idempotencyKey: 'asset-00000001',
    }).success).toBe(true);

    expect(propertyAssetSchema.safeParse({
      organizationId: 'bad',
      projectId,
      displayName: 'x',
      strategy: 'DEVELOP_SELL',
      currency: 'EGP',
      idempotencyKey: 'short',
    }).success).toBe(false);
  });

  it('validates property cost item input', () => {
    expect(propertyCostItemSchema.safeParse({
      organizationId: orgId,
      projectId,
      propertyAssetId: assetId,
      costCategory: 'أعمال حفر',
      isCapitalizable: true,
      costAmount: '50000.00',
      currency: 'EGP',
      occurredOn: '2026-08-11',
      idempotencyKey: 'cost-00000001',
    }).success).toBe(true);
  });

  it('validates property valuation input', () => {
    expect(propertyValuationSchema.safeParse({
      organizationId: orgId,
      projectId,
      propertyAssetId: assetId,
      effectiveDate: '2026-08-11',
      valuerSource: 'شركة التقييم المعتمدة',
      method: 'مقارنة سوقية',
      valuationAmount: '5000000.00',
      currency: 'EGP',
      idempotencyKey: 'val-00000001',
    }).success).toBe(true);
  });

  it('validates disposition input', () => {
    expect(dispositionSchema.safeParse({
      organizationId: orgId,
      projectId,
      propertyAssetId: assetId,
      buyerPartyId: partyId,
      agreedProceeds: '10000000.00',
      currency: 'EGP',
      agreementDate: '2026-08-15',
      idempotencyKey: 'disp-00000001',
    }).success).toBe(true);

    expect(dispositionSchema.safeParse({
      organizationId: orgId,
      projectId,
      propertyAssetId: assetId,
      buyerPartyId: partyId,
      agreedProceeds: '0',
      currency: 'EGP',
      agreementDate: '2026-08-15',
      idempotencyKey: 'disp-00000002',
    }).success).toBe(false);
  });

  it('validates sale recognition input', () => {
    expect(recognizeSaleSchema.safeParse({
      organizationId: orgId,
      projectId,
      dispositionId: dispId,
      controlTransferDate: '2026-09-01',
      idempotencyKey: 'sale-00000001',
    }).success).toBe(true);

    expect(recognizeSaleSchema.safeParse({
      organizationId: orgId,
      projectId,
      dispositionId: dispId,
      controlTransferDate: '',
      idempotencyKey: 'sale-00000002',
    }).success).toBe(false);
  });

  it('validates collection input', () => {
    expect(collectionSchema.safeParse({
      organizationId: orgId,
      projectId,
      saleReceivableId: receivableId,
      collectionAmount: '5000000.00',
      currency: 'EGP',
      collectedOn: '2026-09-15',
      cashAccountId: accountId,
      idempotencyKey: 'coll-00000001',
    }).success).toBe(true);
  });

  it('validates obligation input', () => {
    expect(obligationSchema.safeParse({
      organizationId: orgId,
      projectId,
      supplierPartyId: partyId,
      amount: '250000.00',
      currency: 'EGP',
      costCategory: 'مقاول بناء',
      occurredOn: '2026-08-20',
      idempotencyKey: 'obl-00000001',
    }).success).toBe(true);
  });
});

describe('S2 database contract', () => {
  it('provides balanced double-entry journal with database enforcement', () => {
    expect(s2).toContain('journal_batch_balanced_guard');
    expect(s2).toContain('v_debits is distinct from v_credits');
    expect(s2).toContain('journal_lines_one_sided');
  });

  it('makes journal batches and lines immutable after posting', () => {
    expect(s2).toContain('posted journal batch is immutable except via reversal');
    expect(s2).toContain('journal lines are immutable once posted');
  });

  it('provides idempotent obligation and payment commands', () => {
    expect(s2).toContain('pg_advisory_xact_lock');
    expect(s2).toContain('record_obligation');
    expect(s2).toContain('record_payment');
    expect(s2).toContain('payment exceeds remaining obligation amount');
  });

  it('denies browser writes on all financial tables', () => {
    expect(s2).toContain('enable row level security');
    expect(s2).toContain('force row level security');
    expect(s2).not.toContain('grant insert on public.journal_batches to authenticated');
    expect(s2).not.toContain('grant insert on public.journal_lines to authenticated');
  });

  it('transports bigint money to JavaScript as text', () => {
    expect(s2).toContain('obligation_minor_units::text');
    expect(s2).toContain('payment_minor_units::text');
  });
});

describe('S3 database contract', () => {
  it('provides property assets with lifecycle states', () => {
    expect(s3).toContain('CANDIDATE');
    expect(s3).toContain('HELD');
    expect(s3).toContain('DEVELOPING');
    expect(s3).toContain('DISPOSING');
    expect(s3).toContain('DISPOSED');
  });

  it('provides authoritative carrying amount from posted costs', () => {
    expect(s3).toContain('property_carrying_amount');
    expect(s3).toContain('is_capitalizable');
    expect(s3).toContain('acquisition_cost_minor_units');
  });

  it('keeps valuations separate from posted financial facts', () => {
    expect(s3).toContain('property_valuations');
    expect(s3).toContain('valuation_minor_units');
    expect(s3).toContain('valuer_source');
    expect(s3).toContain('method');
  });

  it('denies browser writes on property tables', () => {
    expect(s3).toContain('enable row level security');
    expect(s3).not.toContain('grant insert on public.property_assets to authenticated');
  });
});

describe('S4 database contract', () => {
  it('separates disposition lifecycle states explicitly', () => {
    expect(s4).toContain("'DRAFT'");
    expect(s4).toContain("'APPROVED'");
    expect(s4).toContain("'CONTROL_TRANSFERRED'");
    expect(s4).toContain("'SETTLED'");
    expect(s4).toContain("'CANCELLED'");
  });

  it('prevents double-sale through database guard', () => {
    expect(s4).toContain('no_double_sale_guard');
    expect(s4).toContain('property asset already sold');
  });

  it('creates balanced revenue and cost derecognition postings atomically', () => {
    expect(s4).toContain('recognize_sale');
    expect(s4).toContain('revenue_journal_batch_id');
    expect(s4).toContain('cost_derecognition_journal_batch_id');
    expect(s4).toContain('property_sale_revenue');
    expect(s4).toContain('cost_of_sale');
  });

  it('fails sale recognition when carrying cost cannot be computed', () => {
    expect(s4).toContain('cannot compute carrying amount');
  });

  it('separates revenue recognition from cash collection', () => {
    expect(s4).toContain('sale_recognitions');
    expect(s4).toContain('sale_receivables');
    expect(s4).toContain('collections');
    expect(s4).toContain('collection exceeds outstanding receivable');
  });

  it('provides collection as independent cash posting', () => {
    expect(s4).toContain('Dr cash, Cr receivable');
    expect(s4).toContain('record_collection');
    expect(s4).toContain('تحصيل');
  });

  it('provides idempotent sale recognition and collection', () => {
    expect(s4).toContain('pg_advisory_xact_lock');
    expect(s4).toContain('sale-recognition:');
    expect(s4).toContain('collection:');
  });

  it('provides realized result as derived view from posted facts', () => {
    expect(s4).toContain('project_realized_result');
    expect(s4).toContain('recognized_revenue_minor_units');
    expect(s4).toContain('derecognized_carrying_cost_minor_units');
    expect(s4).toContain('selling_costs_minor_units');
    expect(s4).toContain('realized_result_minor_units');
    expect(s4).toContain('collected_cash_minor_units');
    expect(s4).toContain('outstanding_receivable_minor_units');
  });

  it('keeps valuation separate from realized result', () => {
    expect(s4).toContain('project_latest_valuation');
    expect(s4).not.toContain('valuation_minor_units + recognized_revenue_minor_units');
  });

  it('transports all S4 monetary amounts as text', () => {
    expect(s4).toContain('agreed_proceeds_minor_units::text');
    expect(s4).toContain('recognized_revenue_minor_units::text');
    expect(s4).toContain('collection_minor_units::text');
  });

  it('denies browser writes on all S4 tables', () => {
    expect(s4).not.toContain('grant insert on public.dispositions to authenticated');
    expect(s4).not.toContain('grant insert on public.sale_recognitions to authenticated');
    expect(s4).not.toContain('grant insert on public.collections to authenticated');
  });
});

describe('S4 accounting integrity', () => {
  it('posts revenue recognition as Dr receivable Cr revenue (not cash)', () => {
    expect(s4).toContain('v_receivable_account := public.ensure_financial_account(p_organization_id, \'receivable\'');
    expect(s4).toContain('v_revenue_account := public.ensure_financial_account(p_organization_id, \'property_sale_revenue\'');
    expect(s4).toContain('v_disposition.agreed_proceeds_minor_units, 0, p_project_currency, v_disposition.buyer_party_id');
    expect(s4).toContain('0, v_disposition.agreed_proceeds_minor_units, p_project_currency, \'property_asset\'');
  });

  it('posts cost derecognition as Dr cost of sale Cr inventory', () => {
    expect(s4).toContain('v_cost_of_sale_account := public.ensure_financial_account(p_organization_id, \'cost_of_sale\'');
    expect(s4).toContain('v_carrying_amount, 0, p_project_currency, \'property_asset\'');
    expect(s4).toContain('0, v_carrying_amount, p_project_currency, \'property_asset\'');
  });

  it('posts collection as Dr cash Cr receivable', () => {
    expect(s4).toContain('p_collection_minor_units, 0, p_currency, \'تحصيل\'');
    expect(s4).toContain('0, p_collection_minor_units, p_currency, \'تحصيل\'');
  });

  it('does not create revenue from cash receipt or bank statement', () => {
    expect(s4).not.toMatch(/cash.*revenue|bank.*revenue/i);
    expect(s2).toContain('bank statement lines are immutable external facts');
  });

  it('computes realized result as proceeds minus carrying cost minus selling costs', () => {
    expect(s4).toContain('v_realized_result := v_disposition.agreed_proceeds_minor_units - v_carrying_amount - v_disposition.selling_costs_minor_units');
  });
});

describe('S4 project lifecycle integration', () => {
  it('supports EXITING lifecycle state', () => {
    expect(s4).toContain("'EXITING'");
    expect(s4).toContain("set lifecycle_state = 'EXITING'");
  });

  it('marks property as DISPOSED after sale recognition', () => {
    expect(s4).toContain("set lifecycle_state = 'DISPOSED'");
  });
});

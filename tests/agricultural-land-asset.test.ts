import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  LAND_CONTROL_BASES,
  agriculturalLandAssetSchema,
  farmLandAssetLinkSchema,
} from '../src/features/agriculture/schema';
import { formatLandControlBasis } from '../src/features/agriculture/labels';

const migration = readFileSync('supabase/migrations/20260814001400_agricultural_land_asset.sql', 'utf8');
const dbTest = readFileSync('supabase/tests/50_gf017_agricultural_land_asset.sql', 'utf8');
const forward = readFileSync('supabase/tests/51_gf017_land_asset_forward_upgrade.sh', 'utf8');
const page = readFileSync('src/app/(app)/projects/[projectId]/agriculture/page.tsx', 'utf8');
const forms = readFileSync('src/app/(app)/projects/[projectId]/agriculture/forms.tsx', 'utf8');
const nav = readFileSync('src/features/workspace/nav.tsx', 'utf8');
const actions = readFileSync('src/features/agriculture/actions.ts', 'utf8');
const queries = readFileSync('src/features/agriculture/queries.ts', 'utf8');

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const base = {
  organizationId: id(1), projectId: id(2), name: 'أرض النيل', internalReference: 'LAND-001',
  legalReference: '', legalAreaQuantity: '25', areaUnit: 'FEDDAN', legalLocationDescription: '',
  controlStartDate: '2026-08-01', controlEndDate: '', counterpartyPartyId: id(3),
  agreementReference: 'عقد شراء 1', evidenceReference: 'مستند حيازة 1',
  agreedConsideration: '', considerationCurrency: '', considerationObligationId: '',
  idempotencyKey: 'gf017-land-test-001',
};

describe('GF-017 agricultural land validation', () => {
  it('accepts every bounded control basis and rejects an owned boolean substitute', () => {
    expect(LAND_CONTROL_BASES).toEqual(['PURCHASED', 'LEASED', 'CONTRIBUTED_IN_KIND', 'MANAGED_FOR_OWNER']);
    for (const controlBasis of LAND_CONTROL_BASES) {
      expect(agriculturalLandAssetSchema.safeParse({ ...base, controlBasis }).success).toBe(true);
    }
    expect(agriculturalLandAssetSchema.safeParse({ ...base, controlBasis: 'OWNED' }).success).toBe(false);
  });

  it('requires positive land area and matching purchase consideration/currency', () => {
    expect(agriculturalLandAssetSchema.safeParse({ ...base, controlBasis: 'PURCHASED', legalAreaQuantity: '0' }).success).toBe(false);
    expect(agriculturalLandAssetSchema.safeParse({ ...base, controlBasis: 'PURCHASED', agreedConsideration: '500000.00', considerationCurrency: 'EGP' }).success).toBe(true);
    expect(agriculturalLandAssetSchema.safeParse({ ...base, controlBasis: 'PURCHASED', agreedConsideration: '500000.00' }).success).toBe(false);
  });

  it('never allows purchase consideration on leased, in-kind, or managed land', () => {
    for (const controlBasis of ['LEASED', 'CONTRIBUTED_IN_KIND', 'MANAGED_FOR_OWNER'] as const) {
      expect(agriculturalLandAssetSchema.safeParse({
        ...base, controlBasis, agreedConsideration: '1.00', considerationCurrency: 'EGP',
      }).success).toBe(false);
    }
  });

  it('validates a project-coherent link payload', () => {
    expect(farmLandAssetLinkSchema.safeParse({
      organizationId: id(1), projectId: id(2), landAssetId: id(3), farmId: id(4),
      idempotencyKey: 'gf017-link-test-001',
    }).success).toBe(true);
  });
});

describe('GF-017 database and finance boundary', () => {
  it('models a sector-specific land asset and Farm link, not a universal asset engine', () => {
    expect(migration).toContain('create table public.agricultural_land_assets');
    expect(migration).toContain('create table public.farm_land_asset_links');
    expect(migration).not.toMatch(/create table public\.(assets|universal_assets|asset_types|asset_repository)/);
    expect(migration).not.toContain('alter table public.property_assets');
  });

  it('enforces tenant/project coherence, forced RLS, command-only writes and append-only facts', () => {
    expect(migration).toContain('foreign key (land_asset_id, organization_id, project_id)');
    expect(migration).toContain('foreign key (farm_id, organization_id, project_id)');
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(migration).toContain('agricultural land asset and farm linkage facts are immutable');
    expect(migration).toContain('set search_path=pg_catalog,public');
  });

  it('keeps contractual consideration distinct from payment, carrying value, valuation and cycle cost', () => {
    expect(migration).toContain('agreed_consideration_minor_units');
    expect(migration).toContain("'accounting_effect','NONE','payment_effect','NONE'");
    expect(migration).not.toMatch(/insert into public\.(project_payments|contributions|journal_batches|journal_lines)/);
    expect(migration).not.toMatch(/\b(carrying_amount_minor_units|valuation_minor_units|crop_cycle_cost_minor_units)\s+(bigint|numeric)/);
    expect(dbTest).toContain('s17_no_automatic_finance_or_cycle_cost');
  });

  it('proves replay, duplicate-domain error, all bases, RLS, cross-project rejection and Real Estate alignment', () => {
    for (const proof of [
      's17_all_control_bases', 's17_land_replay', 's17_duplicate_reference_domain_error',
      's17_cross_project_farm_rejected', 's17_tenant_b_rls', 's17_direct_dml_denied',
      's17_real_estate_alignment_unchanged', 's17_existing_farms_not_fabricated',
    ]) expect(dbTest).toContain(proof);
  });

  it('has a genuine forward upgrade fingerprint for all existing Agriculture layers', () => {
    for (const table of ['farms', 'fields', 'cycles', 'activities', 'input_applications', 'harvest_events', 'movements', 'property_assets']) {
      expect(forward).toContain(`'${table}'`);
    }
    expect(forward).toContain('genuinely pre-GF-017');
  });
});

describe('GF-017 Arabic/RTL operator experience', () => {
  it('makes land, Farm and Field meanings explicit and keeps historical Farms truthful', () => {
    expect(page).toContain('الأرض أصل استثماري/قانوني · المزرعة وحدة تشغيل · الحقل وحدة زراعية');
    expect(page).toContain('لا يوجد أصل استثماري مرتبط');
    expect(page).toContain('المزارع القائمة لن يُنشأ لها أصل وهمي');
    expect(nav).toContain('الأراضي والأصول');
    expect(nav).toContain('#land-assets');
  });

  it('uses non-ownership wording for leased and managed control', () => {
    expect(formatLandControlBasis('LEASED')).toContain('ليست مملوكة');
    expect(formatLandControlBasis('MANAGED_FOR_OWNER')).toContain('ليست مملوكة');
    expect(forms).toContain('لن ننشئ مساهمة نقدية أو دفعة وهمية');
  });

  it('uses the command and security-invoker read models without raw database errors', () => {
    expect(actions).toContain("'create_agricultural_land_asset'");
    expect(actions).toContain("'link_farm_to_agricultural_land_asset'");
    expect(actions).toContain('مرجع الأرض/الأصل مستخدم بالفعل');
    expect(queries).toContain("'agricultural_land_assets_read'");
    expect(queries).toContain("'farm_land_asset_links_read'");
  });
});

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  INPUT_BEARING_ACTIVITY_TYPES,
  INPUT_CATEGORIES,
  INPUT_CATEGORY_ACTIVITY,
  inputApplicationSchema,
  inputCategoryForActivity,
  inputItemSchema,
  inputLotSchema,
} from '../src/features/agriculture/schema';
import {
  formatInputCategory,
  formatInputQuantity,
  formatLotExpiryStatus,
} from '../src/features/agriculture/labels';

const migration = readFileSync(
  'supabase/migrations/20260814001200_agriculture_input_application.sql',
  'utf8',
);
const dbTest = readFileSync('supabase/tests/44_gf015_input_application.sql', 'utf8');
const upgradeTest = readFileSync(
  'supabase/tests/45_gf015_input_application_forward_upgrade.sh',
  'utf8',
);
const page = readFileSync('src/app/(app)/projects/[projectId]/agriculture/page.tsx', 'utf8');
const forms = readFileSync('src/app/(app)/projects/[projectId]/agriculture/forms.tsx', 'utf8');
const actions = readFileSync('src/features/agriculture/actions.ts', 'utf8');
const queries = readFileSync('src/features/agriculture/queries.ts', 'utf8');
const labels = readFileSync('src/features/agriculture/labels.ts', 'utf8');
const nav = readFileSync('src/features/workspace/nav.tsx', 'utf8');
const adr = readFileSync('docs/decisions/0015_GF015_INPUT_APPLICATION.md', 'utf8');

const uuid = '00000000-0000-4000-8000-000000000001';

describe('GF-015 input item schema', () => {
  const base = {
    organizationId: uuid,
    projectId: uuid,
    category: 'FERTILIZER' as const,
    name: 'يوريا 46%',
    applicationUnit: 'كجم',
    idempotencyKey: 'gf-015-item-key-0001',
  };

  it('accepts the three supported field-applied categories only', () => {
    expect(INPUT_CATEGORIES).toEqual(['SEED', 'FERTILIZER', 'CHEMICAL']);
    for (const category of INPUT_CATEGORIES) {
      expect(inputItemSchema.safeParse({ ...base, category }).success).toBe(true);
    }
  });

  it('rejects deferred non-field-applied categories', () => {
    expect(inputItemSchema.safeParse({ ...base, category: 'FUEL' }).success).toBe(false);
    expect(inputItemSchema.safeParse({ ...base, category: 'PACKAGING' }).success).toBe(false);
  });

  it('requires a name and an application unit', () => {
    expect(inputItemSchema.safeParse({ ...base, name: 'x' }).success).toBe(false);
    expect(inputItemSchema.safeParse({ ...base, applicationUnit: '' }).success).toBe(false);
  });

  it('has no price, supplier, stock, or valuation field in the contract', () => {
    const shape = Object.keys(inputItemSchema.shape);
    for (const forbidden of [
      'price', 'unitCost', 'supplierId', 'availableStock', 'currentQuantity',
      'remainingQuantity', 'lotBalance', 'onHandQuantity', 'valuation',
    ]) {
      expect(shape).not.toContain(forbidden);
    }
  });
});

describe('GF-015 input lot schema', () => {
  const base = {
    organizationId: uuid,
    projectId: uuid,
    inputItemId: uuid,
    lotReference: 'LOT-2027-001',
    idempotencyKey: 'gf-015-lot-key-0001',
  };

  it('accepts a minimal identity/traceability lot', () => {
    expect(inputLotSchema.safeParse(base).success).toBe(true);
  });

  it('rejects a manufacture date after the expiry date', () => {
    expect(inputLotSchema.safeParse({
      ...base, manufacturedOn: '2028-01-01', expiresOn: '2027-01-01',
    }).success).toBe(false);
    expect(inputLotSchema.safeParse({
      ...base, manufacturedOn: '2027-01-01', expiresOn: '2028-01-01',
    }).success).toBe(true);
  });

  it('does not model quantity received or any balance', () => {
    for (const forbidden of [
      'receivedQuantity', 'availableQuantity', 'remainingQuantity',
      'lotBalance', 'onHandQuantity', 'unit', 'unitCost',
    ]) {
      // An unknown key must not become part of the parsed lot payload.
      const parsed = inputLotSchema.safeParse({ ...base, [forbidden]: '100' });
      expect(parsed.success).toBe(true);
      expect(Object.keys(parsed.success ? parsed.data : {})).not.toContain(forbidden);
    }
  });
});

describe('GF-015 input application schema', () => {
  const base = {
    organizationId: uuid,
    projectId: uuid,
    fieldActivityId: uuid,
    inputItemId: uuid,
    inputLotId: uuid,
    applicationDate: '2027-06-01',
    quantity: '200',
    unit: 'كجم',
    appliedAreaQuantity: '4',
    appliedAreaUnit: 'FEDDAN' as const,
    idempotencyKey: 'gf-015-app-key-0001',
  };

  it('accepts a coherent application', () => {
    expect(inputApplicationSchema.safeParse(base).success).toBe(true);
  });

  it('requires a positive quantity and a positive treated area', () => {
    expect(inputApplicationSchema.safeParse({ ...base, quantity: '0' }).success).toBe(false);
    expect(inputApplicationSchema.safeParse({ ...base, quantity: '-1' }).success).toBe(false);
    expect(inputApplicationSchema.safeParse({ ...base, appliedAreaQuantity: '0' }).success).toBe(false);
    expect(inputApplicationSchema.safeParse({ ...base, appliedAreaQuantity: '-2' }).success).toBe(false);
  });

  it('restricts the treated-area unit to the canonical area vocabulary', () => {
    expect(inputApplicationSchema.safeParse({ ...base, appliedAreaUnit: 'ACRE' }).success).toBe(false);
    expect(inputApplicationSchema.safeParse({ ...base, appliedAreaUnit: 'HECTARE' }).success).toBe(true);
  });

  it('never asks the browser for the crop cycle, field, or assignment', () => {
    const shape = Object.keys(inputApplicationSchema.shape);
    expect(shape).not.toContain('cropCycleId');
    expect(shape).not.toContain('fieldId');
    expect(shape).not.toContain('assignmentId');
    expect(shape).toContain('fieldActivityId');
  });

  it('does not accept a browser-supplied actor or rate', () => {
    const shape = Object.keys(inputApplicationSchema.shape);
    expect(shape).not.toContain('recordedBy');
    expect(shape).not.toContain('operatorId');
    expect(shape).not.toContain('applicationRate');
  });
});

describe('GF-015 category/activity mapping', () => {
  it('maps exactly SEED→PLANT, FERTILIZER→FERTILIZE, CHEMICAL→SPRAY', () => {
    expect(INPUT_CATEGORY_ACTIVITY).toEqual({
      SEED: 'PLANT', FERTILIZER: 'FERTILIZE', CHEMICAL: 'SPRAY',
    });
    expect(INPUT_BEARING_ACTIVITY_TYPES).toEqual(['PLANT', 'FERTILIZE', 'SPRAY']);
  });

  it('never resolves an input category for a non-input activity', () => {
    expect(inputCategoryForActivity('PLANT')).toBe('SEED');
    expect(inputCategoryForActivity('FERTILIZE')).toBe('FERTILIZER');
    expect(inputCategoryForActivity('SPRAY')).toBe('CHEMICAL');
    for (const activity of ['SCOUT', 'IRRIGATE', 'WEED', 'PREPARE', 'OTHER', 'HARVEST']) {
      expect(inputCategoryForActivity(activity)).toBeNull();
    }
  });
});

describe('GF-015 migration contract', () => {
  it('creates the three tenant-owned tables and their invoker read views', () => {
    expect(migration).toContain('create table public.input_items');
    expect(migration).toContain('create table public.input_lots');
    expect(migration).toContain('create table public.input_applications');
    expect(migration).toContain('create or replace view public.input_items_read');
    expect(migration).toContain('create or replace view public.input_lots_read');
    expect(migration).toContain('create or replace view public.input_applications_read');
    expect(migration.match(/security_invoker=on/g)?.length).toBe(3);
  });

  it('creates exactly the three authoritative commands', () => {
    expect(migration).toContain('create or replace function public.create_input_item');
    expect(migration).toContain('create or replace function public.create_input_lot');
    expect(migration).toContain('create or replace function public.record_input_application');
    // Exactly three security-definer commands, and no fourth write path.
    expect(migration.match(/^security definer$/gm)?.length).toBe(3);
    expect(migration.match(/^create or replace function public\.\w+\($/gm)?.length).toBe(3);
    // Every function this migration defines — the three commands and
    // every guard trigger — pins its search_path.
    const definedFunctions = migration.match(/create or replace function public\.\w+/g) ?? [];
    const pinnedSearchPaths = migration.match(/set search_path\s*=\s*pg_catalog\s*,\s*public/g) ?? [];
    expect(pinnedSearchPaths.length).toBe(definedFunctions.length);
  });

  it('enforces coherence with database composite foreign keys, not only app checks', () => {
    expect(migration).toContain(
      'foreign key (assignment_id, organization_id, project_id, crop_cycle_id, field_id, applied_area_unit)',
    );
    expect(migration).toContain(
      'field_activity_id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_type',
    );
    expect(migration).toContain(
      'foreign key (input_item_id, organization_id, project_id, input_category, unit)',
    );
    expect(migration).toContain(
      'foreign key (input_lot_id, organization_id, project_id, input_item_id, unit)',
    );
    expect(migration).toContain(
      'foreign key (input_item_id, organization_id, project_id, unit)',
    );
  });

  it('constrains the activity/category mapping at the table boundary', () => {
    expect(migration).toContain('input_applications_category_activity_map');
    expect(migration).toContain("activity_type in ('PLANT','FERTILIZE','SPRAY')");
    expect(migration).toContain("input_category = 'SEED'       and activity_type = 'PLANT'");
    expect(migration).not.toMatch(/activity_type\s+in\s*\([^)]*'SCOUT'/);
    expect(migration).not.toMatch(/activity_type\s+in\s*\([^)]*'IRRIGATE'/);
  });

  it('enforces the area and expiry invariants for direct SQL too', () => {
    expect(migration).toContain('gf015_guard_input_application_invariants');
    expect(migration).toContain('applied area exceeds the assigned area');
    expect(migration).toContain('cannot be applied on');
    expect(migration).toContain('before insert on public.input_applications');
  });

  it('normalizes numerics before hashing so formatting is not a false mismatch', () => {
    expect(migration).toContain('(p_quantity::numeric(20,6))::text');
    expect(migration).toContain('(p_applied_area_quantity::numeric(20,6))::text');
    expect(migration).toContain('idempotency key payload mismatch');
    expect(migration).toContain('pg_advisory_xact_lock');
  });

  it('reuses the existing audit trail with distinct event types', () => {
    expect(migration).toContain('insert into public.audit_events');
    expect(migration).toContain('INPUT_ITEM_CREATED');
    expect(migration).toContain('INPUT_LOT_CREATED');
    expect(migration).toContain('INPUT_APPLICATION_RECORDED');
    expect(migration).not.toMatch(/create table public\.\w*(audit|event_log)/i);
  });

  it('is append-only and default-deny', () => {
    expect(migration).toContain('input applications are append-only');
    expect(migration).toContain('input catalog definitions are immutable once recorded');
    expect(migration.match(/enable row level security/g)).toBeTruthy();
    expect(migration).toContain('force row level security');
    expect(migration).toContain("revoke all on public.%I from public, anon, authenticated");
    expect(migration).toContain('grant select on public.%I to authenticated');
  });

  it('derives the actor from auth.uid() and never from a parameter', () => {
    expect(migration.match(/v_actor uuid := auth\.uid\(\)/g)?.length).toBe(3);
    expect(migration).not.toMatch(/p_recorded_by|p_created_by|p_actor/);
  });

  it('grants execute to authenticated only', () => {
    expect(migration).toContain('from public, anon;');
    expect(migration).toContain('to authenticated;');
    expect(migration).not.toMatch(/grant execute[\s\S]{0,200}to anon/);
    expect(migration).not.toMatch(/service_role/i);
  });

  it('does not create any inventory, stock, valuation or accounting artefact', () => {
    for (const forbidden of [
      'available_stock', 'current_quantity', 'remaining_quantity', 'lot_balance',
      'received_quantity', 'available_quantity', 'on_hand', 'unit_cost',
      'purchase_price', 'valuation_amount',
    ]) {
      expect(migration.toLowerCase()).not.toContain(`${forbidden} numeric`);
    }
    expect(migration).not.toMatch(/insert into public\.(journal_batches|journal_lines|cost_obligations|project_payments|s5_distributions|accounting_periods)/);
    expect(migration).not.toMatch(/create table public\.(inventory_movements|storage_locations|harvest_events|harvest_lots)/);
    // IAS 41 may only appear in the deferral commentary, never in
    // executable SQL.
    const executable = migration
      .split('\n')
      .filter((line) => !line.trimStart().startsWith('--'))
      .join('\n');
    expect(executable).not.toMatch(/IAS ?41/i);
    expect(executable).not.toMatch(/inventory|valuation|journal|obligation/i);
  });

  it('does not automate CropCycle lifecycle', () => {
    expect(migration).not.toContain('transition_crop_cycle');
    expect(migration).not.toContain('insert into public.crop_cycle_state_history');
  });

  it('records the intentional stock-validation boundary in the migration itself', () => {
    expect(migration).toContain('Available-stock validation begins only when the canonical');
    expect(migration).toContain('InventoryMovement slice exists');
  });

  it('qualifies pgcrypto digest with the proven single-escape replacement', () => {
    expect(migration).toContain("E'\\\\1' || quote_ident(v_pgcrypto_schema) || '.digest('");
    expect(migration).not.toContain("E'\\\\\\\\1'");
  });

  it('never edits an applied migration', () => {
    const gf014 = readFileSync(
      'supabase/migrations/20260813001100_agriculture_field_activity.sql',
      'utf8',
    );
    expect(gf014).not.toMatch(/input_item|input_lot|input_application/);
  });
});

describe('GF-015 database verification coverage', () => {
  it('covers happy path, idempotency, coherence, expiry, area, quantity and security', () => {
    for (const marker of [
      's15_application_scope_derived',
      's15_application_audit_once',
      's15_idempotent_same_payload',
      's15_idempotent_replay_does_not_re_audit',
      's15_no_duplicate_application',
      's15_payload_mismatch_rejected',
      's15_seed_against_fertilize_rejected',
      's15_fertilizer_against_plant_rejected',
      's15_chemical_against_scout_rejected',
      's15_expired_lot_rejected',
      's15_zero_area_rejected',
      's15_negative_area_rejected',
      's15_area_above_assignment_rejected',
      's15_area_unit_mismatch_rejected',
      's15_zero_quantity_rejected',
      's15_negative_quantity_rejected',
      's15_quantity_unit_mismatch_rejected',
      's15_anon_execute_denied',
      's15_direct_application_insert_denied',
      's15_application_update_rejected',
      's15_application_delete_rejected',
      's15_does_not_advance_lifecycle',
      's15_no_journal_batch',
      's15_no_fake_inventory_or_costing_columns',
      's15_tenant_b_cannot_read_applications',
      's15_rls_enabled_and_forced',
      's15_read_views_are_security_invoker',
      's15_no_direct_dml_grants',
    ]) {
      expect(dbTest).toContain(marker);
    }
  });

  it('constructs the forward-upgrade fixture at the real pre-GF-015 boundary', () => {
    // The skip list excludes the GF-015 family and every later family
    // (GF-016/GF-017/GF-018) so a later migration is never applied before
    // GF-015's own prerequisites.
    expect(upgradeTest).toContain('20260814001200*.sql|20260814001300*.sql|20260814001400*.sql|20260814001500*.sql|20260814001600*.sql) continue ;;');
    // Guard against the GF-014 defect: the skip list must not remove a
    // prerequisite, so the fixture asserts a minimum applied count.
    expect(upgradeTest).toContain('the skip list is too broad');
    expect(upgradeTest).toContain('field_activities where id');
    expect(upgradeTest).toContain('crop_cycle_field_assignments where id');
    expect(upgradeTest).toContain('sector = \'REAL_ESTATE\'');
  });

  it('keeps every earlier forward-upgrade fixture excluding the GF-015 family', () => {
    for (const file of [
      'supabase/tests/09_s3_forward_upgrade.sh',
      'supabase/tests/15_s4_forward_upgrade.sh',
      'supabase/tests/18_s6_forward_upgrade.sh',
      'supabase/tests/22_s5_forward_upgrade.sh',
      'supabase/tests/25_s7_forward_upgrade.sh',
      'supabase/tests/40_gf013_agriculture_forward_upgrade.sh',
      'supabase/tests/43_gf014_field_activity_forward_upgrade.sh',
    ]) {
      expect(readFileSync(file, 'utf8')).toContain('20260814*.sql');
    }
  });
});

describe('GF-015 application layer', () => {
  it('uses only the three command RPCs and the three read views', () => {
    expect(actions).toContain("'create_input_item'");
    expect(actions).toContain("'create_input_lot'");
    expect(actions).toContain("'record_input_application'");
    expect(queries).toContain('input_items_read');
    expect(queries).toContain('input_lots_read');
    expect(queries).toContain('input_applications_read');
    expect(actions).not.toMatch(/from\('input_(items|lots|applications)'\)/);
    expect(actions).not.toMatch(/service_role/i);
    expect(queries).not.toMatch(/service_role/i);
  });

  it('does not send the derived scope or the actor from the browser', () => {
    expect(actions).not.toContain('p_crop_cycle_id: value.cropCycleId,\n      p_field_activity_id');
    const applicationCall = actions.slice(
      actions.indexOf("'record_input_application'"),
      actions.indexOf("'create_storage_location'"),
    );
    expect(applicationCall).not.toContain('p_recorded_by');
    expect(applicationCall).not.toContain('p_assignment_id');
    expect(applicationCall).not.toContain('p_crop_cycle_id');
  });

  it('does not send project or unit when creating a lot', () => {
    const lotCall = actions.slice(
      actions.indexOf("'create_input_lot'"),
      actions.indexOf("'record_input_application'"),
    );
    expect(lotCall).not.toContain('p_project_id');
    expect(lotCall).not.toContain('p_unit');
  });

  it('maps every server invariant to a truthful Arabic operator message', () => {
    expect(actions).toContain('التقاوي تُسجَّل على نشاط زراعة فقط.');
    expect(actions).toContain('السماد يُسجَّل على نشاط تسميد فقط.');
    expect(actions).toContain('المبيد/الكيماوي يُسجَّل على نشاط رش فقط.');
    expect(actions).toContain('التشغيلة منتهية الصلاحية في تاريخ التطبيق ولا يمكن تسجيلها.');
    expect(actions).toContain('المساحة المعالجة تتجاوز المساحة المخصصة لهذا التخصيص.');
    expect(actions).toContain('وحدة الكمية يجب أن تطابق وحدة تطبيق المدخل.');
  });

  it('reports natural-key collisions as domain errors instead of leaking constraint names', () => {
    // The commands pre-check the natural keys so a duplicate definition
    // surfaces an explainable message rather than a raw unique violation.
    expect(migration).toContain('input item already exists for this project and category');
    expect(migration).toContain('input lot reference already exists for this input item');
    expect(actions).toContain('يوجد مدخل بنفس الاسم والفئة في هذا المشروع.');
    expect(actions).toContain('مرجع التشغيلة مستخدم بالفعل لهذا المدخل.');
    // The pre-check must run after the idempotency replay lookup, so a
    // genuine retry still returns the original row instead of erroring.
    const itemFn = migration.slice(migration.indexOf('function public.create_input_item'));
    const body = itemFn.slice(0, itemFn.indexOf('$$ language plpgsql'));
    expect(body.indexOf('return v_existing.id')).toBeLessThan(body.indexOf('input item already exists'));
  });

  it('labels the slice in Arabic without inventing inventory or finance terms', () => {
    expect(formatInputCategory('SEED')).toBe('تقاوي');
    expect(formatInputCategory('FERTILIZER')).toBe('سماد');
    expect(formatInputCategory('CHEMICAL')).toBe('مبيد/كيماوي');
    expect(formatLotExpiryStatus('EXPIRED')).toBe('منتهية');
    expect(formatLotExpiryStatus('VALID')).toBe('سارية');
    expect(formatInputQuantity('200', 'كجم')).toBe('200 كجم');
    expect(formatInputQuantity(null, 'كجم')).toBe('—');
    expect(labels).not.toMatch(/رصيد المخزون|المخزون المتاح|تكلفة الوحدة/);
  });
});

describe('GF-015 workspace UI', () => {
  it('extends the existing Agriculture workspace with one shallow area', () => {
    expect(page).toContain('المدخلات والتطبيقات');
    expect(page).toContain('id="inputs"');
    expect(nav).toContain('المدخلات والتطبيقات');
    expect(nav).toContain('/agriculture#inputs');
    expect(nav).toContain('AGRICULTURE_SECTIONS');
  });

  it('surfaces input, lot, activity, field, cycle, date, quantity, area and expiry', () => {
    for (const heading of [
      'المدخل', 'التشغيلة', 'النشاط', 'الدورة', 'الحقل',
      'التاريخ', 'الكمية', 'المساحة المعالجة', 'الصلاحية',
    ]) {
      expect(page).toContain(heading);
    }
    expect(page).toContain('InputApplicationForm');
    expect(page).toContain('InputItemForm');
    expect(page).toContain('InputLotForm');
  });

  it('constrains selection so invalid combinations are hard to choose', () => {
    expect(forms).toContain('INPUT_BEARING_ACTIVITY_TYPES');
    expect(forms).toContain('inputCategoryForActivity');
    expect(forms).toContain('l.input_item_id === item?.id');
    expect(forms).toContain('l.expires_on >= activity.activity_date');
    // The six identifiers the activity already knows are shown, not asked for.
    expect(forms).toContain('النشاط يحدد المشروع ودورة المحصول والحقل والتخصيص تلقائيًا');
    expect(forms).not.toContain('name="cropCycleId"\n          required');
  });

  it('states the input-stock boundary honestly in the evolved operator UI', () => {
    expect(page).toContain('لا يوجد رصيد مخزون للمدخلات ولا تحقق من توفر كمياتها');
    expect(forms).toContain('النظام لا يتحقق من توفر رصيد مخزون');
    expect(page).not.toMatch(/رصيد مخزون المدخلات المتاح|قيمة مخزون المدخلات/);
  });

  it('shows the derived rate as derived, not as a stored authoritative value', () => {
    expect(page).toContain('المعدل قيمة مشتقة للعرض');
    expect(queries).toContain('Derived for display only');
  });

  it('does not redesign or reference unrelated Real Estate screens', () => {
    expect(page).not.toMatch(/getProperty|property_assets|real_estate/i);
    expect(forms).not.toContain('property_assets');
  });

  it('preserves GF-015 inputs while later bounded harvest and sale slices evolve the workspace', () => {
    expect(page).toContain('الحصاد والمخزون');
    expect(page).toContain('المبيعات والتحصيل');
    expect(forms).toMatch(/HarvestEventForm/);
    expect(forms).toMatch(/AgricultureSaleForm/);
    expect(actions).toMatch(/recordHarvestEvent/);
    expect(actions).toMatch(/createAgricultureSale/);
    // Livestock, purchasing and warehouse ERP remain outside Agriculture scope.
    expect(page).not.toMatch(/ماشية|IAS 41|أمر شراء|إدارة مستودعات/);
    expect(forms).not.toMatch(/livestock|warehouse|purchaseOrder|createInvoice/i);
    expect(actions).not.toMatch(/createInvoice|createBuyer|createPurchaseOrder/i);
  });
});

describe('GF-015 ADR', () => {
  it('records why stock availability is intentionally not modelled', () => {
    expect(adr).toMatch(/InventoryMovement/);
    expect(adr).toMatch(/intentional architecture/i);
    expect(adr).toMatch(/GF-016/);
  });

  it('records the mapping, area, expiry, idempotency and audit decisions', () => {
    expect(adr).toMatch(/SEED.*PLANT/);
    expect(adr).toMatch(/FERTILIZER.*FERTILIZE/);
    expect(adr).toMatch(/CHEMICAL.*SPRAY/);
    expect(adr).toMatch(/expires_on/);
    expect(adr).toMatch(/assigned area/i);
    expect(adr).toMatch(/audit_events/);
    expect(adr).toMatch(/no accounting|accounting side effect/i);
  });
});

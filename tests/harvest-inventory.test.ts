import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  HARVEST_MOVEMENT_TYPES,
  harvestEventSchema,
  harvestInventoryAdjustmentSchema,
  storageLocationSchema,
  transferHarvestInventorySchema,
} from '../src/features/agriculture/schema';
import {
  formatHarvestMovementType,
  formatHarvestQuantity,
} from '../src/features/agriculture/labels';

const migration = readFileSync(
  'supabase/migrations/20260814001300_agriculture_harvest_inventory.sql',
  'utf8',
);
const dbTest = readFileSync('supabase/tests/47_gf016_harvest_inventory.sql', 'utf8');
const concurrencyTest = readFileSync('supabase/tests/48_gf016_harvest_concurrency.sh', 'utf8');
const upgradeTest = readFileSync(
  'supabase/tests/49_gf016_harvest_inventory_forward_upgrade.sh',
  'utf8',
);
const page = readFileSync('src/app/(app)/projects/[projectId]/agriculture/page.tsx', 'utf8');
const forms = readFileSync('src/app/(app)/projects/[projectId]/agriculture/forms.tsx', 'utf8');
const actions = readFileSync('src/features/agriculture/actions.ts', 'utf8');
const queries = readFileSync('src/features/agriculture/queries.ts', 'utf8');
const labels = readFileSync('src/features/agriculture/labels.ts', 'utf8');
const nav = readFileSync('src/features/workspace/nav.tsx', 'utf8');
const adr = readFileSync('docs/decisions/0016_GF016_HARVEST_INVENTORY.md', 'utf8');

const uuid = '00000000-0000-4000-8000-000000000001';

describe('GF-016 storage location schema', () => {
  const base = {
    organizationId: uuid,
    projectId: uuid,
    name: 'مخزن رئيسي',
    idempotencyKey: 'gf-016-storage-key-01',
  };

  it('accepts a minimal storage location', () => {
    expect(storageLocationSchema.safeParse(base).success).toBe(true);
  });

  it('rejects an empty or single-character name', () => {
    expect(storageLocationSchema.safeParse({ ...base, name: '' }).success).toBe(false);
    expect(storageLocationSchema.safeParse({ ...base, name: 'x' }).success).toBe(false);
  });

  it('has no capacity, zone, bin, or temperature field', () => {
    const shape = Object.keys(storageLocationSchema.shape);
    for (const forbidden of ['capacity', 'zone', 'bin', 'rack', 'temperature']) {
      expect(shape).not.toContain(forbidden);
    }
  });
});

describe('GF-016 harvest event schema', () => {
  const base = {
    organizationId: uuid,
    projectId: uuid,
    assignmentId: uuid,
    harvestDate: '2027-08-01',
    grossQuantity: '100',
    netQuantity: '95',
    quantityUnit: 'كجم',
    lotReference: 'LOT-HV-001',
    destinationStorageId: uuid,
    idempotencyKey: 'gf-016-harvest-key-01',
  };

  it('accepts a coherent harvest', () => {
    expect(harvestEventSchema.safeParse(base).success).toBe(true);
  });

  it('rejects non-positive gross or net quantity', () => {
    expect(harvestEventSchema.safeParse({ ...base, grossQuantity: '0' }).success).toBe(false);
    expect(harvestEventSchema.safeParse({ ...base, grossQuantity: '-1' }).success).toBe(false);
    expect(harvestEventSchema.safeParse({ ...base, netQuantity: '0' }).success).toBe(false);
    expect(harvestEventSchema.safeParse({ ...base, netQuantity: '-2' }).success).toBe(false);
  });

  it('rejects net quantity above gross quantity', () => {
    expect(harvestEventSchema.safeParse({ ...base, netQuantity: '101' }).success).toBe(false);
  });

  it('never asks the browser for the crop cycle, field, or project-derived identifiers', () => {
    const shape = Object.keys(harvestEventSchema.shape);
    expect(shape).not.toContain('cropCycleId');
    expect(shape).not.toContain('fieldId');
    expect(shape).toContain('assignmentId');
  });

  it('does not accept a browser-supplied actor or stored loss', () => {
    const shape = Object.keys(harvestEventSchema.shape);
    expect(shape).not.toContain('recordedBy');
    expect(shape).not.toContain('harvestLoss');
  });
});

describe('GF-016 movement schemas', () => {
  const transferBase = {
    organizationId: uuid,
    projectId: uuid,
    harvestLotId: uuid,
    fromStorageId: uuid,
    toStorageId: '00000000-0000-4000-8000-000000000002',
    quantity: '30',
    movementDate: '2027-08-05',
    idempotencyKey: 'gf-016-transfer-key-01',
  };

  it('rejects a transfer to the same storage location', () => {
    expect(transferHarvestInventorySchema.safeParse({
      ...transferBase, toStorageId: transferBase.fromStorageId,
    }).success).toBe(false);
  });

  it('does not accept a browser-supplied unit on a transfer', () => {
    expect(Object.keys(transferHarvestInventorySchema.shape)).not.toContain('unit');
  });

  const adjustmentBase = {
    organizationId: uuid,
    projectId: uuid,
    harvestLotId: uuid,
    storageId: uuid,
    movementType: 'ADJUSTMENT_OUT' as const,
    quantity: '5',
    movementDate: '2027-08-06',
    reason: 'تسوية جرد',
    idempotencyKey: 'gf-016-adjustment-key-01',
  };

  it('requires a meaningful reason for an adjustment', () => {
    expect(harvestInventoryAdjustmentSchema.safeParse({
      ...adjustmentBase, reason: '',
    }).success).toBe(false);
    expect(harvestInventoryAdjustmentSchema.safeParse({
      ...adjustmentBase, reason: 'تسوية جرد فعلي',
    }).success).toBe(true);
  });

  it('keeps the GF-016 movement vocabulary and accepts the bounded GF-018 sale issue extension', () => {
    expect(HARVEST_MOVEMENT_TYPES).toEqual([
      'HARVEST_RECEIPT', 'TRANSFER', 'ADJUSTMENT_IN', 'ADJUSTMENT_OUT', 'SPOILAGE',
      'SALE_ISSUE',
    ]);
  });
});

describe('GF-016 migration contract', () => {
  it('creates the four tenant-owned tables and five invoker read views', () => {
    for (const t of [
      'storage_locations', 'harvest_events', 'harvest_lots', 'harvest_inventory_movements',
    ]) {
      expect(migration).toContain(`create table public.${t}`);
    }
    for (const v of [
      'storage_locations_read', 'harvest_events_read', 'harvest_lots_read',
      'harvest_inventory_by_location_read', 'harvest_inventory_movements_read',
    ]) {
      expect(migration).toContain(`create or replace view public.${v}`);
    }
    expect(migration.match(/security_invoker=on/g)?.length).toBe(5);
  });

  it('creates exactly the four authoritative commands', () => {
    expect(migration).toContain('create or replace function public.create_storage_location');
    expect(migration).toContain('create or replace function public.record_harvest_event');
    expect(migration).toContain('create or replace function public.transfer_harvest_inventory');
    expect(migration).toContain('create or replace function public.record_harvest_inventory_adjustment');
    expect(migration.match(/^security definer$/gm)?.length).toBe(4);
  });

  it('enforces scope and unit coherence with composite foreign keys', () => {
    expect(migration).toContain(
      'foreign key (assignment_id, organization_id, project_id, crop_cycle_id, field_id)',
    );
    expect(migration).toContain(
      'harvest_event_id, organization_id, project_id,\n    crop_cycle_id, field_id, assignment_id, quantity_unit,\n    initial_quantity, harvest_date',
    );
    expect(migration).toContain(
      'foreign key (harvest_lot_id, organization_id, project_id, unit)',
    );
    expect(migration).toContain(
      'foreign key (from_storage_id, organization_id, project_id)',
    );
  });

  it('enforces initial_quantity = net_quantity and harvest-date equality at the database boundary', () => {
    // The lot→event composite FK maps initial_quantity onto net_quantity and
    // harvest_date onto harvest_date, so privileged SQL cannot create a lot
    // whose initial quantity or date differs from its event.
    expect(migration).toContain(
      'crop_cycle_id, field_id, assignment_id, quantity_unit,\n    net_quantity, harvest_date',
    );
    expect(migration).toContain(
      'crop_cycle_id, field_id, assignment_id, quantity_unit,\n    initial_quantity, harvest_date\n  ) references public.harvest_events',
    );
  });

  it('allows exactly one HARVEST_RECEIPT per lot with receipt quantity/date equal to the lot', () => {
    expect(migration).toContain('harvest_inventory_movements_one_receipt');
    expect(migration).toContain("where movement_type = 'HARVEST_RECEIPT'");
    expect(migration).toContain('harvest receipt quantity % must equal the lot initial quantity');
    expect(migration).toContain('harvest receipt date % must equal the harvest date');
  });

  it('resolves the idempotency replay before lifecycle and balance checks', () => {
    // A true retry must return the original row before any mutable-state
    // check (cycle state or available balance) can reject it.
    const harvestFn = migration.slice(
      migration.indexOf('function public.record_harvest_event'),
      migration.indexOf('function public.transfer_harvest_inventory'),
    );
    expect(harvestFn.indexOf('return v_existing.id')).toBeLessThan(
      harvestFn.indexOf('not harvest-ready'),
    );
    const transferFn = migration.slice(
      migration.indexOf('function public.transfer_harvest_inventory'),
      migration.indexOf('function public.record_harvest_inventory_adjustment'),
    );
    expect(transferFn.indexOf('return v_existing.id')).toBeLessThan(
      transferFn.indexOf('insufficient inventory'),
    );
    const adjustmentFn = migration.slice(
      migration.indexOf('function public.record_harvest_inventory_adjustment'),
      migration.indexOf('8. Default-deny RLS'),
    );
    expect(adjustmentFn.indexOf('return v_existing.id')).toBeLessThan(
      adjustmentFn.indexOf('insufficient inventory'),
    );
  });

  it('enforces the harvest quantity invariant at the table boundary', () => {
    expect(migration).toContain('gross_quantity numeric(20,6) not null check (gross_quantity > 0)');
    expect(migration).toContain('net_quantity numeric(20,6) not null check (net_quantity > 0)');
    expect(migration).toContain('check (net_quantity <= gross_quantity)');
  });

  it('constrains movement types to the five canonical values without SALE_ISSUE', () => {
    expect(migration).toContain("movement_type in (\n    'HARVEST_RECEIPT','TRANSFER','ADJUSTMENT_IN','ADJUSTMENT_OUT','SPOILAGE'\n  )");
    // SALE_ISSUE may only appear in the deferral commentary, never in
    // executable SQL.
    const executable = migration
      .split('\n')
      .filter((line) => !line.trimStart().startsWith('--'))
      .join('\n');
    expect(executable).not.toMatch(/SALE_ISSUE/);
  });

  it('enforces the lifecycle rule and movement date rule in triggers', () => {
    expect(migration).toContain('gf016_guard_harvest_event_invariants');
    expect(migration).toContain('crop cycle is not harvest-ready');
    expect(migration).toContain('gf016_guard_harvest_inventory_movement_invariants');
    expect(migration).toContain('cannot precede the harvest date');
    expect(migration).toContain('insufficient inventory: available');
  });

  it('derives balance from movements and stores no mutable balance column', () => {
    expect(migration).toContain('harvest_lot_storage_balance');
    expect(migration).toContain('harvest_lot_total_balance');
    // No stored balance column: these names may appear in commentary and
    // in derived view aliases, but never as a mutable table column.
    expect(migration).not.toMatch(/on_hand\s+(numeric|text|bigint)/);
    expect(migration).not.toMatch(/available_quantity\s+(numeric|text|bigint)/);
    expect(migration).not.toMatch(/remaining_quantity\s+(numeric|text|bigint)/);
    expect(migration).not.toMatch(/current_balance\s+(numeric|text|bigint)/);
  });

  it('reuses the existing audit trail and derives the actor from auth.uid()', () => {
    expect(migration).toContain('insert into public.audit_events');
    expect(migration).toContain('STORAGE_LOCATION_CREATED');
    expect(migration).toContain('HARVEST_EVENT_RECORDED');
    expect(migration).toContain('HARVEST_INVENTORY_TRANSFERRED');
    expect(migration).toContain('HARVEST_INVENTORY_ADJUSTED');
    expect(migration).toContain('HARVEST_SPOILAGE_RECORDED');
    expect(migration.match(/v_actor uuid := auth\.uid\(\)/g)?.length).toBe(4);
    expect(migration).not.toMatch(/p_recorded_by|p_created_by|p_actor/);
    expect(migration).not.toMatch(/create table public\.\w*(audit|event_log)/i);
  });

  it('is append-only and default-deny', () => {
    expect(migration).toContain('harvest and inventory facts are append-only');
    expect(migration).toContain('enable row level security');
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.%I from public, anon, authenticated');
    expect(migration).toContain('grant select on public.%I to authenticated');
  });

  it('does not create sale, valuation, accounting or input-stock artefacts', () => {
    expect(migration).not.toMatch(/insert into public\.(journal_batches|journal_lines|cost_obligations|project_payments|s5_distributions|accounting_periods)/);
    expect(migration).not.toMatch(/create table public\.(sale_orders|purchase_orders|buyers|invoices|receivables|inventory_valuations)/);
    const executable = migration
      .split('\n')
      .filter((line) => !line.trimStart().startsWith('--'))
      .join('\n');
    expect(executable).not.toMatch(/SALE_ISSUE|valuation_amount|sale_price|available_stock/);
  });

  it('does not automate CropCycle lifecycle', () => {
    expect(migration).not.toContain('transition_crop_cycle');
    expect(migration).not.toContain('insert into public.crop_cycle_state_history');
  });

  it('qualifies pgcrypto digest with the proven single-escape replacement', () => {
    expect(migration).toContain("E'\\\\1' || quote_ident(v_pgcrypto_schema) || '.digest('");
    expect(migration).not.toContain("E'\\\\\\\\1'");
  });

  it('never edits an applied migration', () => {
    const gf015 = readFileSync(
      'supabase/migrations/20260814001200_agriculture_input_application.sql',
      'utf8',
    );
    expect(gf015).not.toMatch(/harvest_event|harvest_lot|storage_location|inventory_movement/);
  });
});

describe('GF-016 database verification coverage', () => {
  it('covers storage, harvest, quantity, lifecycle, transfer, adjustment and security', () => {
    for (const marker of [
      's16_storage_created',
      's16_storage_duplicate_domain_error',
      's16_storage_real_estate_rejected',
      's16_harvest_scope_derived',
      's16_initial_balance_equals_net_quantity',
      's16_initial_total_balance_equals_net_quantity',
      's16_harvest_audit_once',
      's16_harvest_audit_references_lot_and_receipt',
      's16_derived_loss',
      's16_gross_zero_rejected',
      's16_gross_negative_rejected',
      's16_net_zero_rejected',
      's16_net_negative_rejected',
      's16_net_over_gross_rejected',
      's16_harvest_not_ready_rejected',
      's16_lifecycle_unchanged_by_harvest',
      's16_guessed_assignment_rejected',
      's16_cross_project_storage_rejected',
      's16_harvest_idempotent_same_payload',
      's16_duplicate_lot_reference_domain_error',
      's16_transfer_source_decreased',
      's16_transfer_destination_increased',
      's16_transfer_total_unchanged',
      's16_same_source_destination_rejected',
      's16_transfer_overdraw_rejected',
      's16_movement_before_harvest_rejected',
      's16_adjustment_reason_required',
      's16_adjustment_in_increases',
      's16_adjustment_out_decreases',
      's16_adjustment_out_overdraw_rejected',
      's16_spoilage_decreases',
      's16_spoilage_overdraw_rejected',
      's16_harvest_update_rejected',
      's16_harvest_delete_rejected',
      's16_no_journal_batch',
      's16_input_tables_have_no_stock_columns',
      's16_sale_issue_phase_boundary_respected',
      's16_tenant_b_cannot_read_harvest_events',
      's16_harvest_replay_after_close',
      's16_transfer_replay_after_balance_change',
      's16_initial_quantity_mismatch_rejected',
      's16_second_receipt_rejected',
      's16_rls_enabled_and_forced',
      's16_read_views_are_security_invoker',
    ]) {
      expect(dbTest).toContain(marker);
    }
  });

  it('races two concurrent outbound movements against one lot/location', () => {
    expect(concurrencyTest).toContain('s16-conc-transfer-70');
    expect(concurrencyTest).toContain('s16-conc-transfer-60');
    expect(concurrencyTest).toContain('expected exactly one success');
    expect(concurrencyTest).toContain('harvest_lot_storage_balance');
    // The movement commands and the BEFORE INSERT trigger lock the lot row.
    expect(migration).toContain('for update');
  });

  it('constructs the forward-upgrade fixture at the real pre-GF-016 boundary', () => {
    expect(upgradeTest).toContain('20260814001300*.sql|20260814001400*.sql|20260814001500*.sql|20260814001600*.sql|20260815*.sql|20260816*.sql|202609*.sql) continue ;;');
    expect(upgradeTest).toContain('the skip list is too broad');
    expect(upgradeTest).toContain('input_applications where id');
    expect(upgradeTest).toContain("sector = 'REAL_ESTATE'");
    expect(upgradeTest).toContain('crop_cycle_field_assignments_harvest_scope_key');
  });
});

describe('GF-016 application layer', () => {
  it('uses the four command RPCs and five read views', () => {
    expect(actions).toContain("'create_storage_location'");
    expect(actions).toContain("'record_harvest_event'");
    expect(actions).toContain("'transfer_harvest_inventory'");
    expect(actions).toContain("'record_harvest_inventory_adjustment'");
    expect(queries).toContain('storage_locations_read');
    expect(queries).toContain('harvest_events_read');
    expect(queries).toContain('harvest_lots_read');
    expect(queries).toContain('harvest_inventory_by_location_read');
    expect(queries).toContain('harvest_inventory_movements_read');
    expect(actions).not.toMatch(/service_role/i);
    expect(queries).not.toMatch(/service_role/i);
  });

  it('does not send the derived scope, actor, or movement unit from the browser', () => {
    const harvestCall = actions.slice(
      actions.indexOf("'record_harvest_event'"),
      actions.indexOf("'transfer_harvest_inventory'"),
    );
    expect(harvestCall).not.toContain('p_recorded_by');
    expect(harvestCall).not.toContain('p_crop_cycle_id');
    expect(harvestCall).not.toContain('p_field_id');
    const transferCall = actions.slice(
      actions.indexOf("'transfer_harvest_inventory'"),
      actions.indexOf("'record_harvest_inventory_adjustment'"),
    );
    expect(transferCall).not.toContain('p_unit');
  });

  it('maps every server invariant to a truthful Arabic operator message', () => {
    expect(actions).toContain('دورة المحصول ليست جاهزة للحصاد.');
    expect(actions).toContain('الكمية الصافية يجب ألا تتجاوز الكمية الإجمالية.');
    expect(actions).toContain('مرجع تشغيلة الحصاد مستخدم بالفعل في هذا المشروع.');
    expect(actions).toContain('موقع التخزين المحدد غير موجود في هذا المشروع.');
    expect(actions).toContain('الرصيد المتاح غير كافٍ لهذه الحركة.');
    expect(actions).toContain('لا يمكن النقل إلى نفس موقع التخزين.');
    expect(actions).toContain('تاريخ الحركة لا يمكن أن يسبق تاريخ الحصاد.');
    expect(actions).toContain('سبب التعديل مطلوب.');
  });

  it('labels all current physical movement types in Arabic without inventing valuation terms', () => {
    expect(formatHarvestMovementType('HARVEST_RECEIPT')).toBe('استلام حصاد');
    expect(formatHarvestMovementType('TRANSFER')).toBe('تحويل');
    expect(formatHarvestMovementType('ADJUSTMENT_IN')).toBe('تعديل زيادة');
    expect(formatHarvestMovementType('ADJUSTMENT_OUT')).toBe('تعديل نقص');
    expect(formatHarvestMovementType('SPOILAGE')).toBe('تالف/هالك');
    expect(formatHarvestMovementType('SALE_ISSUE')).toBe('صرف بيع/تسليم');
    expect(formatHarvestQuantity('95', 'كجم')).toBe('95 كجم');
    expect(formatHarvestQuantity(null, 'كجم')).toBe('—');
    expect(labels).not.toMatch(/قيمة المخزون|تكلفة البضاعة|تقييم/);
  });
});

describe('GF-016 workspace UI', () => {
  it('extends the Agriculture workspace with the harvest/inventory area', () => {
    expect(page).toContain('الحصاد والمخزون');
    expect(page).toContain('id="harvest"');
    expect(nav).toContain('الحصاد والمخزون');
    expect(nav).toContain('/agriculture#harvest');
  });

  it('surfaces storage, harvest event, lot, location and movement forms', () => {
    expect(page).toContain('StorageLocationForm');
    expect(page).toContain('HarvestEventForm');
    expect(page).toContain('TransferHarvestInventoryForm');
    expect(page).toContain('HarvestInventoryAdjustmentForm');
  });

  it('blocks the harvest form when no cycle is harvest-ready', () => {
    expect(forms).toContain('operational_state === \'HARVESTING\'');
    expect(forms).toContain('لا توجد دورات محصول في حالة');
    expect(forms).toContain('انقل الدورة إلى حالة الحصاد أولًا');
  });

  it('derives the assignment and shows the derived balance, not a stored one', () => {
    expect(forms).toContain('التخصيص يحدد المشروع ودورة المحصول والحقل تلقائيًا');
    expect(forms).toContain('الرصيد الحالي');
    expect(queries).toContain('Derived for display only');
  });

  it('keeps harvest quantity, sale dispatch, valuation and input-stock boundaries honest', () => {
    expect(page).toContain('صرف البيع يخصم الكمية عبر حركة موثقة');
    expect(page).toContain('لا تُخمن قيمة للمخزون أو تكلفة بضاعة');
    expect(page).toContain('لا يوجد رصيد مخزون للمدخلات الزراعية');
    expect(page).not.toMatch(/قيمة المخزون المُقدرة|تكلفة بضاعة مُقدرة/);
  });

  it('does not redesign or reference unrelated Real Estate screens', () => {
    expect(page).not.toMatch(/getProperty|property_assets|real_estate/i);
    expect(forms).not.toContain('property_assets');
  });
});

describe('GF-016 ADR', () => {
  it('records why Harvest Event is separate from Field Activity and one Event → one Lot', () => {
    expect(adr).toMatch(/separate from Field Activity/);
    expect(adr).toMatch(/one Harvest Event produces one canonical Harvest Lot/i);
  });

  it('records the quantity invariant, atomic receipt, and derived balance decisions', () => {
    expect(adr).toMatch(/net_quantity <= gross_quantity/);
    expect(adr).toMatch(/initial `HARVEST_RECEIPT`/);
    expect(adr).toMatch(/derived from append-only movements/);
    expect(adr).toMatch(/concurrency-protected/);
  });

  it('records the deferred input-inventory and sale/accounting boundaries', () => {
    expect(adr).toMatch(/Input inventory remains outside scope/);
    expect(adr).toMatch(/Sale and accounting remain deferred/);
    expect(adr).toMatch(/GF-017/);
  });
});

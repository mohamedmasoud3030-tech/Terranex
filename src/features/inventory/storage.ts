import { requireClient } from '../../core/storage/supabaseClientRegistry';
import type { Currency, InventoryItem, InventoryMovement, InventoryStockRow } from '../../core/types/domain';

const ITEMS = 'inventory_items';
const MOVEMENTS = 'inventory_movements';
const VIEW_STOCK = 'inventory_stock';

export async function listInventoryItems(): Promise<InventoryItem[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(ITEMS).select('*').order('name_ar');
  if (error) throw new Error(`تعذر تحميل عناصر المخزون: ${error.message}`);
  return (data ?? []) as InventoryItem[];
}

export async function listStockLevels(): Promise<InventoryStockRow[]> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(VIEW_STOCK).select('*').order('name_ar');
  if (error) throw new Error(`تعذر تحميل مستويات المخزون: ${error.message}`);
  return (data ?? []) as InventoryStockRow[];
}

export async function listMovements(itemId?: string): Promise<InventoryMovement[]> {
  const supabase = requireClient();
  let q = supabase.from(MOVEMENTS).select('*').order('movement_date', { ascending: false });
  if (itemId) q = q.eq('item_id', itemId);
  const { data, error } = await q;
  if (error) throw new Error(`تعذر تحميل حركات المخزون: ${error.message}`);
  return (data ?? []) as InventoryMovement[];
}

export interface InventoryItemInput {
  name_ar: string;
  name_en?: string;
  sku?: string;
  category: InventoryItem['category'];
  unit: string;
  project_id?: string;
  reorder_level?: number;
  default_unit_cost?: number;
  currency?: Currency;
}

export async function createInventoryItem(input: InventoryItemInput): Promise<InventoryItem> {
  const supabase = requireClient();
  const { data, error } = await supabase.from(ITEMS).insert({
    ...input,
    reorder_level: input.reorder_level ?? 0,
    default_unit_cost: input.default_unit_cost ?? 0,
    currency: input.currency ?? 'OMR',
    is_archived: false,
  }).select().single();
  if (error) throw new Error(`تعذر إضافة الصنف: ${error.message}`);
  return data as InventoryItem;
}

export interface InventoryMovementInput {
  item_id: string;
  movement_type: InventoryMovement['movement_type'];
  quantity: number; // signed: positive for in, negative for out? schema uses separate types so always positive with type
  unit_cost?: number;
  currency?: Currency;
  fx_rate_to_base?: number;
  movement_date: string;
  notes?: string;
  reference_type?: string;
  reference_id?: string;
}

export async function recordMovement(input: InventoryMovementInput): Promise<InventoryMovement> {
  const supabase = requireClient();
  const qty = Math.abs(input.quantity);
  const unitCost = input.unit_cost ?? 0;
  const fx = input.fx_rate_to_base ?? 1;
  const currency = input.currency ?? 'OMR';
  const totalCostBase = Math.round(qty * unitCost * fx * 1000) / 1000;
  const { data, error } = await supabase.from(MOVEMENTS).insert({
    item_id: input.item_id,
    movement_type: input.movement_type,
    quantity: qty,
    unit_cost: unitCost,
    currency,
    fx_rate_to_base: fx,
    total_cost_base: totalCostBase,
    movement_date: input.movement_date,
    notes: input.notes ?? null,
    reference_type: input.reference_type ?? null,
    reference_id: input.reference_id ?? null,
  }).select().single();
  if (error) throw new Error(`تعذر تسجيل حركة المخزون: ${error.message}`);
  return data as InventoryMovement;
}

/**
 * Auto-consume inventory from operational events.
 *
 * When the user records a feed_consumption / fertilization / vaccination /
 * treatment event, we write a matching `consume` inventory movement if a
 * matching inventory item exists (fuzzy match by category) AND there is
 * stock available. This is best-effort and never blocks saving the event.
 *
 * A later pass can add an inventory-picker UI to EventForm to let the user
 * pick which item was consumed (see OPERATIONS-INVENTORY-BRIDGE follow-up).
 */
import type { OperationalEvent, InventoryItem } from '../../core/types/domain';
import { requireClient } from '../../core/storage/supabaseClientRegistry';

const CATEGORY_BY_EVENT: Record<string, InventoryItem['category'] | null> = {
  feed_consumption: 'feed',
  fertilization: 'fertilizer',
  vaccination: 'vaccine',
  treatment: 'medicine',
  seed_input: 'seed', // transaction category, not event — but useful for sowing later
};

/**
 * Best-effort: write a consume movement for the first matching inventory item
 * that has enough stock. Returns the movement id or null.
 */
export async function autoConsumeFromEvent(
  event: Pick<OperationalEvent, 'id' | 'type' | 'asset_id' | 'project_id' | 'quantity_delta' | 'event_date'> & { total_cost_egp?: number; unit_cost_egp?: number },
): Promise<string | null> {
  try {
    const category = CATEGORY_BY_EVENT[event.type];
    if (!category) return null;
    const qty = event.quantity_delta;
    // consumption events typically have negative quantity_delta; convert to positive.
    const consumeQty = Math.abs(Number(qty)) || 1;

    const supabase = requireClient();
    // Pick the most-stocked item in this category for the event's project.
    let query = supabase.from('inventory_stock')
      .select('*')
      .eq('category', category)
      .gt('quantity_on_hand', 0);
    if (event.project_id) query = query.eq('project_id', event.project_id);
    const { data, error } = await query.order('quantity_on_hand', { ascending: false }).limit(1);
    if (error || !data || data.length === 0) return null;

    const item = data[0] as InventoryItem & { quantity_on_hand: number };
    const takeQty = Math.min(consumeQty, item.quantity_on_hand);
    const unitCost = item.default_unit_cost;
    const fx = 1;
    const totalBase = Math.round(takeQty * unitCost * fx * 1000) / 1000;

    const { data: inserted, error: insErr } = await supabase
      .from('inventory_movements')
      .insert({
        item_id: item.id,
        movement_type: 'consume',
        quantity: takeQty,
        unit_cost: unitCost,
        currency: item.currency,
        fx_rate_to_base: fx,
        total_cost_base: totalBase,
        movement_date: event.event_date,
        reference_type: 'operational_event',
        reference_id: event.id,
        notes: `استهلاك تلقائي من حدث ${event.type}`,
      })
      .select('id')
      .single();
    if (insErr || !inserted) return null;
    return (inserted as { id: string }).id;
  } catch {
    return null;
  }
}

import { Package, Plus, AlertTriangle, ArrowUpCircle, ArrowDownCircle } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import { useI18n } from '../../core/i18n/context';
import { formatMoney } from '../../core/lib/format';
import type { Currency, InventoryCategory, InventoryStockRow } from '../../core/types/domain';
import { listStockLevels, createInventoryItem, recordMovement } from './storage';

const CATEGORY_LABELS: Record<InventoryCategory, { ar: string; en: string }> = {
  feed: { ar: 'أعلاف', en: 'Feed' },
  fertilizer: { ar: 'أسمدة', en: 'Fertilizer' },
  seed: { ar: 'بذور', en: 'Seeds' },
  medicine: { ar: 'أدوية', en: 'Medicine' },
  vaccine: { ar: 'تحصينات', en: 'Vaccine' },
  supply: { ar: 'مستلزمات', en: 'Supplies' },
  other: { ar: 'أخرى', en: 'Other' },
};

export function InventoryPage() {
  const { locale } = useI18n();
  const [rows, setRows] = useState<InventoryStockRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<null | 'item' | { kind: 'movement'; item: InventoryStockRow; type: 'in' | 'out' }>(null);
  const [selectedCategory, setSelectedCategory] = useState<string>('all');

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      setRows(await listStockLevels());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const categories = useMemo(() => {
    const set = new Set<string>(['all']);
    rows.forEach(r => set.add(r.category));
    return Array.from(set);
  }, [rows]);

  const filtered = useMemo(() =>
    selectedCategory === 'all' ? rows : rows.filter(r => r.category === selectedCategory),
    [rows, selectedCategory],
  );

  const lowStockCount = rows.filter(r => r.reorder_level > 0 && r.quantity_on_hand <= r.reorder_level).length;
  const totalValue = rows.reduce((s, r) => s + r.quantity_on_hand * r.default_unit_cost, 0);
  const baseCurrency: Currency = 'OMR';

  async function addItem(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    await createInventoryItem({
      name_ar: String(fd.get('name_ar') || ''),
      name_en: String(fd.get('name_en') || '') || undefined,
      sku: String(fd.get('sku') || '') || undefined,
      category: (fd.get('category') || 'other') as InventoryCategory,
      unit: String(fd.get('unit') || 'unit'),
      reorder_level: Number(fd.get('reorder_level')) || 0,
      default_unit_cost: Number(fd.get('default_unit_cost')) || 0,
      currency: (fd.get('currency') as Currency) || 'OMR',
    });
    setDialog(null);
    await refresh();
  }

  async function addMovement(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!dialog || typeof dialog === 'string') return;
    const fd = new FormData(e.currentTarget);
    const qty = Number(fd.get('quantity'));
    const type = dialog.type === 'in' ? 'purchase' : 'consume';
    await recordMovement({
      item_id: dialog.item.id,
      movement_type: type,
      quantity: qty,
      unit_cost: Number(fd.get('unit_cost')) || dialog.item.default_unit_cost,
      currency: dialog.item.currency,
      fx_rate_to_base: 1,
      movement_date: String(fd.get('movement_date')) || new Date().toISOString().slice(0, 10),
      notes: String(fd.get('notes')) || undefined,
    });
    setDialog(null);
    await refresh();
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={locale === 'ar' ? 'المخزون' : 'Inventory'}
        description={locale === 'ar' ? 'إدارة الأعلاف، الأسمدة، البذور، الأدوية والمستلزمات.' : 'Manage feed, fertilizer, seeds, medicine and supplies.'}
      >
        <Button onClick={() => setDialog('item')}>
          <Plus className="h-4 w-4" /> {locale === 'ar' ? 'صنف جديد' : 'New item'}
        </Button>
      </PageHeader>

      {error && <div className="rounded-2xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</div>}

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'عدد الأصناف' : 'Items'}</p><p className="text-xl font-bold">{rows.length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'قيمة المخزون' : 'Stock value'}</p><p className="text-xl font-bold text-primary">{formatMoney(totalValue, baseCurrency, locale)}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'أصناف تحت حد الطلب' : 'Low stock'}</p><p className="text-xl font-bold text-warning">{lowStockCount}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'فئات' : 'Categories'}</p><p className="text-xl font-bold">{categories.length - 1}</p></CardContent></Card>
      </div>

      <div className="flex gap-2 flex-wrap">
        {categories.map(c => (
          <button key={c} onClick={() => setSelectedCategory(c)}
            className={`rounded-full px-3 py-1 text-xs border transition ${selectedCategory === c ? 'border-primary bg-primary/10 text-primary' : 'border-border bg-card hover:bg-muted'}`}>
            {c === 'all' ? (locale === 'ar' ? 'الكل' : 'All') : CATEGORY_LABELS[c as InventoryCategory]?.[locale] ?? c}
          </button>
        ))}
      </div>

      <Card>
        <CardHeader>
          <h3 className="font-semibold flex items-center gap-2"><Package className="h-4 w-4 text-primary" /> {locale === 'ar' ? 'أصناف المخزون' : 'Stock items'}</h3>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <p className="p-8 text-center text-sm text-muted-foreground">...</p>
          ) : filtered.length === 0 ? (
            <p className="p-8 text-center text-sm text-muted-foreground">{locale === 'ar' ? 'لا توجد أصناف.' : 'No items.'}</p>
          ) : (
            <div className="divide-y divide-border">
              {filtered.map((item) => {
                const low = item.reorder_level > 0 && item.quantity_on_hand <= item.reorder_level;
                return (
                  <div key={item.id} className="flex items-center gap-3 px-4 py-3">
                    <div className={`flex h-9 w-9 items-center justify-center rounded-lg border ${low ? 'border-warning/40 bg-warning/10 text-warning' : 'border-primary/20 bg-primary/5 text-primary'}`}>
                      {low ? <AlertTriangle className="h-4 w-4" /> : <Package className="h-4 w-4" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{locale === 'ar' ? item.name_ar : (item.name_en ?? item.name_ar)}</p>
                      <p className="text-xs text-muted-foreground">
                        {CATEGORY_LABELS[item.category]?.[locale]} • {item.quantity_on_hand.toLocaleString(locale === 'ar' ? 'ar-EG' : 'en-US')} {item.unit}
                        {item.default_unit_cost > 0 && <> • {formatMoney(item.quantity_on_hand * item.default_unit_cost, item.currency, locale)}</>}
                      </p>
                    </div>
                    {low && <Badge tone="warning">{locale === 'ar' ? 'إعادة طلب' : 'Reorder'}</Badge>}
                    <div className="flex gap-1">
                      <button onClick={() => setDialog({ kind: 'movement', item, type: 'in' })} title={locale === 'ar' ? 'وارد' : 'Stock in'} className="rounded-lg p-2 text-success hover:bg-success/10">
                        <ArrowUpCircle className="h-4 w-4" />
                      </button>
                      <button onClick={() => setDialog({ kind: 'movement', item, type: 'out' })} title={locale === 'ar' ? 'منصرف' : 'Stock out'} className="rounded-lg p-2 text-danger hover:bg-danger/10">
                        <ArrowDownCircle className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {dialog === 'item' && (
        <div
          role="button"
          tabIndex={0}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 cursor-pointer"
          onClick={() => setDialog(null)}
          onKeyDown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') setDialog(null); }}
        >
          <form onSubmit={addItem} onClick={(e) => e.stopPropagation()} className="w-full max-w-lg space-y-3 rounded-2xl bg-card p-6 shadow-xl">
            <h3 className="font-semibold">{locale === 'ar' ? 'صنف جديد' : 'New inventory item'}</h3>
            <div className="grid gap-3 sm:grid-cols-2">
              <FormField><FormLabel>{locale === 'ar' ? 'الاسم (عربي)' : 'Name (AR)'}</FormLabel><input name="name_ar" required className="min-h-11 w-full rounded-xl border bg-background px-3" /></FormField>
              <FormField><FormLabel>{locale === 'ar' ? 'الاسم (إنجليزي)' : 'Name (EN)'}</FormLabel><input name="name_en" className="min-h-11 w-full rounded-xl border bg-background px-3" /></FormField>
              <FormField><FormLabel>{locale === 'ar' ? 'الفئة' : 'Category'}</FormLabel>
                <select name="category" className="min-h-11 w-full rounded-xl border bg-background px-3">
                  {Object.entries(CATEGORY_LABELS).map(([k, v]) => <option key={k} value={k}>{v[locale]}</option>)}
                </select>
              </FormField>
              <FormField><FormLabel>{locale === 'ar' ? 'الوحدة' : 'Unit'}</FormLabel><input name="unit" defaultValue="kg" className="min-h-11 w-full rounded-xl border bg-background px-3" /></FormField>
              <FormField><FormLabel>{locale === 'ar' ? 'حد الطلب' : 'Reorder level'}</FormLabel><input name="reorder_level" type="number" step="0.001" defaultValue="0" className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" /></FormField>
              <FormField><FormLabel>{locale === 'ar' ? 'تكلفة الوحدة الافتراضية' : 'Default unit cost'}</FormLabel><input name="default_unit_cost" type="number" step="0.001" defaultValue="0" className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" /></FormField>
              <FormField><FormLabel>{locale === 'ar' ? 'العملة' : 'Currency'}</FormLabel>
                <select name="currency" defaultValue="OMR" className="min-h-11 w-full rounded-xl border bg-background px-3">
                  {['OMR','EGP','USD','SAR','AED','EUR','GBP'].map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              </FormField>
              <FormField><FormLabel>SKU</FormLabel><input name="sku" className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" /></FormField>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="secondary" onClick={() => setDialog(null)}>{locale === 'ar' ? 'إلغاء' : 'Cancel'}</Button>
              <Button type="submit">{locale === 'ar' ? 'حفظ' : 'Save'}</Button>
            </div>
          </form>
        </div>
      )}

      {dialog && typeof dialog === 'object' && dialog.kind === 'movement' && (
        <div
          role="button"
          tabIndex={0}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 cursor-pointer"
          onClick={() => setDialog(null)}
          onKeyDown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') setDialog(null); }}
        >
          <form onSubmit={addMovement} onClick={(e) => e.stopPropagation()} className="w-full max-w-md space-y-3 rounded-2xl bg-card p-6 shadow-xl">
            <h3 className="font-semibold">
              {dialog.type === 'in'
                ? (locale === 'ar' ? 'وارد: ' : 'Stock in: ')
                : (locale === 'ar' ? 'منصرف: ' : 'Stock out: ')}
              {locale === 'ar' ? dialog.item.name_ar : (dialog.item.name_en ?? dialog.item.name_ar)}
            </h3>
            <FormField><FormLabel>{locale === 'ar' ? 'الكمية' : 'Quantity'} ({dialog.item.unit})</FormLabel>
              <input name="quantity" type="number" step="0.001" min="0" required autoFocus className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" />
            </FormField>
            <FormField><FormLabel>{locale === 'ar' ? 'تكلفة الوحدة' : 'Unit cost'}</FormLabel>
              <input name="unit_cost" type="number" step="0.001" defaultValue={dialog.item.default_unit_cost} className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" />
            </FormField>
            <FormField><FormLabel>{locale === 'ar' ? 'التاريخ' : 'Date'}</FormLabel>
              <input name="movement_date" type="date" defaultValue={new Date().toISOString().slice(0, 10)} className="min-h-11 w-full rounded-xl border bg-background px-3" />
            </FormField>
            <FormField><FormLabel>{locale === 'ar' ? 'ملاحظات' : 'Notes'}</FormLabel>
              <textarea name="notes" rows={2} className="w-full rounded-xl border bg-background px-3 py-2" />
            </FormField>
            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="secondary" onClick={() => setDialog(null)}>{locale === 'ar' ? 'إلغاء' : 'Cancel'}</Button>
              <Button type="submit">{locale === 'ar' ? 'تسجيل' : 'Record'}</Button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}

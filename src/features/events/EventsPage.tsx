import { useState, useMemo } from 'react';
import { Activity, Plus, Trash2, TrendingUp, TrendingDown, Syringe, Utensils, Heart, Skull } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { useOperationalEvents, computeAssetLiveQuantity, useStockAdjustments } from './hooks';
import { useAssets } from '../assets/hooks';
import { useProjects } from '../projects/hooks';
import { useI18n } from '../../core/i18n/context';
import type { OperationalEventType } from '../../core/types/domain';
import type { OperationalEventInput } from './storage';

const EVENT_META: Record<OperationalEventType, { label_ar: string; icon: any; color: string; delta: number; sector?: 'livestock' | 'agriculture' | 'both' }> = {
  birth:            { label_ar: 'ولادة',       icon: Heart,      color: 'text-success',    delta: 1,  sector: 'livestock' },
  death:            { label_ar: 'نفوق',        icon: Skull,      color: 'text-danger',     delta: -1, sector: 'livestock' },
  purchase:         { label_ar: 'شراء',        icon: TrendingUp, color: 'text-info',       delta: 1,  sector: 'both' },
  sale:             { label_ar: 'بيع',         icon: TrendingDown,color: 'text-warning',   delta: -1, sector: 'both' },
  vaccination:      { label_ar: 'تحصين',       icon: Syringe,    color: 'text-info',       delta: 0,  sector: 'livestock' },
  treatment:        { label_ar: 'علاج',        icon: Activity,   color: 'text-warning',    delta: 0,  sector: 'livestock' },
  feed_consumption: { label_ar: 'استهلاك علف', icon: Utensils,   color: 'text-muted-foreground', delta: 0, sector: 'livestock' },
  weighing:         { label_ar: 'وزن',         icon: Activity,   color: 'text-info',       delta: 0,  sector: 'livestock' },
  transfer:         { label_ar: 'نقل',         icon: Activity,   color: 'text-muted-foreground', delta: 0, sector: 'both' },
  planting:         { label_ar: 'زراعة',       icon: Activity,   color: 'text-success',    delta: 0,  sector: 'agriculture' },
  irrigation:       { label_ar: 'ري',          icon: Activity,   color: 'text-info',       delta: 0,  sector: 'agriculture' },
  fertilization:    { label_ar: 'تسميد',       icon: Activity,   color: 'text-warning',    delta: 0,  sector: 'agriculture' },
  pest_control:     { label_ar: 'مكافحة آفات', icon: Activity,   color: 'text-danger',     delta: 0,  sector: 'agriculture' },
  harvest:          { label_ar: 'حصاد',        icon: TrendingUp, color: 'text-success',    delta: 0,  sector: 'agriculture' },
  crop_loss:        { label_ar: 'فقد محصول',   icon: TrendingDown,color:'text-danger',    delta: 0,  sector: 'agriculture' },
};

export function EventsPage() {
  const { t } = useI18n();
  const { events, createEvent, removeEvent } = useOperationalEvents();
  const { assets } = useAssets();
  const { projects } = useProjects();
  const [showForm, setShowForm] = useState(false);
  const [filterSector, setFilterSector] = useState<'all' | 'livestock' | 'agriculture'>('all');

  const [form, setForm] = useState({
    asset_id: '',
    project_id: '',
    type: 'birth' as OperationalEventType,
    event_date: new Date().toISOString().slice(0, 10),
    quantity_delta: 1,
    weight_kg: '',
    description: '',
    create_transaction: false,
    total_cost_egp: '',
  });

  const operationalAssets = useMemo(() => 
    assets.filter(a => a.sector_id === 'livestock' || a.sector_id === 'agriculture'),
    [assets]
  );

  const filteredEvents = useMemo(() => {
    if (filterSector === 'all') return events;
    const sectorAssetIds = new Set(
      assets.filter(a => a.sector_id === filterSector).map(a => a.id)
    );
    return events.filter(e => sectorAssetIds.has(e.asset_id));
  }, [events, filterSector, assets]);

  // Live quantity preview per asset
  const assetLiveMap = useMemo(() => {
    const map = new Map<string, ReturnType<typeof computeAssetLiveQuantity>>();
    operationalAssets.forEach(asset => {
      const assetEvents = events.filter(e => e.asset_id === asset.id);
      // stock adjustments hook would be per-asset; simplified here
      map.set(asset.id, computeAssetLiveQuantity(asset.quantity ?? 0, assetEvents, []));
    });
    return map;
  }, [operationalAssets, events]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!form.asset_id || !form.project_id) return;

    const meta = EVENT_META[form.type];
    const input: OperationalEventInput = {
      asset_id: form.asset_id,
      project_id: form.project_id,
      type: form.type,
      event_date: form.event_date,
      quantity_delta: meta.delta !== 0 ? (form.quantity_delta || meta.delta) : undefined,
      weight_kg: form.weight_kg ? Number(form.weight_kg) : undefined,
      description: form.description || undefined,
      total_cost_egp: form.total_cost_egp ? Number(form.total_cost_egp) : undefined,
    };

    createEvent(input);

    // Reset
    setForm(f => ({
      ...f,
      quantity_delta: 1,
      weight_kg: '',
      description: '',
      total_cost_egp: '',
      create_transaction: false,
    }));
    setShowForm(false);
  }

  const selectedAsset = operationalAssets.find(a => a.id === form.asset_id);
  const assetProjects = selectedAsset 
    ? projects.filter(p => p.id === selectedAsset.project_id || p.sector_id === selectedAsset.sector_id)
    : projects;

  return (
    <div className="space-y-6">
      <PageHeader
        title={t('events_title')}
        description={t('events_description')}
      >
        <Button onClick={() => setShowForm(!showForm)}>
          <Plus className="h-4 w-4" />
          {showForm ? t('action_close') : t('events_new')}
        </Button>
      </PageHeader>

      {/* Live asset balances */}
      {operationalAssets.length > 0 && (
        <div>
          <h3 className="mb-3 font-semibold text-sm">{t('events_live_balances')}</h3>
          <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {operationalAssets.slice(0, 8).map(asset => {
              const live = assetLiveMap.get(asset.id);
              const baseQty = asset.quantity ?? 0;
              const diff = (live?.quantity ?? 0) - baseQty;
              return (
                <Card key={asset.id}>
                  <CardContent className="p-3">
                    <p className="text-xs text-muted-foreground truncate">{asset.name_ar}</p>
                    <p className="text-lg font-bold">
                      {live?.quantity ?? baseQty}
                      <span className="text-xs font-normal text-muted-foreground mr-1">{asset.unit ?? 'رأس'}</span>
                    </p>
                    {diff !== 0 && (
                      <p className={`text-[11px] ${diff > 0 ? 'text-success' : 'text-danger'}`}>
                        {diff > 0 ? '+' : ''}{diff} {t('events_from_events')}
                      </p>
                    )}
                    {live?.lastEventDate && (
                      <p className="text-[10px] text-muted-foreground mt-1">آخر حدث: {live.lastEventDate}</p>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </div>
      )}

      {/* Event form */}
      {showForm && (
        <Card>
          <CardHeader>
            <h3 className="font-semibold">{t('events_new_title')}</h3>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="grid gap-4 sm:grid-cols-2">
              <label className="space-y-1 text-sm">
                <span>{t('asset_name_ar')} *</span>
                <select
                  required
                  value={form.asset_id}
                  onChange={e => {
                    const assetId = e.target.value;
                    const asset = operationalAssets.find(a => a.id === assetId);
                    setForm(f => ({
                      ...f,
                      asset_id: assetId,
                      project_id: asset?.project_id ?? f.project_id,
                    }));
                  }}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2"
                >
                  <option value="">{t('events_choose_asset')}</option>
                  {operationalAssets.map(a => (
                    <option key={a.id} value={a.id}>
                      {a.name_ar} — {a.sector_id === 'livestock' ? 'حيواني' : 'زراعي'}
                    </option>
                  ))}
                </select>
              </label>

              <label className="space-y-1 text-sm">
                <span>{t('project_name_ar')} *</span>
                <select
                  required
                  value={form.project_id}
                  onChange={e => setForm(f => ({ ...f, project_id: e.target.value }))}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2"
                >
                  <option value="">{t('events_choose_project')}</option>
                  {assetProjects.map(p => (
                    <option key={p.id} value={p.id}>{p.name_ar}</option>
                  ))}
                </select>
              </label>

              <label className="space-y-1 text-sm">
                <span>{t('events_type')} *</span>
                <select
                  value={form.type}
                  onChange={e => setForm(f => ({ ...f, type: e.target.value as OperationalEventType }))}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2"
                >
                  {Object.entries(EVENT_META).map(([key, meta]) => (
                    <option key={key} value={key}>{meta.label_ar}</option>
                  ))}
                </select>
              </label>

              <label className="space-y-1 text-sm">
                <span>{t('transaction_date')} *</span>
                <input
                  type="date"
                  required
                  value={form.event_date}
                  onChange={e => setForm(f => ({ ...f, event_date: e.target.value }))}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2"
                />
              </label>

              {EVENT_META[form.type].delta !== 0 && (
                <label className="space-y-1 text-sm">
                  <span>{t('asset_quantity')} (Δ)</span>
                  <input
                    type="number"
                    value={form.quantity_delta}
                    onChange={e => setForm(f => ({ ...f, quantity_delta: Number(e.target.value) || 0 }))}
                    className="w-full rounded-xl border border-border bg-background px-3 py-2 ltr"
                    dir="ltr"
                  />
                  <span className="text-[11px] text-muted-foreground">
                    افتراضي: {EVENT_META[form.type].delta > 0 ? '+' : ''}{EVENT_META[form.type].delta}
                  </span>
                </label>
              )}

              <label className="space-y-1 text-sm">
                <span>{t('events_weight_kg')}</span>
                <input
                  type="number"
                  step="0.1"
                  value={form.weight_kg}
                  onChange={e => setForm(f => ({ ...f, weight_kg: e.target.value }))}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2 ltr"
                  dir="ltr"
                  placeholder="اختياري"
                />
              </label>

              <label className="space-y-1 text-sm sm:col-span-2">
                <span>{t('events_cost_egp')}</span>
                <input
                  type="number"
                  step="0.01"
                  value={form.total_cost_egp}
                  onChange={e => setForm(f => ({ ...f, total_cost_egp: e.target.value }))}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2 ltr"
                  dir="ltr"
                  placeholder="0"
                />
              </label>

              <label className="space-y-1 text-sm sm:col-span-2">
                <span>{t('transaction_notes')}</span>
                <textarea
                  value={form.description}
                  onChange={e => setForm(f => ({ ...f, description: e.target.value }))}
                  rows={2}
                  className="w-full rounded-xl border border-border bg-background px-3 py-2"
                  placeholder="ملاحظات اختيارية…"
                />
              </label>

              <div className="sm:col-span-2 flex gap-3 pt-2">
                <Button type="submit">{t('action_save')}</Button>
                <button
                  type="button"
                  onClick={() => setShowForm(false)}
                  className="rounded-xl border border-border px-4 py-2 text-sm hover:bg-muted"
                >
                  {t('action_cancel')}
                </button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {/* Filters */}
      <div className="flex gap-2 text-xs">
        {(['all','livestock','agriculture'] as const).map(s => (
          <button
            key={s}
            onClick={() => setFilterSector(s)}
            className={`rounded-full px-3 py-1.5 border transition ${
              filterSector === s 
                ? 'bg-primary text-primary-foreground border-primary' 
                : 'border-border hover:bg-muted'
            }`}
          >
            {s === 'all' ? 'الكل' : s === 'livestock' ? 'حيواني' : 'زراعي'} 
            {s !== 'all' && ` (${filteredEvents.filter(ev => {
              const asset = assets.find(a => a.id === ev.asset_id);
              return asset?.sector_id === s;
            }).length})`}
          </button>
        ))}
        <span className="mr-auto text-muted-foreground self-center">
          {filteredEvents.length} {t('events_count')}
        </span>
      </div>

      {/* Events list */}
      <Card>
        <CardContent className="p-0">
          {filteredEvents.length === 0 ? (
            <div className="py-10">
              <EmptyState 
                title={t('state_empty_title')} 
                description="سجّل أول حدث تشغيلي — ولادة، نفوق، تحصين، حصاد…" 
              />
            </div>
          ) : (
            <div className="divide-y divide-border">
              {filteredEvents.map(ev => {
                const meta = EVENT_META[ev.type] ?? EVENT_META.treatment;
                const Icon = meta.icon;
                const asset = assets.find(a => a.id === ev.asset_id);
                const project = projects.find(p => p.id === ev.project_id);
                return (
                  <div key={ev.id} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/40">
                    <div className={`p-2 rounded-lg bg-muted ${meta.color}`}>
                      <Icon className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium">
                        {meta.label_ar}
                        {ev.quantity_delta ? (
                          <span className={`mr-2 text-xs ${ev.quantity_delta > 0 ? 'text-success' : 'text-danger'}`}>
                            {ev.quantity_delta > 0 ? '+' : ''}{ev.quantity_delta}
                          </span>
                        ) : null}
                      </p>
                      <p className="text-xs text-muted-foreground truncate">
                        {asset?.name_ar ?? ev.asset_id} • {project?.name_ar ?? ''}
                        {ev.weight_kg ? ` • ${ev.weight_kg} كجم` : ''}
                        {ev.total_cost_egp ? ` • ${ev.total_cost_egp} EGP` : ''}
                      </p>
                      {ev.description && (
                        <p className="text-[11px] text-muted-foreground truncate">{ev.description}</p>
                      )}
                    </div>
                    <div className="text-left">
                      <p className="text-xs text-muted-foreground">{ev.event_date}</p>
                      <Badge tone="neutral">{ev.type}</Badge>
                    </div>
                    <button
                      onClick={() => {
                        if (confirm('حذف هذا الحدث؟')) removeEvent(ev.id);
                      }}
                      className="p-2 text-muted-foreground hover:text-danger rounded-lg hover:bg-danger/5"
                      title="حذف"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      <div className="text-[11px] text-muted-foreground text-center">
        ADR-003 — Event Sourcing track • الكمية الحية = الرصيد الأساسي + Σ quantity_delta + التعديلات
      </div>
    </div>
  );
}

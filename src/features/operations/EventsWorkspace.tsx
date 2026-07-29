import { CalendarDays, FileText, Pencil, Plus, ReceiptText } from 'lucide-react';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import type { Asset, OperationalEvent, OperationalEventType, Project } from '../../core/types/domain';
import { EVENT_DEFINITIONS, filterOperationalEvents, type EventFilters, type OperationsContext } from './model';

interface EventsWorkspaceProps {
  events: OperationalEvent[];
  assets: Asset[];
  projects: Project[];
  context: OperationsContext;
  filters: EventFilters;
  locale: 'ar' | 'en';
  onFiltersChange: (filters: EventFilters) => void;
  onCreate: () => void;
  onEdit: (event: OperationalEvent) => void;
  onInspect: (event: OperationalEvent) => void;
}

export function EventsWorkspace({
  events,
  assets,
  projects,
  context,
  filters,
  locale,
  onFiltersChange,
  onCreate,
  onEdit,
  onInspect,
}: EventsWorkspaceProps) {
  const filtered = filterOperationalEvents(events, assets, filters);
  const assetById = new Map(assets.map((asset) => [asset.id, asset]));
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const realEstateOnly = context.sector === 'real-estate'
    || Boolean(context.assetId && assetById.get(context.assetId)?.sector_id === 'real-estate');

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="font-bold">{locale === 'ar' ? 'سجل الأحداث' : 'Events timeline'}</h2>
            <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'قائمة موحدة حسب السياق، وليست صفحة لكل نوع.' : 'One contextual timeline, not a page per event type.'}</p>
          </div>
          {!realEstateOnly && (
            <Button type="button" onClick={onCreate} className="min-h-11">
              <Plus className="h-4 w-4" />
              {locale === 'ar' ? 'حدث جديد' : 'New event'}
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {realEstateOnly && (
          <div className="rounded-2xl border border-info/30 bg-info/5 p-4 text-sm">
            {locale === 'ar'
              ? 'لا يعرّف النموذج الحالي أحداثًا عقارية. استخدم عرض القطاع للمعاملات والمستندات بدل اختراع حدث جديد.'
              : 'The current domain has no real-estate events. Use the sector view for transactions and documents.'}
          </div>
        )}
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label className="text-xs font-semibold">
            <span className="mb-1 block">{locale === 'ar' ? 'نوع الحدث' : 'Event type'}</span>
            <select value={filters.type ?? 'all'} onChange={(event) => onFiltersChange({ ...filters, type: event.target.value as OperationalEventType | 'all' })} className="min-h-11 w-full rounded-xl border bg-background px-3">
              <option value="all">{locale === 'ar' ? 'كل الأنواع' : 'All types'}</option>
              {(Object.keys(EVENT_DEFINITIONS) as OperationalEventType[]).map((type) => (
                <option key={type} value={type}>{EVENT_DEFINITIONS[type][locale]}</option>
              ))}
            </select>
          </label>
          <label className="text-xs font-semibold">
            <span className="mb-1 block">{locale === 'ar' ? 'من' : 'From'}</span>
            <input type="date" value={filters.dateFrom ?? ''} onChange={(event) => onFiltersChange({ ...filters, dateFrom: event.target.value || undefined })} className="min-h-11 w-full rounded-xl border bg-background px-3" />
          </label>
          <label className="text-xs font-semibold">
            <span className="mb-1 block">{locale === 'ar' ? 'إلى' : 'To'}</span>
            <input type="date" value={filters.dateTo ?? ''} onChange={(event) => onFiltersChange({ ...filters, dateTo: event.target.value || undefined })} className="min-h-11 w-full rounded-xl border bg-background px-3" />
          </label>
          <div className="flex items-end">
            <Button type="button" variant="secondary" className="min-h-11 w-full" onClick={() => onFiltersChange({ ...context, type: 'all' })}>
              {locale === 'ar' ? 'مسح الفلاتر' : 'Clear filters'}
            </Button>
          </div>
        </div>
        {!filtered.length ? (
          <EmptyState
            title={locale === 'ar' ? 'لا توجد أحداث في هذا السياق' : 'No events in this context'}
            description={locale === 'ar' ? 'غيّر الفلاتر أو أنشئ حدثًا من أصل زراعي أو حيواني.' : 'Change filters or create an event from an agriculture or livestock asset.'}
            icon={CalendarDays}
          />
        ) : (
          <div className="space-y-3">
            {filtered.map((event) => {
              const asset = assetById.get(event.asset_id);
              const project = projectById.get(event.project_id);
              return (
                <article key={event.id} className="rounded-2xl border p-4">
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <button type="button" onClick={() => onInspect(event)} className="min-h-11 flex-1 text-start">
                      <div className="flex flex-wrap items-center gap-2">
                        <strong>{EVENT_DEFINITIONS[event.type][locale]}</strong>
                        <Badge tone="neutral">{event.event_date}</Badge>
                        {event.quantity_delta != null && (
                          <Badge tone={event.quantity_delta >= 0 ? 'positive' : 'warning'}>
                            {event.quantity_delta > 0 ? '+' : ''}{event.quantity_delta}
                          </Badge>
                        )}
                      </div>
                      <p className="mt-1 text-sm text-muted-foreground">
                        {asset ? (locale === 'ar' ? asset.name_ar : asset.name_en) : event.asset_id}
                        {' · '}
                        {project ? (locale === 'ar' ? project.name_ar : project.name_en) : event.project_id}
                      </p>
                      {event.description && <p className="mt-2 text-sm">{event.description}</p>}
                      <div className="mt-2 flex gap-3 text-xs text-muted-foreground">
                        {event.document_id && <span className="inline-flex items-center gap-1"><FileText className="h-3.5 w-3.5" />{locale === 'ar' ? 'مستند' : 'Document'}</span>}
                        {event.linked_transaction_id && <span className="inline-flex items-center gap-1"><ReceiptText className="h-3.5 w-3.5" />{locale === 'ar' ? 'معاملة' : 'Transaction'}</span>}
                      </div>
                    </button>
                    <Button type="button" variant="secondary" size="sm" onClick={() => onEdit(event)} className="min-h-11">
                      <Pencil className="h-4 w-4" />
                      {locale === 'ar' ? 'تعديل' : 'Edit'}
                    </Button>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

import { useEffect, useMemo, useRef, useState } from 'react';
import { Activity, Boxes, Gauge, LayoutDashboard, Plus, ReceiptText, FileText, Pencil } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { EntityInspectorDrawer } from '../../components/ui/EntityInspectorDrawer';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { WorkspaceShell, useWorkspaceUrlState } from '../../components/workspace';
import { useI18n } from '../../core/i18n/context';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import type { Asset, OperationalEvent } from '../../core/types/domain';
import { computeAssetLiveQuantity } from '../events/hooks';
import {
  operationalEventsStore,
  type OperationalEventInput,
  type StockAdjustmentInput,
} from '../events/storage';
import { recordStockAdjustmentAtomic } from '../events/stockAdjustmentWorkflow';
import { AssetBalancesWorkspace } from './AssetBalancesWorkspace';
import type { OperationsHandoff } from './contracts';
import { EventForm } from './EventForm';
import { EventsWorkspace } from './EventsWorkspace';
import { computeOperationsOverview, EVENT_DEFINITIONS, type EventFilters } from './model';
import { OperationsContextBar } from './OperationsContextBar';
import { OperationsOverview } from './OperationsOverview';
import { SectorWorkspace } from './SectorWorkspace';
import { StockAdjustmentForm } from './StockAdjustmentForm';
import { useOperationsContext } from './useOperationsContext';
import { useOperationsData } from './useOperationsData';

const workspaceIds = ['overview', 'events', 'balances', 'sector'] as const;
type WorkspaceId = typeof workspaceIds[number];
type Surface =
  | { kind: 'event'; event?: OperationalEvent }
  | { kind: 'adjustment'; asset: Asset }
  | null;

interface OperationsHubProps {
  onHandoff?: (handoff: OperationsHandoff) => void;
}

export function OperationsHub({ onHandoff }: OperationsHubProps) {
  const { locale } = useI18n();
  const { data, status, error: loadError, retry } = useOperationsData();
  const [activeWorkspace, setActiveWorkspace] = useWorkspaceUrlState(
    workspaceIds,
    'overview',
    { parameter: 'workspace', replace: true },
  );
  const [context, setContext] = useOperationsContext(data.projects, data.assets);
  const [filters, setFilters] = useState<EventFilters>({ ...context, type: 'all' });
  const [surface, setSurface] = useState<Surface>(null);
  const [inspectedEvent, setInspectedEvent] = useState<OperationalEvent | null>(null);
  const [pending, setPending] = useState(false);
  const [writeError, setWriteError] = useState<string | null>(null);
  const [adjustmentDraft, setAdjustmentDraft] = useState<StockAdjustmentInput | null>(null);
  const initialIntentHandled = useRef(false);

  useEffect(() => {
    setFilters((current) => ({ ...current, ...context }));
  }, [context]);

  const overview = useMemo(
    () => computeOperationsOverview(
      data.projects,
      data.assets,
      data.events,
      data.adjustments,
      data.documents,
      data.transactions,
      context.sector,
    ),
    [context.sector, data],
  );
  const assetById = new Map(data.assets.map((asset) => [asset.id, asset]));
  const projectById = new Map(data.projects.map((project) => [project.id, project]));
  const documentById = new Map(data.documents.map((document) => [document.id, document]));
  const linkedTransaction = inspectedEvent
    ? data.transactions.find((transaction) =>
      transaction.id === inspectedEvent.linked_transaction_id
      || transaction.operational_event_id === inspectedEvent.id,
    )
    : undefined;
  const inspectedAsset = inspectedEvent ? assetById.get(inspectedEvent.asset_id) : undefined;
  const inspectedProject = inspectedEvent ? projectById.get(inspectedEvent.project_id) : undefined;
  const inspectedDocument = inspectedEvent?.document_id ? documentById.get(inspectedEvent.document_id) : undefined;

  useEffect(() => {
    if (status !== 'ready' || initialIntentHandled.current) return;
    initialIntentHandled.current = true;
    const search = new URL(window.location.href).searchParams;
    const inspectId = search.get('inspect') ?? search.get('event');
    const intent = search.get('intent');
    const inspected = data.events.find((item) => item.id === inspectId);
    if (inspected) {
      setActiveWorkspace('events');
      setInspectedEvent(inspected);
    }
    if (intent === 'create-event' && context.assetId) {
      setActiveWorkspace('events');
      setSurface({ kind: 'event' });
    }
  }, [context.assetId, data.events, setActiveWorkspace, status]);

  const labels = locale === 'ar'
    ? {
        title: 'مركز العمليات',
        description: 'سياق واحد للمشروع والأصل، مع أحداث وأرصدة وتركيب قطاعي من البيانات الفعلية.',
        overview: 'نظرة عامة',
        events: 'الأحداث',
        balances: 'الأرصدة والتصحيحات',
        sector: 'عرض القطاع',
      }
    : {
        title: 'Operations Hub',
        description: 'One project and asset context for real events, balances, and sector composition.',
        overview: 'Overview',
        events: 'Events',
        balances: 'Balances',
        sector: 'Sector view',
      };

  const workspaces = [
    { id: 'overview', label: labels.overview, icon: LayoutDashboard },
    { id: 'events', label: labels.events, icon: Activity },
    { id: 'balances', label: labels.balances, icon: Gauge },
    { id: 'sector', label: labels.sector, icon: Boxes },
  ];

  async function saveEvent(input: OperationalEventInput, existing?: OperationalEvent) {
    setPending(true);
    setWriteError(null);
    try {
      if (existing) operationalEventsStore.update(existing.id, input);
      else operationalEventsStore.create(input);
      await operationalEventsStore.flush();
      setSurface(null);
      if (existing) setInspectedEvent({ ...existing, ...input });
    } catch (error) {
      setWriteError(translateServerError(error));
    } finally {
      setPending(false);
    }
  }

  async function confirmAdjustment() {
    if (!adjustmentDraft) return;
    setPending(true);
    setWriteError(null);
    try {
      await recordStockAdjustmentAtomic(adjustmentDraft);
      setAdjustmentDraft(null);
      setSurface(null);
    } catch (error) {
      setWriteError(translateServerError(error));
      const asset = assetById.get(adjustmentDraft.asset_id);
      setAdjustmentDraft(null);
      if (asset) setSurface({ kind: 'adjustment', asset });
    } finally {
      setPending(false);
    }
  }

  const state = status === 'loading' ? 'loading' : status === 'error' ? 'error' : 'ready';

  return (
    <>
      <WorkspaceShell
        title={labels.title}
        description={labels.description}
        workspaces={workspaces}
        activeWorkspace={activeWorkspace}
        onWorkspaceChange={(workspace) => setActiveWorkspace(workspace as WorkspaceId)}
        switcherLabel={locale === 'ar' ? 'مساحات عمل العمليات' : 'Operations workspaces'}
        loadingLabel={locale === 'ar' ? 'جار تحميل العمليات' : 'Loading operations'}
        state={state}
        errorState={{
          title: locale === 'ar' ? 'تعذر تحميل العمليات' : 'Operations could not load',
          description: loadError ?? '',
          onRetry: () => void retry(),
        }}
        actions={
          context.sector !== 'real-estate' && (
            <Button type="button" onClick={() => setSurface({ kind: 'event' })}>
              <Plus className="h-4 w-4" />
              {locale === 'ar' ? 'حدث جديد' : 'New event'}
            </Button>
          )
        }
        summaries={
          <OperationsContextBar
            context={context}
            projects={data.projects}
            assets={data.assets}
            locale={locale}
            onChange={setContext}
          />
        }
      >
        {activeWorkspace === 'overview' && (
          <OperationsOverview
            overview={overview}
            locale={locale}
            assetName={(id) => {
              const asset = assetById.get(id);
              return asset ? (locale === 'ar' ? asset.name_ar : asset.name_en) : id;
            }}
            onInspectEvent={(id) => setInspectedEvent(data.events.find((event) => event.id === id) ?? null)}
          />
        )}
        {activeWorkspace === 'events' && (
          <EventsWorkspace
            events={data.events}
            assets={data.assets}
            projects={data.projects}
            context={context}
            filters={filters}
            locale={locale}
            onFiltersChange={setFilters}
            onCreate={() => setSurface({ kind: 'event' })}
            onEdit={(event) => setSurface({ kind: 'event', event })}
            onInspect={setInspectedEvent}
          />
        )}
        {activeWorkspace === 'balances' && (
          <AssetBalancesWorkspace
            assets={data.assets}
            events={data.events}
            adjustments={data.adjustments}
            context={context}
            locale={locale}
            onAdjust={(asset) => {
              setWriteError(null);
              setSurface({ kind: 'adjustment', asset });
            }}
          />
        )}
        {activeWorkspace === 'sector' && (
          <SectorWorkspace
            {...data}
            context={context}
            locale={locale}
            onContextChange={setContext}
            onHandoff={onHandoff}
          />
        )}
      </WorkspaceShell>

      <AdaptiveFormSurface
        open={surface?.kind === 'event'}
        onOpenChange={(open) => {
          if (!open) {
            setSurface(null);
            setWriteError(null);
          }
        }}
        title={surface?.kind === 'event' && surface.event
          ? (locale === 'ar' ? 'تعديل الحدث' : 'Edit event')
          : (locale === 'ar' ? 'حدث سياقي جديد' : 'New contextual event')}
        description={locale === 'ar' ? 'الحقول تتبع نوع الحدث وقطاع الأصل.' : 'Fields follow the event type and asset sector.'}
        mode={surface?.kind === 'event' && surface.event ? 'edit' : 'create'}
        pending={pending}
        submitLabel={locale === 'ar' ? 'حفظ الحدث' : 'Save event'}
        cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'}
        closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'}
        formId="operations-event-form"
      >
        {surface?.kind === 'event' && (
          <EventForm
            key={surface.event?.id ?? `${context.projectId}-${context.assetId}`}
            formId="operations-event-form"
            locale={locale}
            projects={data.projects}
            assets={data.assets}
            documents={data.documents}
            context={context}
            initial={surface.event}
            serverError={writeError}
            onSubmit={(input) => saveEvent(input, surface.event)}
          />
        )}
      </AdaptiveFormSurface>

      <AdaptiveFormSurface
        open={surface?.kind === 'adjustment'}
        onOpenChange={(open) => {
          if (!open) {
            setSurface(null);
            setWriteError(null);
          }
        }}
        title={locale === 'ar' ? 'تصحيح رصيد محكوم' : 'Guarded stock adjustment'}
        description={locale === 'ar' ? 'يظل الحدث التاريخي كما هو، ويضاف سجل تصحيح مستقل.' : 'Event history remains intact and a separate adjustment is added.'}
        pending={pending}
        submitLabel={locale === 'ar' ? 'مراجعة الأثر' : 'Review impact'}
        cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'}
        closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'}
        formId="operations-adjustment-form"
      >
        {surface?.kind === 'adjustment' && (
          <StockAdjustmentForm
            key={surface.asset.id}
            formId="operations-adjustment-form"
            asset={surface.asset}
            currentQuantity={computeAssetLiveQuantity(
              surface.asset.quantity ?? 0,
              data.events.filter((event) => event.asset_id === surface.asset.id),
              data.adjustments.filter((adjustment) => adjustment.asset_id === surface.asset.id),
            ).quantity}
            locale={locale}
            serverError={writeError}
            onReview={(draft) => {
              setAdjustmentDraft(draft);
              setSurface(null);
            }}
          />
        )}
      </AdaptiveFormSurface>

      <ConfirmDialog
        open={Boolean(adjustmentDraft)}
        onOpenChange={(open) => {
          if (!open && adjustmentDraft) {
            const asset = assetById.get(adjustmentDraft.asset_id);
            setAdjustmentDraft(null);
            if (asset) setSurface({ kind: 'adjustment', asset });
          }
        }}
        title={locale === 'ar' ? 'تأكيد أثر التصحيح' : 'Confirm adjustment impact'}
        entityName={assetById.get(adjustmentDraft?.asset_id ?? '')?.name_ar ?? ''}
        impact={adjustmentDraft
          ? `${locale === 'ar' ? 'الكمية' : 'Quantity'}: ${adjustmentDraft.quantity_before} → ${adjustmentDraft.quantity_after} · ${locale === 'ar' ? 'القيمة' : 'Value'}: ${adjustmentDraft.value_egp_before.toLocaleString()} → ${adjustmentDraft.value_egp_after.toLocaleString()} EGP · ${adjustmentDraft.reason}`
          : ''}
        confirmLabel={locale === 'ar' ? 'تسجيل التصحيح' : 'Record adjustment'}
        cancelLabel={locale === 'ar' ? 'العودة' : 'Go back'}
        destructive={false}
        pending={pending}
        onConfirm={confirmAdjustment}
      />

      <EntityInspectorDrawer
        open={Boolean(inspectedEvent)}
        onOpenChange={(open) => {
          if (!open) setInspectedEvent(null);
        }}
        title={inspectedEvent ? EVENT_DEFINITIONS[inspectedEvent.type][locale] : ''}
        description={inspectedEvent?.event_date}
        closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'}
        relationshipsLabel={locale === 'ar' ? 'العلاقات' : 'Relationships'}
        activityLabel={locale === 'ar' ? 'الأثر' : 'Impact'}
        summary={inspectedEvent && (
          <dl className="grid grid-cols-2 gap-3 text-sm">
            <InspectorValue label={locale === 'ar' ? 'المشروع' : 'Project'} value={inspectedProject ? (locale === 'ar' ? inspectedProject.name_ar : inspectedProject.name_en) : '—'} />
            <InspectorValue label={locale === 'ar' ? 'الأصل' : 'Asset'} value={inspectedAsset ? (locale === 'ar' ? inspectedAsset.name_ar : inspectedAsset.name_en) : '—'} />
            <InspectorValue label={locale === 'ar' ? 'تغير الكمية' : 'Quantity delta'} value={inspectedEvent.quantity_delta == null ? '—' : String(inspectedEvent.quantity_delta)} />
            <InspectorValue label={locale === 'ar' ? 'التكلفة' : 'Cost'} value={inspectedEvent.total_cost_egp == null ? '—' : `${inspectedEvent.total_cost_egp.toLocaleString()} EGP`} />
          </dl>
        )}
        relationships={inspectedEvent && (
          <div className="space-y-2 text-sm">
            <p className="flex items-center gap-2"><FileText className="h-4 w-4" />{inspectedDocument ? (locale === 'ar' ? inspectedDocument.title_ar : inspectedDocument.title_en ?? inspectedDocument.title_ar) : (locale === 'ar' ? 'لا يوجد مستند' : 'No document')}</p>
            <p className="flex items-center gap-2"><ReceiptText className="h-4 w-4" />{linkedTransaction ? `${linkedTransaction.category} · ${linkedTransaction.amount_egp.toLocaleString()} EGP` : (locale === 'ar' ? 'لا توجد معاملة مرتبطة' : 'No linked transaction')}</p>
          </div>
        )}
        activity={inspectedEvent?.description ? <p className="text-sm">{inspectedEvent.description}</p> : <p className="text-sm text-muted-foreground">—</p>}
        actions={inspectedEvent && (
          <>
            <Button type="button" variant="secondary" onClick={() => setSurface({ kind: 'event', event: inspectedEvent })}>
              <Pencil className="h-4 w-4" />{locale === 'ar' ? 'تعديل' : 'Edit'}
            </Button>
            {onHandoff && inspectedAsset && (
              <>
                <Button type="button" variant="secondary" onClick={() => onHandoff({
                  destination: 'finance',
                  intent: 'create-or-link-transaction',
                  projectId: inspectedEvent.project_id,
                  assetId: inspectedEvent.asset_id,
                  eventId: inspectedEvent.id,
                  eventType: inspectedEvent.type,
                  amountEgp: inspectedEvent.total_cost_egp,
                })}>
                  <ReceiptText className="h-4 w-4" />{locale === 'ar' ? 'إنشاء/ربط معاملة' : 'Create/link transaction'}
                </Button>
                <Button type="button" variant="secondary" onClick={() => onHandoff({
                  destination: 'governance',
                  intent: 'attach-document',
                  projectId: inspectedEvent.project_id,
                  assetId: inspectedEvent.asset_id,
                  eventId: inspectedEvent.id,
                })}>
                  <FileText className="h-4 w-4" />{locale === 'ar' ? 'إرفاق مستند' : 'Attach document'}
                </Button>
              </>
            )}
          </>
        )}
      />

      {writeError && !surface && !adjustmentDraft && (
        <FormErrorSummary
          serverError={writeError}
          title={locale === 'ar' ? 'فشل حفظ التغيير' : 'Change could not be saved'}
        />
      )}
    </>
  );
}

function InspectorValue({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl border p-3"><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 font-semibold">{value}</dd></div>;
}

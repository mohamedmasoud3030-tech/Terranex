import { useEffect, useMemo, useRef, useState } from 'react';
import { CircleDollarSign, FileText, HandCoins, LayoutDashboard, ListChecks, ReceiptText } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { EntityInspectorDrawer } from '../../components/ui/EntityInspectorDrawer';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { WorkspaceShell, useWorkspaceUrlState } from '../../components/workspace';
import { useI18n } from '../../core/i18n/context';
import type { Obligation, Transaction } from '../../core/types/domain';
import { ObligationForm } from '../obligations/ObligationForm';
import { obligationsStore, type ObligationInput } from '../obligations/storage';
import { reverseSettlement } from '../settlements/posting';
import { recordSettlementWithAllocations, type RecordSettlementWithAllocationsInput } from '../settlements/workflow';
import type { Settlement } from '../settlements/types';
import { TransactionForm } from '../transactions/TransactionForm';
import { createTransactionWithOptionalPayable, updateTransactionWithLinkedPayable, type DeferredExpenseTransactionInput } from '../transactions/deferredExpenseWorkflow';
import type { FinanceHandoff } from './contracts';
import { executeFinanceWrite, FINANCE_ATOMICITY_NOTICE } from './financeWriteBoundary';
import { FinanceOverviewView, ObligationsWorkspace, SettlementsWorkspace, TransactionsWorkspace } from './FinanceWorkspaces';
import { computeFinanceOverview, filterObligations, filterTransactions, type ObligationFilters, type TransactionFilters } from './hubModel';
import { SettlementFlowForm } from './SettlementFlowForm';
import { useFinanceContext } from './useFinanceContext';
import { useFinanceData } from './useFinanceData';

const workspaceIds = ['overview', 'transactions', 'obligations', 'settlements'] as const;
type Surface =
  | { kind: 'transaction'; item?: Transaction }
  | { kind: 'obligation'; item?: Obligation }
  | { kind: 'settlement'; anchorId?: string }
  | null;
type Inspected = { kind: 'transaction'; item: Transaction } | { kind: 'obligation'; item: Obligation } | null;

export function FinanceHub({ onHandoff }: { onHandoff?: (handoff: FinanceHandoff) => void }) {
  const { locale } = useI18n();
  const { data, status, error: loadError, retry } = useFinanceData();
  const [context, setContext] = useFinanceContext(data.projects, data.assets, data.partners, data.events, data.obligations);
  const [workspace, setWorkspace] = useWorkspaceUrlState(workspaceIds, 'overview', { parameter: 'workspace' });
  const today = new Date().toISOString().slice(0, 10);
  const [transactionFilters, setTransactionFilters] = useState<TransactionFilters>(context);
  const [obligationFilters, setObligationFilters] = useState<ObligationFilters>({ ...context, asOf: today, aging: 'all' });
  const [surface, setSurface] = useState<Surface>(null);
  const [inspected, setInspected] = useState<Inspected>(null);
  const [pending, setPending] = useState(false);
  const [writeError, setWriteError] = useState<string | null>(null);
  const [reverseTarget, setReverseTarget] = useState<Settlement | null>(null);
  const [reverseReason, setReverseReason] = useState('');
  const initialIntentHandled = useRef(false);

  useEffect(() => {
    setTransactionFilters((current) => ({ ...current, ...context }));
    setObligationFilters((current) => ({ ...current, ...context }));
  }, [context]);

  const overview = useMemo(
    () => computeFinanceOverview(data.projects, data.transactions, data.obligations, today),
    [data.obligations, data.projects, data.transactions, today],
  );
  const filteredTransactions = filterTransactions(data.transactions, transactionFilters);
  const filteredObligations = filterObligations(data.obligations, obligationFilters);
  const projectById = new Map(data.projects.map((item) => [item.id, item]));
  const assetById = new Map(data.assets.map((item) => [item.id, item]));
  const partnerById = new Map(data.partners.map((item) => [item.id, item]));
  const documentById = new Map(data.documents.map((item) => [item.id, item]));
  const eventById = new Map(data.events.map((item) => [item.id, item]));

  const workspaces = [
    { id: 'overview', label: locale === 'ar' ? 'نظرة مالية' : 'Finance overview', icon: LayoutDashboard },
    { id: 'transactions', label: locale === 'ar' ? 'المعاملات' : 'Transactions', icon: ReceiptText },
    { id: 'obligations', label: locale === 'ar' ? 'الذمم' : 'Obligations', icon: ListChecks },
    { id: 'settlements', label: locale === 'ar' ? 'التسويات' : 'Settlements', icon: HandCoins },
  ];

  function beginTransaction(item?: Transaction) {
    if (!item && !context.projectId) {
      setWriteError(locale === 'ar' ? 'اختر مشروعًا من سياق Finance قبل إنشاء المعاملة.' : 'Choose a project context before creating a transaction.');
      return;
    }
    setWriteError(null);
    setSurface({ kind: 'transaction', item });
  }

  useEffect(() => {
    if (status !== 'ready' || initialIntentHandled.current) return;
    initialIntentHandled.current = true;
    const search = new URL(window.location.href).searchParams;
    const intent = search.get('intent');
    const obligationId = search.get('obligation');
    if ((intent === 'create-transaction' || intent === 'create-or-link-transaction') && context.projectId) {
      setWorkspace('transactions');
      beginTransaction();
    } else if (obligationId && search.get('workspace') === 'settlements') {
      setSurface({ kind: 'settlement', anchorId: obligationId });
    }
  }, [context.projectId, setWorkspace, status]);

  async function runWrite<T>(operation: () => T, onSuccess: (result: T) => void) {
    setPending(true);
    setWriteError(null);
    try {
      const result = await executeFinanceWrite(operation);
      onSuccess(result);
    } catch (error) {
      setWriteError(error instanceof Error ? error.message : String(error));
    } finally {
      setPending(false);
    }
  }

  function saveTransaction(input: DeferredExpenseTransactionInput, item?: Transaction) {
    return runWrite(
      () => item ? updateTransactionWithLinkedPayable(item.id, input) : createTransactionWithOptionalPayable(input),
      (saved) => {
        setSurface(null);
        setInspected({ kind: 'transaction', item: saved });
      },
    );
  }

  function saveObligation(input: ObligationInput, item?: Obligation) {
    return runWrite(
      () => {
        if (item) {
          obligationsStore.update(item.id, input);
          return { ...item, ...input, updated_at: new Date().toISOString() };
        }
        return obligationsStore.create(input);
      },
      (saved) => {
        setSurface(null);
        setInspected({ kind: 'obligation', item: saved });
      },
    );
  }

  function saveSettlement(input: RecordSettlementWithAllocationsInput) {
    return runWrite(
      () => recordSettlementWithAllocations(input),
      () => setSurface(null),
    );
  }

  function confirmReverse() {
    if (!reverseTarget) return Promise.resolve();
    if (!reverseReason.trim()) {
      setWriteError(locale === 'ar' ? 'سبب العكس مطلوب.' : 'Reversal reason is required.');
      return Promise.resolve();
    }
    return runWrite(
      () => reverseSettlement(reverseTarget.id, reverseReason),
      () => {
        setReverseTarget(null);
        setReverseReason('');
      },
    );
  }

  const shellState = status === 'loading' ? 'loading' : status === 'error' ? 'error' : 'ready';
  const selectedProject = projectById.get(context.projectId ?? '');
  const selectedPartner = partnerById.get(context.partnerId ?? '');

  return (
    <>
      <WorkspaceShell
        title={locale === 'ar' ? 'مركز المالية' : 'Finance Hub'}
        description={locale === 'ar' ? 'سير واحد للحركة والذمة والتسوية والتوزيع، مع دليل وسياق قابلين للتتبع.' : 'One flow for movement, obligation, settlement, allocation, evidence, and context.'}
        workspaces={workspaces}
        activeWorkspace={workspace}
        onWorkspaceChange={setWorkspace}
        switcherLabel={locale === 'ar' ? 'مساحات المالية' : 'Finance workspaces'}
        loadingLabel={locale === 'ar' ? 'جار تحميل المالية' : 'Loading finance'}
        state={shellState}
        errorState={{ title: locale === 'ar' ? 'تعذر تحميل المالية' : 'Finance could not load', description: loadError ?? '', onRetry: () => void retry() }}
        actions={<Button onClick={() => beginTransaction()}><CircleDollarSign className="h-4 w-4" />{locale === 'ar' ? 'معاملة جديدة' : 'New transaction'}</Button>}
        summaries={
          <div className="grid gap-3 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2">
            <label className="text-xs font-semibold">{locale === 'ar' ? 'المشروع' : 'Project'}<select value={context.projectId ?? ''} onChange={(event) => setContext({ projectId: event.target.value || undefined, partnerId: context.partnerId })} className="mt-1 min-h-11 w-full rounded-xl border bg-card px-3"><option value="">{locale === 'ar' ? 'كل المشاريع' : 'All projects'}</option>{data.projects.map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en}</option>)}</select></label>
            <label className="text-xs font-semibold">{locale === 'ar' ? 'الطرف' : 'Party'}<select value={context.partnerId ?? ''} onChange={(event) => setContext({ ...context, partnerId: event.target.value || undefined })} className="mt-1 min-h-11 w-full rounded-xl border bg-card px-3"><option value="">{locale === 'ar' ? 'كل الأطراف' : 'All parties'}</option>{data.partners.map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en ?? item.name_ar}</option>)}</select></label>
          </div>
        }
      >
        {workspace === 'overview' && <FinanceOverviewView overview={overview} locale={locale} onSettle={(item) => setSurface({ kind: 'settlement', anchorId: item.id })} />}
        {workspace === 'transactions' && <TransactionsWorkspace items={filteredTransactions} projects={data.projects} partners={data.partners} filters={transactionFilters} locale={locale} onFilters={setTransactionFilters} onCreate={() => beginTransaction()} onEdit={beginTransaction} onInspect={(item) => setInspected({ kind: 'transaction', item })} />}
        {workspace === 'obligations' && <ObligationsWorkspace items={filteredObligations} partners={data.partners} filters={obligationFilters} locale={locale} onFilters={setObligationFilters} onCreate={() => setSurface({ kind: 'obligation' })} onEdit={(item) => setSurface({ kind: 'obligation', item })} onInspect={(item) => setInspected({ kind: 'obligation', item })} onSettle={(item) => setSurface({ kind: 'settlement', anchorId: item.id })} />}
        {workspace === 'settlements' && <SettlementsWorkspace settlements={data.settlements} allocations={data.allocations} locale={locale} onReverse={(item) => { setWriteError(null); setReverseTarget(item); }} />}
      </WorkspaceShell>

      {writeError && !surface && !reverseTarget && <FormErrorSummary serverError={writeError} title={locale === 'ar' ? 'تعذر تنفيذ العملية' : 'Operation could not complete'} />}

      <AdaptiveFormSurface open={surface?.kind === 'transaction'} onOpenChange={(open) => { if (!open) setSurface(null); }} title={surface?.kind === 'transaction' && surface.item ? (locale === 'ar' ? 'تعديل معاملة' : 'Edit transaction') : (locale === 'ar' ? 'معاملة سياقية' : 'Contextual transaction')} description={FINANCE_ATOMICITY_NOTICE[locale]} pending={pending} submitLabel={locale === 'ar' ? 'حفظ' : 'Save'} cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'} closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'} formId="finance-transaction-form">
        {surface?.kind === 'transaction' && <TransactionForm key={surface.item?.id ?? `${context.projectId}-${context.eventId}`} formId="finance-transaction-form" hideActions projectId={surface.item?.project_id ?? context.projectId ?? ''} initial={surface.item ?? { asset_id: context.assetId, partner_id: context.partnerId, operational_event_id: context.eventId }} onSubmit={(input) => saveTransaction(input, surface.item)} onCancel={() => setSurface(null)} loading={pending} />}
      </AdaptiveFormSurface>

      <AdaptiveFormSurface open={surface?.kind === 'obligation'} onOpenChange={(open) => { if (!open) setSurface(null); }} title={surface?.kind === 'obligation' && surface.item ? (locale === 'ar' ? 'تعديل ذمة' : 'Edit obligation') : (locale === 'ar' ? 'ذمة جديدة' : 'New obligation')} description={locale === 'ar' ? 'المدينة والدائنة فلتران داخل نفس مساحة العمل.' : 'Receivable and payable remain filters in one workspace.'} pending={pending} submitLabel={locale === 'ar' ? 'حفظ' : 'Save'} cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'} closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'} formId="finance-obligation-form">
        {surface?.kind === 'obligation' && <ObligationForm key={surface.item?.id ?? `${context.projectId}-${context.partnerId}`} formId="finance-obligation-form" hideActions partners={data.partners} projects={data.projects} defaultProjectId={context.projectId} defaultPartnerId={context.partnerId} initial={surface.item} onSubmit={(input) => saveObligation(input, surface.item)} onCancel={() => setSurface(null)} />}
      </AdaptiveFormSurface>

      <AdaptiveFormSurface open={surface?.kind === 'settlement'} onOpenChange={(open) => { if (!open) setSurface(null); }} title={locale === 'ar' ? 'تسجيل وتوزيع تسوية' : 'Record and allocate settlement'} description={locale === 'ar' ? 'حركة نقدية واحدة وتوزيعات قابلة للمراجعة.' : 'One cash movement with auditable allocations.'} pending={pending} submitLabel={locale === 'ar' ? 'تسجيل التسوية' : 'Record settlement'} cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'} closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'} formId="finance-settlement-form">
        {surface?.kind === 'settlement' && <SettlementFlowForm key={surface.anchorId ?? 'new'} formId="finance-settlement-form" obligations={data.obligations} documents={data.documents} anchorId={surface.anchorId} locale={locale} serverError={writeError} onSubmit={saveSettlement} />}
      </AdaptiveFormSurface>

      <EntityInspectorDrawer open={Boolean(inspected)} onOpenChange={(open) => { if (!open) setInspected(null); }} title={inspected?.kind === 'transaction' ? (inspected.item.description || inspected.item.category) : inspected?.kind === 'obligation' ? `${inspected.item.direction} · ${inspected.item.status}` : ''} closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'} relationshipsLabel={locale === 'ar' ? 'العلاقات' : 'Relationships'} activityLabel={locale === 'ar' ? 'السجل' : 'Activity'} summary={inspected && <dl className="grid grid-cols-2 gap-3 text-sm">{inspected.kind === 'transaction' ? <><Value label={locale === 'ar' ? 'المبلغ' : 'Amount'} value={`${inspected.item.amount_egp.toLocaleString()} EGP`} /><Value label={locale === 'ar' ? 'التاريخ' : 'Date'} value={inspected.item.transaction_date} /></> : <><Value label={locale === 'ar' ? 'الأصلي' : 'Original'} value={`${inspected.item.amount_egp.toLocaleString()} EGP`} /><Value label={locale === 'ar' ? 'المتبقي' : 'Remaining'} value={`${Math.max(0, inspected.item.amount_egp - inspected.item.amount_settled_egp).toLocaleString()} EGP`} /></>}</dl>} relationships={inspected && <div className="space-y-2 text-sm">{inspected.kind === 'transaction' ? <><p>{selectedProject?.name_ar ?? projectById.get(inspected.item.project_id)?.name_ar}</p><p>{inspected.item.asset_id ? assetById.get(inspected.item.asset_id)?.name_ar : '—'}</p><p>{inspected.item.partner_id ? partnerById.get(inspected.item.partner_id)?.name_ar : '—'}</p><p><FileText className="me-1 inline h-4 w-4" />{inspected.item.document_id ? documentById.get(inspected.item.document_id)?.title_ar : '—'}</p><p>{inspected.item.operational_event_id ? eventById.get(inspected.item.operational_event_id)?.type : '—'}</p></> : <><p>{selectedPartner?.name_ar ?? partnerById.get(inspected.item.partner_id)?.name_ar}</p><p>{inspected.item.project_id ? projectById.get(inspected.item.project_id)?.name_ar : '—'}</p><p><FileText className="me-1 inline h-4 w-4" />{inspected.item.document_id ? documentById.get(inspected.item.document_id)?.title_ar : '—'}</p></>}</div>} activity={inspected?.kind === 'obligation' ? <p className="text-sm">{data.settlements.filter((item) => item.obligation_id === inspected.item.id || data.allocations.some((allocation) => allocation.obligation_id === inspected.item.id && allocation.settlement_id === item.id)).length} {locale === 'ar' ? 'تسوية مرتبطة' : 'linked settlements'}</p> : <p className="text-sm text-muted-foreground">—</p>} actions={inspected && <>{inspected.kind === 'transaction' && <Button variant="secondary" onClick={() => setSurface({ kind: 'transaction', item: inspected.item })}>{locale === 'ar' ? 'تعديل' : 'Edit'}</Button>}{inspected.kind === 'obligation' && <Button onClick={() => setSurface({ kind: 'settlement', anchorId: inspected.item.id })}>{locale === 'ar' ? 'تحصيل/سداد' : 'Settle'}</Button>}{onHandoff && inspected.kind === 'transaction' && inspected.item.document_id && <Button variant="secondary" onClick={() => onHandoff({ destination: 'governance', intent: 'inspect-related', entityId: inspected.item.document_id!, entityType: 'document' })}><FileText className="h-4 w-4" />{locale === 'ar' ? 'فتح الدليل' : 'Open evidence'}</Button>}</>} />

      <ConfirmDialog open={Boolean(reverseTarget)} onOpenChange={(open) => { if (!open) { setReverseTarget(null); setReverseReason(''); } }} title={locale === 'ar' ? 'عكس التسوية' : 'Reverse settlement'} entityName={reverseTarget?.reference_number ?? reverseTarget?.id ?? ''} impact={locale === 'ar' ? 'يبقى السجل محفوظًا ويصبح أثره النشط صفرًا. اكتب السبب قبل التأكيد.' : 'History remains and the active effect becomes zero. Enter a reason before confirming.'} confirmLabel={locale === 'ar' ? 'عكس' : 'Reverse'} cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'} pending={pending} onConfirm={confirmReverse} />
      {reverseTarget && <label className="fixed start-1/2 top-[calc(50%+1rem)] z-[60] w-[min(24rem,calc(100vw-5rem))] -translate-x-1/2 rtl:translate-x-1/2"><span className="sr-only">{locale === 'ar' ? 'سبب العكس' : 'Reversal reason'}</span><input value={reverseReason} onChange={(event) => setReverseReason(event.target.value)} placeholder={locale === 'ar' ? 'سبب العكس…' : 'Reversal reason…'} className="min-h-11 w-full rounded-xl border bg-background px-3" /></label>}
    </>
  );
}

function Value({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl border p-3"><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 font-semibold">{value}</dd></div>;
}

import { requireDateOnly } from '../../core/lib/dateOnly';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import { requestOdooSync } from '../../core/odoo/hooks';
import { requireClient } from '../../core/storage/supabaseClientRegistry';
import type {
  Currency,
  Distribution,
  DistributionAllocation,
  EquityChangeType,
  PartnerLedgerEntry,
  PartnerLedgerEntryType,
} from '../../core/types/domain';
import { partnersHydration, projectPartnersHydration } from '../partners/storage';
import { projectsHydration } from '../projects/storage';
import { obligationsHydration } from '../obligations/storage';
import { transactionsHydration } from '../transactions/storage';
import {
  distributionAllocationsHydration,
  distributionAllocationsStorage,
  distributionsHydration,
  distributionsStorage,
  equityChangeEventsHydration,
  partnerLedgerEntriesHydration,
  partnerLedgerEntriesStorage,
} from './storage';
import { calculatePartnerLedgerSummary, type PartnerLedgerSummary } from './model';

export const OWNERSHIP_RPC_NAMES = [
  'change_ownership_atomic',
  'record_distribution_atomic',
  'approve_distribution_atomic',
  'pay_distribution_allocation_atomic',
  'record_partner_capital_movement_atomic',
  'record_partner_ledger_entry_atomic',
  'reverse_partner_ledger_entry_atomic',
  'get_ownership_as_of',
] as const;

export type OwnershipRpcName = typeof OWNERSHIP_RPC_NAMES[number];
export type OwnershipErrorKind = 'validation' | 'authorization' | 'conflict' | 'network' | 'not_found' | 'unknown';

type RpcScalar = string | number | boolean | null | undefined;
type RpcParams = Record<string, RpcScalar>;

export interface OwnershipRpcFailureDebug {
  rpc: OwnershipRpcName;
  params: RpcParams;
  original: unknown;
}

export class OwnershipServiceError extends Error {
  readonly kind: OwnershipErrorKind;
  readonly message_ar: string;
  readonly technicalError: unknown;
  readonly debug: OwnershipRpcFailureDebug;

  constructor(kind: OwnershipErrorKind, messageAr: string, debug: OwnershipRpcFailureDebug) {
    super(messageAr);
    this.name = 'OwnershipServiceError';
    this.kind = kind;
    this.message_ar = messageAr;
    this.technicalError = debug.original;
    this.debug = debug;
  }
}

export interface OwnershipMutationContext { requestId?: string }

export interface ChangeOwnershipInput extends OwnershipMutationContext {
  project_id: string;
  partner_id: string;
  effective_date: string;
  new_pct: number;
  change_type: EquityChangeType;
  consideration_amount?: number;
  consideration_currency?: Currency;
  supporting_document_id?: string;
  reason?: string;
  notes?: string;
}

export interface ChangeOwnershipRpcParams extends RpcParams {
  p_request_id: string;
  p_project_id: string;
  p_partner_id: string;
  p_effective_date: string;
  p_new_pct: number;
  p_change_type: EquityChangeType;
  p_consideration_amount?: number;
  p_consideration_currency?: Currency;
  p_supporting_document_id?: string;
  p_reason?: string;
  p_notes?: string;
}

export interface ChangeOwnershipResult {
  equity_change_event_id: string;
  project_partner_id: string | null;
  previous_pct: number;
  new_pct: number;
  total_equity_allocated: number;
}

export interface OwnershipAsOfRow {
  partner_id: string;
  equity_pct: number;
  effective_from: string;
  effective_to: string | null;
  project_partner_id: string;
}

export interface RecordDistributionInput extends OwnershipMutationContext {
  project_id: string;
  distribution_date: string;
  ownership_as_of_date: string;
  total_amount: number;
  currency: Currency;
  fx_rate: number;
  notes?: string;
  supporting_document_id?: string;
}

export interface RecordDistributionRpcParams extends RpcParams {
  p_request_id: string;
  p_project_id: string;
  p_distribution_date: string;
  p_ownership_as_of_date: string;
  p_total_amount: number;
  p_currency: Currency;
  p_fx_rate: number;
  p_notes?: string;
  p_supporting_document_id?: string;
}

export interface RecordDistributionResult {
  distribution_id: string;
  total_amount: number;
  total_amount_egp: number;
  status: Distribution['status'];
}

export interface RecordPartnerLedgerEntryInput extends OwnershipMutationContext {
  project_id: string;
  partner_id: string;
  entry_type: PartnerLedgerEntryType;
  amount: number;
  currency: Currency;
  fx_rate: number;
  posting_date: string;
  bank_account_id?: string;
  supporting_document_id?: string;
  related_equity_event_id?: string;
  related_distribution_id?: string;
  notes?: string;
  reversal_of_id?: string;
}

export interface RecordPartnerLedgerEntryRpcParams extends RpcParams {
  p_request_id: string;
  p_project_id: string;
  p_partner_id: string;
  p_entry_type: PartnerLedgerEntryType;
  p_amount: number;
  p_currency: Currency;
  p_fx_rate: number;
  p_posting_date: string;
  p_supporting_document_id?: string;
  p_related_equity_event_id?: string;
  p_related_distribution_id?: string;
  p_notes?: string;
  p_reversal_of_id?: string;
}

export interface RecordPartnerLedgerEntryResult {
  ledger_entry_id: string;
  bank_transaction_id?: string;
  amount_egp: number;
  entry_type: PartnerLedgerEntryType;
}

export interface ApproveDistributionInput extends OwnershipMutationContext {
  distribution_id: string;
  notes?: string;
}
export interface ApproveDistributionResult {
  distribution_id: string;
  status: 'approved';
  ledger_entry_ids: string[];
}
export interface PayDistributionAllocationInput extends OwnershipMutationContext {
  allocation_id: string;
  bank_account_id: string;
  payment_date: string;
  payment_document_id?: string;
  notes?: string;
}
export interface PayDistributionAllocationResult {
  allocation_id: string;
  ledger_entry_id: string;
  bank_transaction_id: string;
  distribution_status: 'approved' | 'paid';
}
export interface ReversePartnerLedgerInput extends OwnershipMutationContext {
  entry_id: string;
  posting_date: string;
  reason: string;
}
export interface ReversePartnerLedgerResult {
  original_entry_id: string;
  reversal_entry_id: string;
  bank_transaction_id?: string;
}

const ownershipHydrations = [
  projectsHydration,
  partnersHydration,
  projectPartnersHydration,
  equityChangeEventsHydration,
  partnerLedgerEntriesHydration,
  distributionsHydration,
  distributionAllocationsHydration,
  transactionsHydration,
  obligationsHydration,
] as const;

export function createOwnershipRequestId(): string { return crypto.randomUUID(); }

async function rehydrateOwnershipStores(): Promise<void> {
  await Promise.all(ownershipHydrations.map((store) => store.rehydrate()));
}

function extractMessage(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  if (error && typeof error === 'object' && 'message' in error) {
    const value = error.message;
    return typeof value === 'string' ? value : String(value);
  }
  if (error === null || error === undefined) return '';
  if (typeof error === 'object') return JSON.stringify(error);
  return String(error);
}
function extractCode(error: unknown): string | undefined {
  if (error && typeof error === 'object' && 'code' in error) {
    const value = error.code;
    return typeof value === 'string' ? value : undefined;
  }
  return undefined;
}
function classifyRpcError(error: unknown): OwnershipErrorKind {
  const code = extractCode(error);
  const message = extractMessage(error).toLowerCase();
  if (code === '23514' || code === '0A000' || message.includes('must') || message.includes('cannot') || message.includes('invalid') || message.includes('total equity')) return 'validation';
  if (code === '42501' || message.includes('permission') || message.includes('not authorized') || message.includes('rls')) return 'authorization';
  if (code === '23505' || code === '40001' || code === '40P01' || message.includes('duplicate') || message.includes('conflict')) return 'conflict';
  if (code === 'P0002' || message.includes('not found')) return 'not_found';
  if (message.includes('failed to fetch') || message.includes('network') || code === 'PGRST202') return 'network';
  return 'unknown';
}

const OWNERSHIP_ERROR_TRANSLATIONS: Array<{ includes: string; message: string }> = [
  { includes: 'total equity would exceed 100', message: 'لا يمكن تنفيذ التغيير لأن إجمالي نسب الملكية سيتجاوز 100%.' },
  { includes: 'already has active ownership', message: 'لا يمكن إدخال الشريك لأنه يملك حصة فعالة بالفعل في هذا المشروع.' },
  { includes: 'entry must set a positive', message: 'إدخال الشريك يتطلب نسبة ملكية موجبة.' },
  { includes: 'has no active ownership', message: 'لا توجد ملكية فعالة لهذا الشريك في المشروع في الوقت الحالي.' },
  { includes: 'exit must set percentage to 0', message: 'خروج الشريك يتطلب أن تكون النسبة الجديدة صفرًا.' },
  { includes: 'higher percentage', message: 'عملية الزيادة يجب أن ترفع النسبة عن النسبة الحالية.' },
  { includes: 'lower percentage', message: 'عملية التخفيض يجب أن تقلل النسبة عن النسبة الحالية.' },
  { includes: 'ownership_as_of_date cannot be after distribution_date', message: 'تاريخ الملكية المستخدم للتوزيع يجب أن يسبق تاريخ التوزيع أو يساويه.' },
  { includes: 'distribution amount must be positive', message: 'مبلغ التوزيع يجب أن يكون أكبر من صفر.' },
  { includes: 'only draft distributions can be approved', message: 'لا يمكن اعتماد هذا التوزيع لأنه ليس في حالة مسودة.' },
  { includes: 'distribution must be approved before payment', message: 'يجب اعتماد التوزيع قبل دفع حصة الشريك.' },
  { includes: 'distribution allocation is not due', message: 'هذه الحصة مدفوعة أو معكوسة بالفعل.' },
  { includes: 'currency must match the selected bank account', message: 'عملة الحركة لا تطابق عملة الحساب البنكي المختار.' },
  { includes: 'cash and distribution ledger entries require', message: 'حركات رأس المال والتوزيعات يجب تسجيلها من التدفق البنكي المعتمد.' },
  { includes: 'reversal reason is required', message: 'سبب العكس مطلوب.' },
  { includes: 'already reversed', message: 'تم عكس هذا القيد من قبل.' },
  { includes: 'ledger entry amount must be positive', message: 'مبلغ حركة الشريك يجب أن يكون أكبر من صفر.' },
  { includes: 'project not found', message: 'المشروع غير موجود أو لا تملك صلاحية الوصول إليه.' },
  { includes: 'reversal target entry not found', message: 'قيد العكس غير موجود أو لا تملك صلاحية الوصول إليه.' },
];

const ERROR_KIND_MESSAGES: Record<Exclude<OwnershipErrorKind, 'validation'>, string> = {
  authorization: 'ليست لديك صلاحية تنفيذ هذه العملية على هذه السجلات.',
  conflict: 'حدث تعارض أثناء الحفظ. تمت إعادة تحميل البيانات، راجع الحالة الحالية ثم أعد المحاولة.',
  network: 'تعذر الاتصال بالخادم أو العثور على دالة Supabase المطلوبة. تمت إعادة مزامنة البيانات.',
  not_found: 'السجل المطلوب غير موجود أو لا يمكن الوصول إليه.',
  unknown: 'تعذر تنفيذ عملية الملكية. تمت إعادة تحميل البيانات، ويمكن مراجعة الخطأ الفني في أدوات التشخيص.',
};
function arabicMessageFor(kind: OwnershipErrorKind, error: unknown): string {
  const message = extractMessage(error).toLowerCase();
  const translated = OWNERSHIP_ERROR_TRANSLATIONS.find((item) => message.includes(item.includes));
  if (translated) return translated.message;
  return kind === 'validation' ? translateServerError(error) : ERROR_KIND_MESSAGES[kind];
}
function toOwnershipError(rpc: OwnershipRpcName, params: RpcParams, error: unknown): OwnershipServiceError {
  const kind = classifyRpcError(error);
  return new OwnershipServiceError(kind, arabicMessageFor(kind, error), { rpc, params, original: error });
}
function unwrapObjectResult<T>(data: unknown): T {
  if (Array.isArray(data)) {
    if (data.length !== 1) throw new Error('استجابة الخادم غير متوقعة لعملية الملكية.');
    return data[0] as T;
  }
  return data as T;
}
function unwrapArrayResult<T>(data: unknown): T[] {
  if (!Array.isArray(data)) throw new Error('استجابة الخادم غير متوقعة لاستعلام الملكية.');
  return data as T[];
}
async function invokeOwnershipRpc<T>(rpc: OwnershipRpcName, params: RpcParams): Promise<T> {
  try {
    const { data, error } = await requireClient().rpc(rpc, params);
    if (error) throw error;
    await rehydrateOwnershipStores();
    return unwrapObjectResult<T>(data);
  } catch (error) {
    await rehydrateOwnershipStores();
    throw toOwnershipError(rpc, params, error);
  }
}
async function queryOwnershipRpc<T>(rpc: OwnershipRpcName, params: RpcParams): Promise<T[]> {
  try {
    const { data, error } = await requireClient().rpc(rpc, params);
    if (error) throw error;
    await Promise.all([projectPartnersHydration.rehydrate(), equityChangeEventsHydration.rehydrate()]);
    return unwrapArrayResult<T>(data);
  } catch (error) {
    await Promise.all([projectPartnersHydration.rehydrate(), equityChangeEventsHydration.rehydrate()]);
    throw toOwnershipError(rpc, params, error);
  }
}

export function buildChangeOwnershipParams(input: ChangeOwnershipInput): ChangeOwnershipRpcParams {
  return {
    p_request_id: input.requestId ?? createOwnershipRequestId(), p_project_id: input.project_id,
    p_partner_id: input.partner_id, p_effective_date: requireDateOnly(input.effective_date, 'تاريخ سريان الملكية'),
    p_new_pct: input.new_pct, p_change_type: input.change_type,
    p_consideration_amount: input.consideration_amount, p_consideration_currency: input.consideration_currency,
    p_supporting_document_id: input.supporting_document_id || undefined,
    p_reason: input.reason || undefined, p_notes: input.notes || undefined,
  };
}
export function buildRecordDistributionParams(input: RecordDistributionInput): RecordDistributionRpcParams {
  return {
    p_request_id: input.requestId ?? createOwnershipRequestId(), p_project_id: input.project_id,
    p_distribution_date: requireDateOnly(input.distribution_date, 'تاريخ التوزيع'),
    p_ownership_as_of_date: requireDateOnly(input.ownership_as_of_date, 'تاريخ ملكية التوزيع'),
    p_total_amount: input.total_amount, p_currency: input.currency, p_fx_rate: input.fx_rate,
    p_notes: input.notes || undefined, p_supporting_document_id: input.supporting_document_id || undefined,
  };
}
export function buildRecordPartnerLedgerEntryParams(input: RecordPartnerLedgerEntryInput): RecordPartnerLedgerEntryRpcParams {
  return {
    p_request_id: input.requestId ?? createOwnershipRequestId(), p_project_id: input.project_id,
    p_partner_id: input.partner_id, p_entry_type: input.entry_type, p_amount: input.amount,
    p_currency: input.currency, p_fx_rate: input.fx_rate,
    p_posting_date: requireDateOnly(input.posting_date, 'تاريخ القيد'),
    p_supporting_document_id: input.supporting_document_id || undefined,
    p_related_equity_event_id: input.related_equity_event_id || undefined,
    p_related_distribution_id: input.related_distribution_id || undefined,
    p_notes: input.notes || undefined, p_reversal_of_id: input.reversal_of_id || undefined,
  };
}

export async function changeOwnership(input: ChangeOwnershipInput): Promise<ChangeOwnershipResult> {
  return invokeOwnershipRpc<ChangeOwnershipResult>('change_ownership_atomic', buildChangeOwnershipParams(input));
}
export async function enterPartnerIntoProject(input: Omit<ChangeOwnershipInput, 'change_type'>): Promise<ChangeOwnershipResult> {
  return changeOwnership({ ...input, change_type: 'entry' });
}
export async function increaseOwnership(input: Omit<ChangeOwnershipInput, 'change_type'>): Promise<ChangeOwnershipResult> {
  return changeOwnership({ ...input, change_type: 'increase' });
}
export async function decreaseOwnership(input: Omit<ChangeOwnershipInput, 'change_type'>): Promise<ChangeOwnershipResult> {
  return changeOwnership({ ...input, change_type: 'decrease' });
}
export async function exitPartnerFromProject(input: Omit<ChangeOwnershipInput, 'change_type' | 'new_pct'>): Promise<ChangeOwnershipResult> {
  return changeOwnership({ ...input, change_type: 'exit', new_pct: 0 });
}
export async function reenterPartnerIntoProject(input: Omit<ChangeOwnershipInput, 'change_type'>): Promise<ChangeOwnershipResult> {
  return changeOwnership({ ...input, change_type: 'entry' });
}
export async function getOwnershipAsOf(projectId: string, asOfDate: string): Promise<OwnershipAsOfRow[]> {
  return queryOwnershipRpc<OwnershipAsOfRow>('get_ownership_as_of', {
    p_project_id: projectId, p_as_of_date: requireDateOnly(asOfDate, 'تاريخ الملكية'),
  });
}

export async function createProfitDistribution(input: RecordDistributionInput): Promise<RecordDistributionResult> {
  return invokeOwnershipRpc<RecordDistributionResult>('record_distribution_atomic', buildRecordDistributionParams(input));
}
export async function approveProfitDistribution(input: ApproveDistributionInput): Promise<ApproveDistributionResult> {
  const result = await invokeOwnershipRpc<ApproveDistributionResult>('approve_distribution_atomic', {
    p_request_id: input.requestId ?? createOwnershipRequestId(),
    p_distribution_id: input.distribution_id,
    p_notes: input.notes || undefined,
  });
  void requestOdooSync();
  return result;
}
export async function payDistributionAllocation(input: PayDistributionAllocationInput): Promise<PayDistributionAllocationResult> {
  const result = await invokeOwnershipRpc<PayDistributionAllocationResult>('pay_distribution_allocation_atomic', {
    p_request_id: input.requestId ?? createOwnershipRequestId(),
    p_allocation_id: input.allocation_id,
    p_bank_account_id: input.bank_account_id,
    p_payment_date: requireDateOnly(input.payment_date, 'تاريخ دفع التوزيع'),
    p_payment_document_id: input.payment_document_id || undefined,
    p_notes: input.notes || undefined,
  });
  void requestOdooSync();
  return result;
}

export async function recordPartnerLedgerEntry(input: RecordPartnerLedgerEntryInput): Promise<RecordPartnerLedgerEntryResult> {
  if (input.entry_type === 'distribution_entitlement' || input.entry_type === 'distribution_payment') {
    throw new Error('استحقاقات ودفعات التوزيع تُدار فقط من دورة اعتماد ودفع التوزيع.');
  }
  if (input.entry_type === 'capital_contribution' || input.entry_type === 'withdrawal') {
    if (!input.bank_account_id) throw new Error('اختر حساب البنك أو الخزينة لحركة رأس المال.');
    const result = await invokeOwnershipRpc<RecordPartnerLedgerEntryResult>('record_partner_capital_movement_atomic', {
      p_request_id: input.requestId ?? createOwnershipRequestId(),
      p_project_id: input.project_id,
      p_partner_id: input.partner_id,
      p_entry_type: input.entry_type,
      p_amount: input.amount,
      p_currency: input.currency,
      p_fx_rate: input.fx_rate,
      p_posting_date: requireDateOnly(input.posting_date, 'تاريخ حركة رأس المال'),
      p_bank_account_id: input.bank_account_id,
      p_supporting_document_id: input.supporting_document_id || undefined,
      p_related_equity_event_id: input.related_equity_event_id || undefined,
      p_notes: input.notes || undefined,
    });
    void requestOdooSync();
    return result;
  }
  if (input.entry_type === 'reversal') {
    if (!input.reversal_of_id) throw new Error('اختر القيد الأصلي المطلوب عكسه.');
    const result = await reversePartnerLedgerEntry({
      requestId: input.requestId,
      entry_id: input.reversal_of_id,
      posting_date: input.posting_date,
      reason: input.notes ?? '',
    });
    return {
      ledger_entry_id: result.reversal_entry_id,
      bank_transaction_id: result.bank_transaction_id,
      amount_egp: input.amount * input.fx_rate,
      entry_type: 'reversal',
    };
  }
  return invokeOwnershipRpc<RecordPartnerLedgerEntryResult>(
    'record_partner_ledger_entry_atomic', buildRecordPartnerLedgerEntryParams(input),
  );
}

export async function reversePartnerLedgerEntry(input: ReversePartnerLedgerInput): Promise<ReversePartnerLedgerResult> {
  const result = await invokeOwnershipRpc<ReversePartnerLedgerResult>('reverse_partner_ledger_entry_atomic', {
    p_request_id: input.requestId ?? createOwnershipRequestId(),
    p_entry_id: input.entry_id,
    p_posting_date: requireDateOnly(input.posting_date, 'تاريخ عكس القيد'),
    p_reason: input.reason,
  });
  void requestOdooSync();
  return result;
}
export async function recordPartnerContribution(input: Omit<RecordPartnerLedgerEntryInput, 'entry_type'>): Promise<RecordPartnerLedgerEntryResult> {
  return recordPartnerLedgerEntry({ ...input, entry_type: 'capital_contribution' });
}
export async function recordPartnerWithdrawal(input: Omit<RecordPartnerLedgerEntryInput, 'entry_type'>): Promise<RecordPartnerLedgerEntryResult> {
  return recordPartnerLedgerEntry({ ...input, entry_type: 'withdrawal' });
}

export function retrieveDistributionAllocations(distributionId: string): DistributionAllocation[] {
  return distributionAllocationsStorage.getByDistribution(distributionId);
}
export function retrievePartnerLedgerHistory(partnerId: string, projectId?: string): PartnerLedgerEntry[] {
  const rows = partnerLedgerEntriesStorage.getByPartner(partnerId);
  return projectId ? rows.filter((entry) => entry.project_id === projectId) : rows;
}
export function calculateCurrentPartnerLedgerBalance(partnerId: string, projectId?: string): number {
  return calculateCurrentPartnerLedgerSummary(partnerId, projectId).current_balance_egp;
}
export function calculateCurrentPartnerLedgerSummary(partnerId: string, projectId?: string): PartnerLedgerSummary {
  return calculatePartnerLedgerSummary(retrievePartnerLedgerHistory(partnerId, projectId));
}
export function retrievePartnerDistributions(partnerId: string): Distribution[] {
  const ids = new Set(distributionAllocationsStorage.getByPartner(partnerId).map(row => row.distribution_id));
  return distributionsStorage.getAll().filter(row => ids.has(row.id));
}
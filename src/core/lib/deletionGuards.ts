import type { Asset, Document, Obligation, OperationalEvent, ProjectPartner, StockAdjustment, Transaction } from '../types/domain';
import type { Settlement } from '../../features/settlements/types';

export interface DeletionGuardResult {
  canDelete: boolean;
  message_ar: string;
}

const TRANSACTIONS_KEY = 'terranex.transactions.v2';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const SETTLEMENTS_KEY = 'terranex.settlements.v1';
const ASSETS_KEY = 'terranex.assets.v1';
const DOCUMENTS_KEY = 'terranex.documents.v1';
const PROJECT_PARTNERS_KEY = 'terranex.projectPartners.v1';
const OPERATIONAL_EVENTS_KEY = 'terranex.operationalEvents.v1';
const STOCK_ADJUSTMENTS_KEY = 'terranex.stockAdjustments.v1';

interface ArrayReadResult<T> {
  ok: boolean;
  value: T[];
}

function readArray<T>(key: string): ArrayReadResult<T> {
  if (typeof localStorage === 'undefined') return { ok: false, value: [] };
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return { ok: true, value: [] };
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return { ok: false, value: [] };
    return { ok: true, value: parsed as T[] };
  } catch {
    return { ok: false, value: [] };
  }
}

function blockIf(count: number, label: string): string | null {
  if (count === 0) return null;
  return `${label}: ${count}`;
}

function result(blockers: Array<string | null>, entity: string, reads: Array<ArrayReadResult<unknown>>): DeletionGuardResult {
  if (reads.some((read) => !read.ok)) {
    return {
      canDelete: false,
      message_ar: `تعذر التحقق من روابط ${entity} بسبب مشكلة في قراءة البيانات المحلية. لم يتم الحذف لحماية البيانات.`,
    };
  }

  const activeBlockers = blockers.filter((blocker): blocker is string => Boolean(blocker));
  if (activeBlockers.length === 0) {
    return { canDelete: true, message_ar: `يمكن حذف ${entity} بعد التأكيد. لا توجد روابط تشغيلية تمنع الحذف.` };
  }
  return {
    canDelete: false,
    message_ar: `لا يمكن حذف ${entity} لأنه مرتبط بسجلات مالية أو تشغيلية. افصل أو عالج الروابط أولاً: ${activeBlockers.join('، ')}.`,
  };
}

export function guardProjectDeletion(projectId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY);
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY);
  const assets = readArray<Asset>(ASSETS_KEY);
  const documents = readArray<Document>(DOCUMENTS_KEY);
  const partners = readArray<ProjectPartner>(PROJECT_PARTNERS_KEY);
  const events = readArray<OperationalEvent>(OPERATIONAL_EVENTS_KEY);
  const adjustments = readArray<StockAdjustment>(STOCK_ADJUSTMENTS_KEY);
  return result([
    blockIf(transactions.value.filter((item) => item.project_id === projectId).length, 'معاملات'),
    blockIf(obligations.value.filter((item) => item.project_id === projectId).length, 'التزامات'),
    blockIf(assets.value.filter((item) => item.project_id === projectId).length, 'أصول'),
    blockIf(documents.value.filter((item) => item.project_id === projectId).length, 'مستندات'),
    blockIf(partners.value.filter((item) => item.project_id === projectId).length, 'شركاء'),
    blockIf(events.value.filter((item) => item.project_id === projectId).length, 'أحداث تشغيلية'),
    blockIf(adjustments.value.filter((item) => item.project_id === projectId).length, 'تسويات مخزون'),
  ], 'المشروع', [transactions, obligations, assets, documents, partners, events, adjustments]);
}

export function guardPartnerDeletion(partnerId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY);
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY);
  const documents = readArray<Document>(DOCUMENTS_KEY);
  const projects = readArray<ProjectPartner>(PROJECT_PARTNERS_KEY);
  return result([
    blockIf(transactions.value.filter((item) => item.partner_id === partnerId).length, 'معاملات'),
    blockIf(obligations.value.filter((item) => item.partner_id === partnerId).length, 'التزامات'),
    blockIf(documents.value.filter((item) => item.partner_id === partnerId).length, 'مستندات'),
    blockIf(projects.value.filter((item) => item.partner_id === partnerId).length, 'مشاريع ملكية'),
  ], 'الشريك', [transactions, obligations, documents, projects]);
}

export function guardAssetDeletion(assetId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY);
  const documents = readArray<Document>(DOCUMENTS_KEY);
  const events = readArray<OperationalEvent>(OPERATIONAL_EVENTS_KEY);
  const adjustments = readArray<StockAdjustment>(STOCK_ADJUSTMENTS_KEY);
  return result([
    blockIf(transactions.value.filter((item) => item.asset_id === assetId).length, 'معاملات'),
    blockIf(documents.value.filter((item) => item.asset_id === assetId).length, 'مستندات'),
    blockIf(events.value.filter((item) => item.asset_id === assetId).length, 'أحداث تشغيلية'),
    blockIf(adjustments.value.filter((item) => item.asset_id === assetId).length, 'تسويات مخزون'),
  ], 'الأصل', [transactions, documents, events, adjustments]);
}

export function guardDocumentDeletion(documentId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY);
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY);
  const settlements = readArray<Settlement>(SETTLEMENTS_KEY);
  const events = readArray<OperationalEvent>(OPERATIONAL_EVENTS_KEY);
  return result([
    blockIf(transactions.value.filter((item) => item.document_id === documentId).length, 'معاملات'),
    blockIf(obligations.value.filter((item) => item.document_id === documentId).length, 'التزامات'),
    blockIf(settlements.value.filter((item) => item.receipt_document_id === documentId).length, 'تسويات'),
    blockIf(events.value.filter((item) => item.document_id === documentId).length, 'أحداث تشغيلية'),
  ], 'المستند', [transactions, obligations, settlements, events]);
}

export function guardTransactionDeletion(transactionId: string): DeletionGuardResult {
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY);
  const events = readArray<OperationalEvent>(OPERATIONAL_EVENTS_KEY);
  return result([
    blockIf(obligations.value.filter((item) => item.source_transaction_id === transactionId).length, 'التزامات'),
    blockIf(events.value.filter((item) => item.linked_transaction_id === transactionId).length, 'أحداث تشغيلية'),
  ], 'المعاملة', [obligations, events]);
}

export function confirmSafeDeletion(message: string) {
  if (typeof window === 'undefined') return false;
  return window.confirm(`${message}\n\nهل تريد المتابعة؟`);
}

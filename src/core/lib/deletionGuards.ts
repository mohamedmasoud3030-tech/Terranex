import type { Asset, Document, Obligation, ProjectPartner, Transaction } from '../types/domain';

export interface DeletionGuardResult {
  canDelete: boolean;
  message_ar: string;
}

const TRANSACTIONS_KEY = 'terranex.transactions.v2';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const ASSETS_KEY = 'terranex.assets.v1';
const DOCUMENTS_KEY = 'terranex.documents.v1';
const PROJECT_PARTNERS_KEY = 'terranex.projectPartners.v1';

function readArray<T>(key: string): T[] {
  if (typeof localStorage === 'undefined') return [];
  try {
    const raw = localStorage.getItem(key);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed as T[] : [];
  } catch {
    return [];
  }
}

function blockIf(count: number, label: string): string | null {
  if (count === 0) return null;
  return `${label}: ${count}`;
}

function result(blockers: Array<string | null>, entity: string): DeletionGuardResult {
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
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY).filter((item) => item.project_id === projectId);
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY).filter((item) => item.project_id === projectId);
  const assets = readArray<Asset>(ASSETS_KEY).filter((item) => item.project_id === projectId);
  const documents = readArray<Document>(DOCUMENTS_KEY).filter((item) => item.project_id === projectId);
  const partners = readArray<ProjectPartner>(PROJECT_PARTNERS_KEY).filter((item) => item.project_id === projectId);
  return result([
    blockIf(transactions.length, 'معاملات'),
    blockIf(obligations.length, 'التزامات'),
    blockIf(assets.length, 'أصول'),
    blockIf(documents.length, 'مستندات'),
    blockIf(partners.length, 'شركاء'),
  ], 'المشروع');
}

export function guardPartnerDeletion(partnerId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY).filter((item) => item.partner_id === partnerId);
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY).filter((item) => item.partner_id === partnerId);
  const documents = readArray<Document>(DOCUMENTS_KEY).filter((item) => item.partner_id === partnerId);
  const projects = readArray<ProjectPartner>(PROJECT_PARTNERS_KEY).filter((item) => item.partner_id === partnerId);
  return result([
    blockIf(transactions.length, 'معاملات'),
    blockIf(obligations.length, 'التزامات'),
    blockIf(documents.length, 'مستندات'),
    blockIf(projects.length, 'مشاريع ملكية'),
  ], 'الشريك');
}

export function guardAssetDeletion(assetId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY).filter((item) => item.asset_id === assetId);
  const documents = readArray<Document>(DOCUMENTS_KEY).filter((item) => item.asset_id === assetId);
  return result([
    blockIf(transactions.length, 'معاملات'),
    blockIf(documents.length, 'مستندات'),
  ], 'الأصل');
}

export function guardDocumentDeletion(documentId: string): DeletionGuardResult {
  const transactions = readArray<Transaction>(TRANSACTIONS_KEY).filter((item) => item.document_id === documentId);
  const obligations = readArray<Obligation>(OBLIGATIONS_KEY).filter((item) => item.document_id === documentId);
  return result([
    blockIf(transactions.length, 'معاملات'),
    blockIf(obligations.length, 'التزامات'),
  ], 'المستند');
}

export function confirmSafeDeletion(message: string) {
  if (typeof window === 'undefined') return false;
  return window.confirm(`${message}\n\nهل تريد المتابعة؟`);
}

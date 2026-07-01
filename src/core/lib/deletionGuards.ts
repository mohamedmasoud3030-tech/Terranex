import { requireClient } from '../storage/supabaseClientRegistry';

export interface DeletionGuardResult {
  canDelete: boolean;
  message_ar: string;
}

const FAILSAFE: DeletionGuardResult = {
  canDelete: false,
  message_ar: 'تعذر التحقق من الروابط التشغيلية عبر الخادم. لم يتم الحذف لحماية البيانات.',
};

async function callGuard(fn: string, param: string, id: string): Promise<DeletionGuardResult> {
  const { data, error } = await requireClient().rpc(fn, { [param]: id });
  if (error || !data || !Array.isArray(data) || data.length === 0) {
    if (error) console.error(`فشل استدعاء ${fn}:`, error.message);
    return FAILSAFE;
  }
  const row = data[0] as { can_delete: boolean; message_ar: string };
  return { canDelete: row.can_delete, message_ar: row.message_ar };
}

export function guardProjectDeletion(projectId: string): Promise<DeletionGuardResult> {
  return callGuard('guard_project_deletion', 'p_project_id', projectId);
}

export function guardPartnerDeletion(partnerId: string): Promise<DeletionGuardResult> {
  return callGuard('guard_partner_deletion', 'p_partner_id', partnerId);
}

export function guardAssetDeletion(assetId: string): Promise<DeletionGuardResult> {
  return callGuard('guard_asset_deletion', 'p_asset_id', assetId);
}

export function guardDocumentDeletion(documentId: string): Promise<DeletionGuardResult> {
  return callGuard('guard_document_deletion', 'p_document_id', documentId);
}

export function guardTransactionDeletion(transactionId: string): Promise<DeletionGuardResult> {
  return callGuard('guard_transaction_deletion', 'p_transaction_id', transactionId);
}

export function confirmSafeDeletion(message: string) {
  if (typeof window === 'undefined') return false;
  return window.confirm(`${message}\n\nهل تريد المتابعة؟`);
}

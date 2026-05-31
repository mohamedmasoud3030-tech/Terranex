import { countAssetRelations, countDocumentRelations, countPartnerRelations, countProjectRelations, type DomainRelations, type RelationCount } from './relations';

export interface DeletionGuardResult {
  allowed: boolean;
  title: string;
  message: string;
  blockingRelations: RelationCount[];
}

function buildResult(entityLabel: string, counts: RelationCount[]): DeletionGuardResult {
  const blockingRelations = counts.filter((item) => item.count > 0);
  if (blockingRelations.length === 0) {
    return {
      allowed: true,
      title: `حذف ${entityLabel}`,
      message: `يمكن حذف ${entityLabel}. يتطلب الحذف تأكيداً صريحاً لأنه إجراء نهائي.`,
      blockingRelations,
    };
  }

  const details = blockingRelations.map((item) => `${item.label}: ${item.count}`).join('، ');
  return {
    allowed: false,
    title: `لا يمكن حذف ${entityLabel}`,
    message: `لا يمكن الحذف لأن هناك سجلات مرتبطة: ${details}. افصل أو سو السجلات المرتبطة أولاً.`,
    blockingRelations,
  };
}

export function guardProjectDeletion(projectId: string, relations: DomainRelations) {
  return buildResult('المشروع', countProjectRelations(projectId, relations));
}

export function guardPartnerDeletion(partnerId: string, relations: DomainRelations) {
  return buildResult('الشريك', countPartnerRelations(partnerId, relations));
}

export function guardAssetDeletion(assetId: string, relations: DomainRelations) {
  return buildResult('الأصل', countAssetRelations(assetId, relations));
}

export function guardDocumentDeletion(documentId: string, relations: DomainRelations) {
  return buildResult('المستند', countDocumentRelations(documentId, relations));
}

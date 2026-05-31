import type { Asset, Document, Obligation, OperationalEvent, ProjectPartner, StockAdjustment, Transaction } from '../types/domain';

export interface DomainRelations {
  transactions: Transaction[];
  assets: Asset[];
  obligations: Obligation[];
  documents: Document[];
  projectPartners: ProjectPartner[];
  operationalEvents: OperationalEvent[];
  stockAdjustments: StockAdjustment[];
}

export interface RelationCount {
  label: string;
  count: number;
}

export function countProjectRelations(projectId: string, relations: DomainRelations): RelationCount[] {
  return [
    { label: 'معاملات', count: relations.transactions.filter((item) => item.project_id === projectId).length },
    { label: 'أصول', count: relations.assets.filter((item) => item.project_id === projectId).length },
    { label: 'ذمم والتزامات', count: relations.obligations.filter((item) => item.project_id === projectId).length },
    { label: 'مستندات', count: relations.documents.filter((item) => item.project_id === projectId).length },
    { label: 'شركاء مشروع', count: relations.projectPartners.filter((item) => item.project_id === projectId).length },
    { label: 'أحداث تشغيلية', count: relations.operationalEvents.filter((item) => item.project_id === projectId).length },
    { label: 'تسويات مخزون', count: relations.stockAdjustments.filter((item) => item.project_id === projectId).length },
  ];
}

export function countPartnerRelations(partnerId: string, relations: DomainRelations): RelationCount[] {
  return [
    { label: 'معاملات', count: relations.transactions.filter((item) => item.partner_id === partnerId).length },
    { label: 'ذمم والتزامات', count: relations.obligations.filter((item) => item.partner_id === partnerId).length },
    { label: 'مستندات', count: relations.documents.filter((item) => item.partner_id === partnerId).length },
    { label: 'شراكات مشاريع', count: relations.projectPartners.filter((item) => item.partner_id === partnerId).length },
  ];
}

export function countAssetRelations(assetId: string, relations: DomainRelations): RelationCount[] {
  return [
    { label: 'معاملات', count: relations.transactions.filter((item) => item.asset_id === assetId).length },
    { label: 'مستندات', count: relations.documents.filter((item) => item.asset_id === assetId).length },
    { label: 'أحداث تشغيلية', count: relations.operationalEvents.filter((item) => item.asset_id === assetId).length },
    { label: 'تسويات مخزون', count: relations.stockAdjustments.filter((item) => item.asset_id === assetId).length },
  ];
}

export function countDocumentRelations(documentId: string, relations: DomainRelations): RelationCount[] {
  return [
    { label: 'معاملات', count: relations.transactions.filter((item) => item.document_id === documentId).length },
    { label: 'ذمم والتزامات', count: relations.obligations.filter((item) => item.document_id === documentId).length },
    { label: 'أحداث تشغيلية', count: relations.operationalEvents.filter((item) => item.document_id === documentId).length },
  ];
}

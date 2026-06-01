import type { Document, Partner, Project, Transaction } from '../types/domain';

const PROJECTS_KEY = 'terranex.projects.v1';
const PARTNERS_KEY = 'terranex.partners.v1';
const DOCUMENTS_KEY = 'terranex.documents.v1';

function readArray<T>(key: string, label: string): T[] {
  if (typeof localStorage === 'undefined') {
    throw new Error(`تعذر التحقق من ${label} لأن التخزين المحلي غير متاح.`);
  }
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) throw new Error();
    return parsed as T[];
  } catch {
    throw new Error(`تعذر التحقق من ${label} بسبب مشكلة في قراءة البيانات المحلية.`);
  }
}

function findById<T extends { id: string }>(items: T[], id: string) {
  return items.find((item) => item.id === id);
}

export interface TransactionReferenceSnapshot {
  project: Project;
  partner: Partner;
  document: Document;
}

export function validateTransactionReferences(
  input: Pick<Transaction, 'project_id' | 'partner_id' | 'document_id'>,
  transactionId?: string,
): TransactionReferenceSnapshot {
  const projectId = input.project_id.trim();
  const partnerId = input.partner_id?.trim();
  const documentId = input.document_id?.trim();

  if (!projectId) throw new Error('يجب اختيار مشروع صالح للمعاملة.');
  if (!partnerId) throw new Error('يجب ربط المعاملة بطرف أو شريك.');
  if (!documentId) throw new Error('يجب ربط المعاملة بوثيقة داعمة.');

  const project = findById(readArray<Project>(PROJECTS_KEY, 'المشاريع'), projectId);
  if (!project) throw new Error('المشروع المرتبط بالمعاملة غير موجود.');

  const partner = findById(readArray<Partner>(PARTNERS_KEY, 'الأطراف والشركاء'), partnerId);
  if (!partner) throw new Error('الطرف أو الشريك المرتبط بالمعاملة غير موجود.');

  const document = findById(readArray<Document>(DOCUMENTS_KEY, 'المستندات'), documentId);
  if (!document) throw new Error('الوثيقة الداعمة المرتبطة بالمعاملة غير موجودة.');
  if (document.project_id !== projectId) {
    throw new Error('الوثيقة الداعمة لا تنتمي إلى نفس مشروع المعاملة.');
  }
  if (document.transaction_id && document.transaction_id !== transactionId) {
    throw new Error('الوثيقة الداعمة مرتبطة بمعاملة أخرى بالفعل.');
  }

  return { project, partner, document };
}

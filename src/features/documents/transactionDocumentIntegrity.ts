import { documentsStore } from './storage';

function requireDocument(documentId: string) {
  const document = documentsStore.getAll().find((item) => item.id === documentId);
  if (!document) throw new Error('المستند المطلوب غير موجود.');
  return document;
}

export function bindSupportingDocument(documentId: string, transactionId: string) {
  const document = requireDocument(documentId);
  if (document.transaction_id && document.transaction_id !== transactionId) {
    throw new Error('الوثيقة الداعمة مرتبطة بمعاملة أخرى بالفعل.');
  }
  if (document.transaction_id === transactionId) return false;
  documentsStore.update(documentId, { transaction_id: transactionId });
  return true;
}

export function releaseSupportingDocument(documentId: string, transactionId: string) {
  const document = documentsStore.getAll().find((item) => item.id === documentId);
  if (!document || document.transaction_id !== transactionId) return false;
  documentsStore.update(documentId, { transaction_id: undefined });
  return true;
}

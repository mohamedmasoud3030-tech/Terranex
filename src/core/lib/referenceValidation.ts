/**
 * Referential integrity checks for transactions.
 *
 * These used to read `terranex.*` localStorage keys directly. After the
 * Supabase migration those keys are never written, so every lookup silently
 * saw an empty list and the checks degraded into "the project does not exist"
 * for every input. They now read the hydrated Supabase-backed stores, which
 * are the only source of truth.
 *
 * The stores are synchronous readers over a cache hydrated asynchronously, so
 * a caller that validates before hydration finishes would see an empty
 * workspace. `assertReferenceDataHydrated` fails closed in that window rather
 * than rejecting valid references.
 */
import type { Document, Partner, Project, Transaction } from '../types/domain';
import { documentsStore, documentsHydration } from '../../features/documents/storage';
import { partnersStore, partnersHydration } from '../../features/partners/storage';
import { projectsStore, projectsHydration } from '../../features/projects/storage';
import { transactionsRegistry } from '../../features/transactions/registry';

function findById<T extends { id: string }>(items: T[], id: string) {
  return items.find((item) => item.id === id);
}

function assertReferenceDataHydrated() {
  const pending = [
    projectsHydration.isLoaded() ? null : 'المشاريع',
    partnersHydration.isLoaded() ? null : 'الأطراف والشركاء',
    documentsHydration.isLoaded() ? null : 'المستندات',
  ].filter((label): label is string => Boolean(label));

  if (pending.length > 0) {
    throw new Error(
      `تعذر التحقق من المراجع لأن البيانات لم تُحمّل بعد من Supabase (${pending.join('، ')}). أعد المحاولة بعد اكتمال التحميل.`,
    );
  }

  const failed = [
    projectsHydration.getLoadError() ? 'المشاريع' : null,
    partnersHydration.getLoadError() ? 'الأطراف والشركاء' : null,
    documentsHydration.getLoadError() ? 'المستندات' : null,
  ].filter((label): label is string => Boolean(label));

  if (failed.length > 0) {
    throw new Error(
      `تعذر التحقق من المراجع بسبب فشل تحميل البيانات من Supabase (${failed.join('، ')}). لم يتم الحفظ لحماية البيانات.`,
    );
  }
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

  assertReferenceDataHydrated();

  const project = findById(projectsStore.getAll(), projectId);
  if (!project) throw new Error('المشروع المرتبط بالمعاملة غير موجود.');

  const partner = findById(partnersStore.getAll(), partnerId);
  if (!partner) throw new Error('الطرف أو الشريك المرتبط بالمعاملة غير موجود.');

  const document = findById(documentsStore.getAll(), documentId);
  if (!document) throw new Error('الوثيقة الداعمة المرتبطة بالمعاملة غير موجودة.');
  if (document.project_id !== projectId) {
    throw new Error('الوثيقة الداعمة لا تنتمي إلى نفس مشروع المعاملة.');
  }
  if (document.transaction_id && document.transaction_id !== transactionId) {
    throw new Error('الوثيقة الداعمة مرتبطة بمعاملة أخرى بالفعل.');
  }

  const conflictingTransaction = transactionsRegistry.read()
    .find((transaction) => transaction.document_id === documentId && transaction.id !== transactionId);
  if (conflictingTransaction) {
    throw new Error('الوثيقة الداعمة مستخدمة في معاملة أخرى بالفعل.');
  }

  return { project, partner, document };
}

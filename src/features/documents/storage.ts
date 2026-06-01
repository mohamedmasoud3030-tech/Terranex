import { guardDocumentDeletion } from '../../core/lib/deletionGuards';
import { isFiniteNumber } from '../../core/lib/validation';
import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import type { Document } from '../../core/types/domain';

const KEY = 'terranex.documents.v1';

function parse(raw: unknown): Document[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is Document =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.title_ar === 'string',
  ).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function makeId() {
  return `doc-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const store = createLocalStorageStore<Document[]>(KEY, [], parse);

export type DocumentInput = Omit<Document, 'id' | 'created_at'>;

function normalizeInput(input: DocumentInput): DocumentInput {
  const title = input.title_ar.trim();
  const projectId = input.project_id?.trim();
  if (!title) throw new Error('عنوان المستند مطلوب.');
  if (!projectId) throw new Error('يجب ربط المستند بمشروع.');

  const hasAnyFileMetadata = Boolean(
    input.file_url || input.file_name || input.file_mime_type || input.file_size_bytes || input.file_sha256,
  );
  if (hasAnyFileMetadata) {
    if (!input.file_url || !input.file_name || !input.file_mime_type) {
      throw new Error('بيانات الملف المحلي ناقصة أو غير صالحة.');
    }
    if (!isFiniteNumber(input.file_size_bytes) || input.file_size_bytes <= 0) {
      throw new Error('حجم الملف المحلي غير صالح.');
    }
  }

  return {
    ...input,
    title_ar: title,
    project_id: projectId,
    partner_id: input.partner_id?.trim() || undefined,
    notes: input.notes?.trim() || undefined,
  };
}

export const documentsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((d) => d.project_id === projectId),
  getByPartner: (partnerId: string) => store.get().filter((d) => d.partner_id === partnerId),
  getByTransaction: (txId: string) => store.get().filter((d) => d.transaction_id === txId),
  create: (input: DocumentInput): Document => {
    const doc: Document = { ...normalizeInput(input), id: makeId(), created_at: new Date().toISOString() };
    store.update((all) => [doc, ...all]);
    return doc;
  },
  update: (id: string, input: Partial<DocumentInput>): void => {
    store.update((all) => all.map((document) => {
      if (document.id !== id) return document;
      return { ...document, ...normalizeInput({ ...document, ...input }) };
    }));
  },
  remove: (id: string): void => {
    const guard = guardDocumentDeletion(id);
    if (!guard.canDelete) throw new Error(guard.message_ar);
    store.update((all) => all.filter((d) => d.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};

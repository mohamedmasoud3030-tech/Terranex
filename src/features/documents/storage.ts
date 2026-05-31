import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { guardDocumentDeletion } from '../../core/domain/deletionGuards';
import { operationalEventsStore } from '../events/storage';
import { obligationsStore } from '../obligations/storage';
import { transactionsStore } from '../transactions/storage';
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

export const documentsStore = {
  getAll: () => store.get(),
  getByProject: (projectId: string) => store.get().filter((d) => d.project_id === projectId),
  getByTransaction: (txId: string) => store.get().filter((d) => d.transaction_id === txId),
  create: (input: DocumentInput): Document => {
    const doc: Document = { ...input, id: makeId(), created_at: new Date().toISOString() };
    store.update((all) => [doc, ...all]);
    return doc;
  },
  update: (id: string, input: Partial<DocumentInput>): void => {
    store.update((all) => all.map((d) => d.id === id ? { ...d, ...input } : d));
  },
  remove: (id: string): void => {
    const guard = guardDocumentDeletion(id, {
      transactions: transactionsStore.getAll(),
      assets: [],
      obligations: obligationsStore.getAll(),
      documents: store.get(),
      projectPartners: [],
      operationalEvents: operationalEventsStore.getAll(),
      stockAdjustments: [],
    });
    if (!guard.allowed) throw new Error(guard.message);
    store.update((all) => all.filter((d) => d.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};

import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { guardPartnerDeletion } from '../../core/domain/deletionGuards';
import { documentsStore } from '../documents/storage';
import { obligationsStore } from '../obligations/storage';
import { transactionsStore } from '../transactions/storage';
import type { Partner, ProjectPartner } from '../../core/types/domain';

const PARTNERS_KEY = 'terranex.partners.v1';
const PROJECT_PARTNERS_KEY = 'terranex.projectPartners.v1';

function parsePartners(raw: unknown): Partner[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is Partner =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.name_ar === 'string',
  ).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function parseProjectPartners(raw: unknown): ProjectPartner[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is ProjectPartner =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.project_id === 'string' &&
      typeof r.partner_id === 'string',
  );
}

function makeId(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const pStore = createLocalStorageStore<Partner[]>(PARTNERS_KEY, [], parsePartners);
const ppStore = createLocalStorageStore<ProjectPartner[]>(PROJECT_PARTNERS_KEY, [], parseProjectPartners);

export type PartnerInput = Omit<Partner, 'id' | 'created_at'>;
export type ProjectPartnerInput = Omit<ProjectPartner, 'id'>;

export const partnersStore = {
  getAll: () => pStore.get(),
  create: (input: PartnerInput): Partner => {
    const partner: Partner = { ...input, id: makeId('prt'), created_at: new Date().toISOString() };
    pStore.update((all) => [partner, ...all]);
    return partner;
  },
  update: (id: string, input: Partial<PartnerInput>): void => {
    pStore.update((all) => all.map((p) => p.id === id ? { ...p, ...input } : p));
  },
  remove: (id: string): void => {
    const guard = guardPartnerDeletion(id, {
      transactions: transactionsStore.getAll(),
      assets: [],
      obligations: obligationsStore.getAll(),
      documents: documentsStore.getAll(),
      projectPartners: ppStore.get(),
      operationalEvents: [],
      stockAdjustments: [],
    });
    if (!guard.allowed) throw new Error(guard.message);
    pStore.update((all) => all.filter((p) => p.id !== id));
  },
  subscribe: pStore.subscribe,
  reset: pStore.reset,
};

export const projectPartnersStore = {
  getAll: () => ppStore.get(),
  getByProject: (projectId: string) => ppStore.get().filter((pp) => pp.project_id === projectId),
  create: (input: ProjectPartnerInput): ProjectPartner => {
    const pp: ProjectPartner = { ...input, id: makeId('pp') };
    ppStore.update((all) => [pp, ...all]);
    return pp;
  },
  remove: (id: string): void => {
    ppStore.update((all) => all.filter((pp) => pp.id !== id));
  },
  subscribe: ppStore.subscribe,
};

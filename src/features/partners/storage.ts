import { createSupabaseStore } from '../../core/storage/supabaseStore';
import { guardPartnerDeletion } from '../../core/lib/deletionGuards';
import type { Partner, ProjectPartner } from '../../core/types/domain';

const PARTNERS_TABLE = 'partners';
const PROJECT_PARTNERS_TABLE = 'project_partners';

function parsePartner(raw: unknown): Partner {
  return raw as Partner;
}

function parseProjectPartner(raw: unknown): ProjectPartner {
  return raw as ProjectPartner;
}

function makeId() {
  return crypto.randomUUID();
}

const pStore = createSupabaseStore<Partner>(PARTNERS_TABLE, parsePartner);
const ppStore = createSupabaseStore<ProjectPartner>(PROJECT_PARTNERS_TABLE, parseProjectPartner, 'id');

export const partnersReady = pStore.ready;
export const projectPartnersReady = ppStore.ready;

export type PartnerInput = Omit<Partner, 'id' | 'created_at'>;
export type ProjectPartnerInput = Omit<ProjectPartner, 'id'>;

export const partnersStore = {
  getAll: () => pStore.get(),
  create: (input: PartnerInput): Partner => {
    const partner: Partner = { ...input, id: makeId(), created_at: new Date().toISOString() };
    pStore.update((all) => [partner, ...all]);
    return partner;
  },
  update: (id: string, input: Partial<PartnerInput>): void => {
    pStore.update((all) => all.map((p) => p.id === id ? { ...p, ...input } : p));
  },
  remove: async (id: string): Promise<void> => {
    const guard = await guardPartnerDeletion(id);
    if (!guard.canDelete) throw new Error(guard.message_ar);
    pStore.update((all) => all.filter((p) => p.id !== id));
  },
  subscribe: pStore.subscribe,
  reset: pStore.reset,
};

export const projectPartnersStore = {
  getAll: () => ppStore.get(),
  getByProject: (projectId: string) => ppStore.get().filter((pp) => pp.project_id === projectId),
  create: (input: ProjectPartnerInput): ProjectPartner => {
    const pp: ProjectPartner = { ...input, id: makeId() };
    ppStore.update((all) => [pp, ...all]);
    return pp;
  },
  remove: (id: string): void => {
    ppStore.update((all) => all.filter((pp) => pp.id !== id));
  },
  subscribe: ppStore.subscribe,
};

import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import { guardProjectDeletion } from '../../core/lib/deletionGuards';
import type { Project } from '../../core/types/domain';

const KEY = 'terranex.projects.v1';

function parse(raw: unknown): Project[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is Project =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.name_ar === 'string' &&
      typeof r.sector_id === 'string',
  ).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

function makeId() {
  return `prj-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const store = createLocalStorageStore<Project[]>(KEY, [], parse);

export type ProjectInput = Omit<Project, 'id' | 'created_at' | 'updated_at'>;

export const projectsStore = {
  getAll: () => store.get(),
  create: (input: ProjectInput): Project => {
    const now = new Date().toISOString();
    const project: Project = { ...input, id: makeId(), created_at: now, updated_at: now };
    store.update((all) => [project, ...all]);
    return project;
  },
  update: (id: string, input: Partial<ProjectInput>): void => {
    store.update((all) =>
      all.map((p) => p.id === id ? { ...p, ...input, updated_at: new Date().toISOString() } : p),
    );
  },
  remove: (id: string): void => {
    const guard = guardProjectDeletion(id);
    if (!guard.canDelete) throw new Error(guard.message_ar);
    store.update((all) => all.filter((p) => p.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};

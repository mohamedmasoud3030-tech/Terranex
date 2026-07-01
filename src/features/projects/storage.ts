import { createSupabaseStore } from '../../core/storage/supabaseStore';
import { guardProjectDeletion } from '../../core/lib/deletionGuards';
import type { Project } from '../../core/types/domain';

const TABLE = 'projects';

function parseOne(raw: unknown): Project {
  return raw as Project;
}

function makeId() {
  return crypto.randomUUID();
}

const store = createSupabaseStore<Project>(TABLE, parseOne);

export const projectsReady = store.ready;

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
  remove: async (id: string): Promise<void> => {
    const guard = await guardProjectDeletion(id);
    if (!guard.canDelete) throw new Error(guard.message_ar);
    store.update((all) => all.filter((p) => p.id !== id));
  },
  subscribe: store.subscribe,
  reset: store.reset,
};

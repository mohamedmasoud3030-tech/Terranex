import { useCallback } from 'react';
import { useHydratedCollection } from '../../core/hooks';
import { syncProjectToOdoo } from '../../core/odoo/hooks';
import { projectsHydration, projectsStore, type ProjectInput } from './storage';
import type { Project } from '../../core/types/domain';

export function useProjects() {
  const { items: projects, status, error, retry } = useHydratedCollection<Project>(
    projectsStore,
    projectsHydration,
  );

  const createProject = useCallback(async (input: ProjectInput) => {
    const project = projectsStore.create(input);
    await projectsHydration.flush();
    void syncProjectToOdoo(project);
    return project;
  }, []);
  const updateProject = useCallback(async (id: string, input: Partial<ProjectInput>) => {
    projectsStore.update(id, input);
    await projectsHydration.flush();
    const project = projectsStore.getAll().find(item => item.id === id);
    if (project) void syncProjectToOdoo(project);
  }, []);
  const deleteProject = useCallback(async (id: string) => {
    await projectsStore.remove(id);
    await projectsHydration.flush();
  }, []);
  const resetProjects = useCallback(async () => {
    projectsStore.reset();
    await projectsHydration.flush();
  }, []);

  return { projects, createProject, updateProject, deleteProject, resetProjects, status, error, retry };
}

export function useProject(id: string) {
  const { projects } = useProjects();
  return projects.find((p) => p.id === id) ?? null;
}

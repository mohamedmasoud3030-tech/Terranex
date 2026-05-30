import { useState, useEffect, useCallback } from 'react';
import { projectsStore, type ProjectInput } from './storage';
import type { Project } from '../../core/types/domain';

export function useProjects() {
  const [projects, setProjects] = useState<Project[]>(() => projectsStore.getAll());

  useEffect(() => projectsStore.subscribe(setProjects), []);

  const createProject = useCallback((input: ProjectInput) => projectsStore.create(input), []);
  const updateProject = useCallback((id: string, input: Partial<ProjectInput>) => projectsStore.update(id, input), []);
  const deleteProject = useCallback((id: string) => projectsStore.remove(id), []);
  const resetProjects = useCallback(() => projectsStore.reset(), []);

  return { projects, createProject, updateProject, deleteProject, resetProjects };
}

export function useProject(id: string) {
  const { projects } = useProjects();
  return projects.find((p) => p.id === id) ?? null;
}

import { useState, useEffect, useCallback } from 'react';
import { projectsHydration, projectsStore, type ProjectInput } from './storage';
import type { Project } from '../../core/types/domain';

export function useProjects() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    const unsubscribe = projectsStore.subscribe((next) => {
      if (active) setProjects(next);
    });
    void projectsHydration.ready.then(() => {
      if (!active) return;
      const loadError = projectsHydration.getLoadError();
      setError(loadError);
      setStatus(loadError ? 'error' : 'ready');
      setProjects(projectsStore.getAll());
    });
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  const createProject = useCallback(async (input: ProjectInput) => {
    const project = projectsStore.create(input);
    await projectsHydration.flush();
    return project;
  }, []);
  const updateProject = useCallback(async (id: string, input: Partial<ProjectInput>) => {
    projectsStore.update(id, input);
    await projectsHydration.flush();
  }, []);
  const deleteProject = useCallback(async (id: string) => {
    await projectsStore.remove(id);
    await projectsHydration.flush();
  }, []);
  const resetProjects = useCallback(async () => {
    projectsStore.reset();
    await projectsHydration.flush();
  }, []);
  const retry = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await projectsHydration.rehydrate();
    const loadError = projectsHydration.getLoadError();
    setProjects(projectsStore.getAll());
    setError(loadError);
    setStatus(loadError ? 'error' : 'ready');
  }, []);

  return { projects, createProject, updateProject, deleteProject, resetProjects, status, error, retry };
}

export function useProject(id: string) {
  const { projects } = useProjects();
  return projects.find((p) => p.id === id) ?? null;
}

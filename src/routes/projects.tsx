import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { ProjectsPage } from '../features/projects/ProjectsPage';

export const projectsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects',
  component: ProjectsPage,
});

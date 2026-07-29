import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const projectsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects',
  beforeLoad: () => { throw redirect({ to: '/portfolio', search: { workspace: 'projects' } }); },
});

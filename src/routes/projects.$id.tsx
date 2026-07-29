import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const projectDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects/$id',
  beforeLoad: ({ params }) => { throw redirect({ to: '/portfolio/projects/$id', params: { id: params.id } }); },
});

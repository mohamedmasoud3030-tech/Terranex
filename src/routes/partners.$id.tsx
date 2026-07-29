import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const partnerDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/partners/$id',
  beforeLoad: ({ params }) => { throw redirect({ to: '/portfolio/partners/$id', params: { id: params.id } }); },
});

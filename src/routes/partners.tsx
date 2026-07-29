import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const partnersRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/partners',
  beforeLoad: () => { throw redirect({ to: '/portfolio', search: { workspace: 'partners' } }); },
});

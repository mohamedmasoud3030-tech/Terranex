import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const assetsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/assets',
  beforeLoad: () => { throw redirect({ to: '/portfolio', search: { workspace: 'assets' } }); },
});

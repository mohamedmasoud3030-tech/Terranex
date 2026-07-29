import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const agricultureRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/agriculture',
  beforeLoad: () => { throw redirect({ to: '/operations', search: { sector: 'agriculture' } }); },
});

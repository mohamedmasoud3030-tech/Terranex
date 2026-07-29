import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const livestockRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/livestock',
  beforeLoad: () => { throw redirect({ to: '/operations', search: { sector: 'livestock' } }); },
});

import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const realEstateRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/real-estate',
  beforeLoad: () => { throw redirect({ to: '/operations', search: { sector: 'real-estate' } }); },
});

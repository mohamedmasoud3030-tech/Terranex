import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const eventsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/events',
  beforeLoad: () => { throw redirect({ to: '/operations', search: { workspace: 'events' } }); },
});

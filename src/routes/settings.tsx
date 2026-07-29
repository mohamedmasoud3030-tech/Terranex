import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const settingsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/settings',
  beforeLoad: () => { throw redirect({ to: '/governance', search: { workspace: 'settings' } }); },
});

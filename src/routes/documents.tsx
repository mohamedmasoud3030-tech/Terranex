import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const documentsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/documents',
  beforeLoad: () => { throw redirect({ to: '/governance', search: { workspace: 'documents' } }); },
});

import { createRoute, redirect } from '@tanstack/react-router';
import { financeRoute } from './finance';

export const financeAllocationsRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/allocations',
  beforeLoad: () => { throw redirect({ to: '/finance', search: { workspace: 'settlements' } }); },
});

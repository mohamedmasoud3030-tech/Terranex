import { createRoute, redirect } from '@tanstack/react-router';
import { rootRoute } from './__root';

export const transactionsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/transactions',
  beforeLoad: () => { throw redirect({ to: '/finance', search: { workspace: 'transactions' } }); },
});

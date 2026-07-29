import { createRoute, redirect } from '@tanstack/react-router';
import { financeRoute } from './finance';

export const financeObligationsRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/obligations',
  beforeLoad: () => { throw redirect({ to: '/finance', search: { workspace: 'obligations' } }); },
});

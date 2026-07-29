import { createRoute, redirect } from '@tanstack/react-router';
import { financeRoute } from './finance';

export const financeProfitabilityRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/profitability',
  beforeLoad: () => { throw redirect({ to: '/intelligence', search: { workspace: 'profitability' } }); },
});

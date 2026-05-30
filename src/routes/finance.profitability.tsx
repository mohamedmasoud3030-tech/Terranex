import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { ProfitabilityPage } from '../features/finance/ProfitabilityPage';

export const financeProfitabilityRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/profitability',
  component: ProfitabilityPage,
});

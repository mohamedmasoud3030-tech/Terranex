import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { SettlementAllocationPage } from '../features/settlements/SettlementAllocationPage';

export const financeAllocationsRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/allocations',
  component: SettlementAllocationPage,
});

import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { ObligationsPage } from '../features/obligations/ObligationsPage';

export const financeObligationsRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/obligations',
  component: ObligationsPage,
});

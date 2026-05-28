import { createRoute, redirect } from '@tanstack/react-router';
import { financeRoute } from './finance';

export const financeIndexRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/',
  beforeLoad: () => { throw redirect({ to: '/finance/obligations' }); },
});

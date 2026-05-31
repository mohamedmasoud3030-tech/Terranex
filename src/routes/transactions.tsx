import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { TransactionsPage } from '../features/transactions/TransactionsPage';

export const transactionsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/transactions',
  component: TransactionsPage,
});

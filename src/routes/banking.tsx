import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { BankingPage } from '../features/banking/BankingPage';

export const bankingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/banking',
  validateSearch: (search: Record<string, unknown>) => ({
    account: typeof search.account === 'string' ? search.account : undefined,
  }),
  component: BankingPage,
});

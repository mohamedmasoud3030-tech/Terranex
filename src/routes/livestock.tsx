import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { LivestockPage } from '../features/livestock/LivestockPage';

export const livestockRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/livestock',
  component: LivestockPage,
});

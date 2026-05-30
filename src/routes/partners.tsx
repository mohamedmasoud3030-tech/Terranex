import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { PartnersPage } from '../features/partners/PartnersPage';

export const partnersRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/partners',
  component: PartnersPage,
});

import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { VatReturnPage } from '../features/finance/VatReturnPage';

export const vatReturnRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/vat-return',
  component: VatReturnPage,
});

import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { InvoicingPage } from '../features/invoicing/InvoicingPage';

export const invoicingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/invoicing',
  component: InvoicingPage,
});

/**
 * Route tree — manual TanStack Router v1 setup (no Vite plugin / codegen).
 *
 * Hierarchy:
 *   rootRoute
 *     indexRoute          /          → redirect /dashboard
 *     dashboardRoute      /dashboard
 *     realEstateRoute     /real-estate
 *     agricultureRoute    /agriculture
 *     livestockRoute      /livestock
 *     financeRoute        /finance
 *       financeIndexRoute       /          → redirect /finance/obligations
 *       financeObligationsRoute /obligations
 *       financeAllocationsRoute /allocations
 *       financeProfitabilityRoute /profitability
 *     documentsRoute      /documents
 *     partnersRoute       /partners
 *     partnerDetailRoute  /partners/$id
 *     transactionsRoute   /transactions
 *     assetsRoute         /assets
 *     settingsRoute       /settings
 *     notFoundRoute       /404
 */

import { createRouter } from '@tanstack/react-router';
import { QueryClient } from '@tanstack/react-query';

import { rootRoute } from './routes/__root';
import { indexRoute } from './routes/index';
import { dashboardRoute } from './routes/dashboard';
import { realEstateRoute } from './routes/real-estate';
import { agricultureRoute } from './routes/agriculture';
import { livestockRoute } from './routes/livestock';
import { financeRoute } from './routes/finance';
import { financeIndexRoute } from './routes/finance.index';
import { financeObligationsRoute } from './routes/finance.obligations';
import { financeAllocationsRoute } from './routes/finance.allocations';
import { financeProfitabilityRoute } from './routes/finance.profitability';
import { documentsRoute } from './routes/documents';
import { partnersRoute } from './routes/partners';
import { partnerDetailRoute } from './routes/partners.$id';
import { transactionsRoute } from './routes/transactions';
import { assetsRoute } from './routes/assets';
import { settingsRoute } from './routes/settings';
import { notFoundRoute } from './routes/404';
import { projectsRoute } from './routes/projects';
import { projectDetailRoute } from './routes/projects.$id';
import { NotFoundPage } from './routes/404';

const financeTree = financeRoute.addChildren([
  financeIndexRoute,
  financeObligationsRoute,
  financeAllocationsRoute,
  financeProfitabilityRoute,
]);

const routeTree = rootRoute.addChildren([
  indexRoute,
  dashboardRoute,
  projectsRoute,
  projectDetailRoute,
  realEstateRoute,
  agricultureRoute,
  livestockRoute,
  financeTree,
  transactionsRoute,
  assetsRoute,
  documentsRoute,
  partnersRoute,
  partnerDetailRoute,
  settingsRoute,
  notFoundRoute,
]);

export function createAppRouter(queryClient: QueryClient) {
  return createRouter({
    routeTree,
    context: { queryClient },
    defaultNotFoundComponent: NotFoundPage,
  });
}

declare module '@tanstack/react-router' {
  interface Register {
    router: ReturnType<typeof createAppRouter>;
  }
}

/**
 * Route tree — manual TanStack Router v1 setup (no Vite plugin / codegen).
 *
 * Hierarchy:
 *   rootRoute
 *     indexRoute          /          → redirect /dashboard
 *     dashboardRoute      /dashboard
 *     portfolioRoute      /portfolio
 *     operationsRoute     /operations
 *     financeRoute        /finance
 *     intelligenceRoute   /intelligence
 *     governanceRoute     /governance
 *     legacy routes       redirect while preserving intent
 *     notFoundRoute       /404
 */

import { createRouter } from '@tanstack/react-router';
import { QueryClient } from '@tanstack/react-query';

import { rootRoute } from './routes/__root';
import { indexRoute } from './routes/index';
import { dashboardRoute } from './routes/dashboard';
import { portfolioRoute } from './routes/portfolio';
import { portfolioProjectDetailRoute } from './routes/portfolio.projects.$id';
import { portfolioPartnerDetailRoute } from './routes/portfolio.partners.$id';
import { bankingRoute } from './routes/banking';
import { invoicingRoute } from './routes/invoicing';
import { operationsRoute } from './routes/operations';
import { intelligenceRoute } from './routes/intelligence';
import { governanceRoute } from './routes/governance';
import { realEstateRoute } from './routes/real-estate';
import { agricultureRoute } from './routes/agriculture';
import { livestockRoute } from './routes/livestock';
import { financeRoute } from './routes/finance';
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
import { eventsRoute } from './routes/events';
import { NotFoundPage } from './routes/404';

const financeTree = financeRoute.addChildren([
  financeObligationsRoute,
  financeAllocationsRoute,
  financeProfitabilityRoute,
]);

const routeTree = rootRoute.addChildren([
  indexRoute,
  dashboardRoute,
  portfolioRoute,
  portfolioProjectDetailRoute,
  portfolioPartnerDetailRoute,
  bankingRoute,
  invoicingRoute,
  operationsRoute,
  projectsRoute,
  projectDetailRoute,
  realEstateRoute,
  agricultureRoute,
  livestockRoute,
  eventsRoute,
  financeTree,
  intelligenceRoute,
  governanceRoute,
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

import { createRoute, useRouter } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { PortfolioHub } from '../features/portfolio';
import { portfolioHandoffTarget } from '../features/integration';
import { validatePortfolioSearch } from '../core/routing/hubSearch';

export const portfolioRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/portfolio',
  validateSearch: validatePortfolioSearch,
  component: PortfolioRouteComponent,
});

function PortfolioRouteComponent() {
  const router = useRouter();
  return <PortfolioHub onHandoff={(handoff) => void router.navigate(portfolioHandoffTarget(handoff) as never)} />;
}

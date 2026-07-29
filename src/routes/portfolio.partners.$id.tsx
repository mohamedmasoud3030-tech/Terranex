import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { PartnerDetailPage } from '../features/partners/PartnerDetailPage';

export const portfolioPartnerDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/portfolio/partners/$id',
  component: PortfolioPartnerDetailRoute,
});

function PortfolioPartnerDetailRoute() {
  const { id } = portfolioPartnerDetailRoute.useParams();
  return <PartnerDetailPage partnerId={id} />;
}

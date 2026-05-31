import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { PartnerDetailPage } from '../features/partners/PartnerDetailPage';

export const partnerDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/partners/$id',
  component: PartnerDetailRouteComponent,
});

function PartnerDetailRouteComponent() {
  const { id } = partnerDetailRoute.useParams();
  return <PartnerDetailPage partnerId={id} />;
}

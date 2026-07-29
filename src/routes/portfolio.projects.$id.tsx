import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { ProjectDetailPage } from '../features/projects/ProjectDetailPage';

export const portfolioProjectDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/portfolio/projects/$id',
  component: PortfolioProjectDetailRoute,
});

function PortfolioProjectDetailRoute() {
  const { id } = portfolioProjectDetailRoute.useParams();
  return <ProjectDetailPage projectId={id} />;
}

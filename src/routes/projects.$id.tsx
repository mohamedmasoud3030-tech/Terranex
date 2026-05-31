import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { ProjectDetailPage } from '../features/projects/ProjectDetailPage';

export const projectDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects/$id',
  component: ProjectDetailRouteComponent,
});

function ProjectDetailRouteComponent() {
  const { id } = projectDetailRoute.useParams();
  return <ProjectDetailPage projectId={id} />;
}

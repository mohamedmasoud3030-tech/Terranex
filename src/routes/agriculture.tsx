import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { AgriculturePage } from '../features/agriculture/AgriculturePage';

export const agricultureRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/agriculture',
  component: AgriculturePage,
});

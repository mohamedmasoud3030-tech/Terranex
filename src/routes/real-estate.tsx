import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { RealEstatePage } from '../features/real-estate/RealEstatePage';

export const realEstateRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/real-estate',
  component: RealEstatePage,
});

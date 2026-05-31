import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { AssetsPage } from '../features/assets/AssetsPage';

export const assetsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/assets',
  component: AssetsPage,
});

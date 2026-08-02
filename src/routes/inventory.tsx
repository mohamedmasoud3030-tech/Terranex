import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { InventoryPage } from '../features/inventory/InventoryPage';

export const inventoryRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/inventory',
  component: InventoryPage,
});

import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { Wheat } from 'lucide-react';
import { PlaceholderPage } from './_placeholder';

export const agricultureRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/agriculture',
  component: () => (
    <PlaceholderPage titleKey="sector_agriculture_name" descriptionKey="sector_agriculture_desc" icon={Wheat} />
  ),
});

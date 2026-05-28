import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { Building2 } from 'lucide-react';
import { PlaceholderPage } from './_placeholder';

export const realEstateRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/real-estate',
  component: () => (
    <PlaceholderPage titleKey="sector_real_estate_name" descriptionKey="sector_real_estate_desc" icon={Building2} />
  ),
});

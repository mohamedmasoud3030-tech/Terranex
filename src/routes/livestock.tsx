import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { PawPrint } from 'lucide-react';
import { PlaceholderPage } from './_placeholder';

export const livestockRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/livestock',
  component: () => (
    <PlaceholderPage titleKey="sector_livestock_name" descriptionKey="sector_livestock_desc" icon={PawPrint} />
  ),
});

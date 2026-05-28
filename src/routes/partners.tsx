import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { Users } from 'lucide-react';
import { PlaceholderPage } from './_placeholder';

export const partnersRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/partners',
  component: () => <PlaceholderPage titleKey="nav_partners" descriptionKey="sector_finance_desc" icon={Users} />,
});

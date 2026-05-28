import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { FolderOpen } from 'lucide-react';
import { PlaceholderPage } from './_placeholder';

export const documentsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/documents',
  component: () => <PlaceholderPage titleKey="nav_documents" descriptionKey="state_no_documents_desc" icon={FolderOpen} />,
});

import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { DocumentsPage } from '../features/documents/DocumentsPage';

export const documentsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/documents',
  component: DocumentsPage,
});

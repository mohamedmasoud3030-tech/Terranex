import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { JournalPage } from '../features/finance/JournalPage';

export const journalRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/journal',
  component: JournalPage,
});

import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { EventsPage } from '../features/events/EventsPage';
import { FeatureErrorBoundary } from '../components/ui/ErrorBoundary';

function EventsRouteComponent() {
  return (
    <FeatureErrorBoundary feature="events">
      <EventsPage />
    </FeatureErrorBoundary>
  );
}

export const eventsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/events',
  component: EventsRouteComponent,
});

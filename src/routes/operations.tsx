import { createRoute, useRouter } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { OperationsHub } from '../features/operations';
import { operationsHandoffTarget } from '../features/integration';
import { validateOperationsSearch } from '../core/routing/hubSearch';

export const operationsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/operations',
  validateSearch: validateOperationsSearch,
  component: OperationsRouteComponent,
});

function OperationsRouteComponent() {
  const router = useRouter();
  return <OperationsHub onHandoff={(handoff) => void router.navigate(operationsHandoffTarget(handoff) as never)} />;
}

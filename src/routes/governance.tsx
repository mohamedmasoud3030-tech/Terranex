import { createRoute, useRouter } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { GovernanceHub } from '../features/governance';
import { governanceHandoffTarget } from '../features/integration';
import { validateGovernanceSearch } from '../core/routing/hubSearch';

export const governanceRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/governance',
  validateSearch: validateGovernanceSearch,
  component: GovernanceRouteComponent,
});

function GovernanceRouteComponent() {
  const router = useRouter();
  return <GovernanceHub onHandoff={(handoff) => void router.navigate(governanceHandoffTarget(handoff) as never)} />;
}

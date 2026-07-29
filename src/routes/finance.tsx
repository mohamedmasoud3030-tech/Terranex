import { createRoute, useRouter } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { FinanceHub } from '../features/finance';
import { financeHandoffTarget } from '../features/integration';
import { validateFinanceSearch } from '../core/routing/hubSearch';

export const financeRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/finance',
  validateSearch: validateFinanceSearch,
  component: FinanceRouteComponent,
});

function FinanceRouteComponent() {
  const router = useRouter();
  return <FinanceHub onHandoff={(handoff) => void router.navigate(financeHandoffTarget(handoff) as never)} />;
}

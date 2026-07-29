import { createRoute, useRouter } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { IntelligenceHub } from '../features/intelligence';
import { intelligenceFinanceTarget } from '../features/integration';
import { validateIntelligenceSearch } from '../core/routing/hubSearch';

export const intelligenceRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/intelligence',
  validateSearch: validateIntelligenceSearch,
  component: IntelligenceRouteComponent,
});

function IntelligenceRouteComponent() {
  const router = useRouter();
  return <IntelligenceHub onFinanceDrillDown={(context) => void router.navigate(intelligenceFinanceTarget(context) as never)} />;
}

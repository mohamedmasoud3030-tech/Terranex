import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { useI18n } from '../core/i18n';
import { EmptyState } from '../components/ui/States';
import { TrendingUp } from 'lucide-react';

export const financeProfitabilityRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/profitability',
  component: ProfitabilityPage,
});

function ProfitabilityPage() {
  const { t } = useI18n();
  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-info/30 bg-info/5 p-4">
        <p className="text-sm font-semibold text-info">{t('profit_formula')}</p>
      </div>
      <EmptyState title={t('profit_label')} description={t('state_empty_description')} icon={TrendingUp} action={{ label: t('action_add_record'), onClick: () => {} }} />
    </div>
  );
}

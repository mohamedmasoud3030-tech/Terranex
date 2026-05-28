import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { ObligationsTable } from '../components/domain/ObligationsTable';
import { EmptyState } from '../components/ui/States';
import { useI18n } from '../core/i18n';
import { obligationRows } from '../data/fixtures';

export const financeObligationsRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/obligations',
  component: ObligationsPage,
});

function ObligationsPage() {
  const { t } = useI18n();
  return (
    <section className="rounded-3xl border border-border bg-card p-4 shadow-sm">
      {obligationRows.length === 0 ? (
        <EmptyState title={t('state_empty_title')} description={t('state_empty_description')} action={{ label: t('action_add_record'), onClick: () => {} }} />
      ) : (
        <ObligationsTable data={obligationRows} />
      )}
    </section>
  );
}

import { useI18n } from '../../core/i18n';
import { usePeriodFilter } from '../../core/hooks';
import { PageHeader } from '../../components/layout/PageHeader';
import { KpiCard } from '../../components/domain/KpiCard';
import { SectorCard } from '../../components/domain/SectorCard';
import { ObligationsTable } from '../../components/domain/ObligationsTable';
import { PeriodFilter } from '../../components/ui/PeriodFilter';
import { EmptyState } from '../../components/ui/States';
import { dashboardKpis, sectorCards, obligationRows } from '../../data/fixtures';

export function DashboardPage() {
  const { t } = useI18n();
  const { period, setPeriod } = usePeriodFilter('quarter');

  return (
    <>
      <PageHeader
        title={t('dashboard_title')}
        description={t('dashboard_description')}
        action={{ label: t('action_add_record'), onClick: () => {} }}
      />

      {/* Period filter */}
      <section
        aria-labelledby="period-section"
        className="mb-6 rounded-3xl border border-border bg-card p-4"
      >
        <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <h2 id="period-section" className="text-lg font-bold">
              {t('dashboard_period_label')}
            </h2>
            <p className="mt-1 text-sm text-muted-foreground">
              {t('dashboard_period_note')}
            </p>
          </div>
          <PeriodFilter value={period} onChange={setPeriod} />
        </div>
      </section>

      {/* KPI row */}
      <section aria-labelledby="kpi-section" className="mb-6">
        <h2 id="kpi-section" className="sr-only">{t('kpi_net_profit')}</h2>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {dashboardKpis.map((kpi) => (
            <KpiCard kpi={kpi} key={kpi.id} />
          ))}
        </div>
      </section>

      {/* Sectors */}
      <section aria-labelledby="sectors-section" className="mb-6">
        <div className="mb-4 flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
          <h2 id="sectors-section" className="text-xl font-bold">
            القطاعات الاستثمارية
          </h2>
        </div>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {sectorCards.map((sector) => (
            <SectorCard sector={sector} key={sector.id} />
          ))}
        </div>
      </section>

      {/* Obligations table */}
      <section
        aria-labelledby="obligations-section"
        className="mb-6 rounded-3xl border border-border bg-card p-4 shadow-sm"
      >
        <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <h2 id="obligations-section" className="text-xl font-bold">
              {t('obligations_title')}
            </h2>
            <p className="mt-1 text-sm text-muted-foreground">
              {t('obligations_description')}
            </p>
          </div>
        </div>

        {obligationRows.length === 0 ? (
          <EmptyState
            title={t('state_empty_title')}
            description={t('state_empty_description')}
          />
        ) : (
          <ObligationsTable data={obligationRows} />
        )}
      </section>

      {/* Documents placeholder */}
      <section className="mb-6">
        <EmptyState
          title={t('state_no_documents')}
          description={t('state_no_documents_desc')}
          action={{ label: t('action_add_record'), onClick: () => {} }}
        />
      </section>
    </>
  );
}

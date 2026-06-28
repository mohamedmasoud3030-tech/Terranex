import { createRoute, Outlet, useLocation, useRouter } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { useI18n } from '../core/i18n';
import { PageHeader } from '../components/layout/PageHeader';
import { cn } from '../core/lib/cn';

export const financeRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/finance',
  component: FinanceLayout,
});

const TABS = [
  { to: '/finance/obligations', label_ar: 'السجلات المالية', label_en: 'Financial records' },
  { to: '/finance/allocations', label_ar: 'دفعات موزعة', label_en: 'Allocations' },
  { to: '/finance/profitability', label_ar: 'الربحية', label_en: 'Profitability' },
] as const;

function FinanceLayout() {
  const { t, locale } = useI18n();
  const { pathname } = useLocation();
  const router = useRouter();

  return (
    <>
      <PageHeader title={t('sector_finance_name')} description={t('sector_finance_desc')} />
      <nav
        className="mb-6 flex gap-1 rounded-2xl border border-border bg-card p-1"
        aria-label={locale === 'ar' ? 'تنقل المالية' : 'Finance navigation'}
      >
        {TABS.map((tab) => {
          const isActive = pathname.startsWith(tab.to);
          return (
            <button
              key={tab.to}
              onClick={() => router.navigate({ to: tab.to })}
              className={cn(
                'flex-1 rounded-xl px-4 py-2.5 text-center text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
                isActive ? 'bg-primary text-white shadow-sm' : 'text-muted-foreground hover:bg-muted hover:text-foreground',
              )}
              aria-current={isActive ? 'page' : undefined}
            >
              {locale === 'ar' ? tab.label_ar : tab.label_en}
            </button>
          );
        })}
      </nav>
      <Outlet />
    </>
  );
}

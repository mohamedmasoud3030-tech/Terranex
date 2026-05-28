import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { useI18n } from '../core/i18n';
import { PageHeader } from '../components/layout/PageHeader';
import { Card, CardContent } from '../components/ui/Card';
import type { Locale } from '../core/types';

export const settingsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/settings',
  component: SettingsPage,
});

const LOCALES: { value: Locale; label: string }[] = [
  { value: 'ar', label: 'العربية (RTL)' },
  { value: 'en', label: 'English (LTR)' },
];

function SettingsPage() {
  const { t, locale, setLocale } = useI18n();
  return (
    <>
      <PageHeader title={t('nav_settings')} />
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardContent>
            <h3 className="mb-4 text-lg font-bold">{locale === 'ar' ? 'اللغة والاتجاه' : 'Language & Direction'}</h3>
            <div className="flex flex-col gap-2">
              {LOCALES.map((l) => (
                <button key={l.value} onClick={() => setLocale(l.value)}
                  className={['flex items-center justify-between rounded-xl border px-4 py-3 text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
                    locale === l.value ? 'border-primary bg-primary/10 text-primary' : 'border-border bg-card text-muted-foreground hover:bg-muted hover:text-foreground'].join(' ')}
                  aria-pressed={locale === l.value}>
                  {l.label}
                  {locale === l.value && <span className="text-xs opacity-60">{locale === 'ar' ? 'نشط' : 'Active'}</span>}
                </button>
              ))}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <h3 className="mb-2 text-lg font-bold">{locale === 'ar' ? 'عملة التقارير' : 'Reporting Currency'}</h3>
            <p className="mb-4 text-sm leading-7 text-muted-foreground">
              {locale === 'ar' ? 'الجنيه المصري (EGP) هو العملة الأساسية لجميع تقارير الربحية الموحدة.' : 'Egyptian Pound (EGP) is the base currency for all consolidated P&L reporting.'}
            </p>
            <div className="rounded-2xl border border-border bg-muted p-3 text-center">
              <span className="text-2xl font-bold">EGP — ج.م</span>
            </div>
          </CardContent>
        </Card>
      </div>
    </>
  );
}

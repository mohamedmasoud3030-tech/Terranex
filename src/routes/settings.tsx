import { createRoute } from '@tanstack/react-router';
import { Monitor, Moon, Sun } from 'lucide-react';
import { rootRoute } from './__root';
import { useI18n } from '../core/i18n';
import { useTheme, type ThemeMode } from '../core/theme';
import { PageHeader } from '../components/layout/PageHeader';
import { Card, CardContent } from '../components/ui/Card';
import { BackupRestoreSection } from '../features/settings/BackupRestoreSection';
import { ExchangeRateSection } from '../features/settings/ExchangeRateSection';
import { useAuth } from '../core/auth/AuthProvider';
import { Button } from '../components/ui/Button';
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

const THEME_OPTIONS: Array<{
  value: ThemeMode;
  labelAr: string;
  labelEn: string;
  descriptionAr: string;
  descriptionEn: string;
  icon: typeof Sun;
}> = [
  {
    value: 'light',
    labelAr: 'الوضع النهاري',
    labelEn: 'Light mode',
    descriptionAr: 'خلفيات فاتحة ووضوح مرتفع للاستخدام اليومي.',
    descriptionEn: 'Bright surfaces and clear contrast for daytime use.',
    icon: Sun,
  },
  {
    value: 'dark',
    labelAr: 'الوضع الليلي',
    labelEn: 'Dark mode',
    descriptionAr: 'ألوان داكنة هادئة مناسبة للإضاءة المنخفضة.',
    descriptionEn: 'Calm dark surfaces for low-light environments.',
    icon: Moon,
  },
  {
    value: 'system',
    labelAr: 'اتباع إعداد الجهاز',
    labelEn: 'Use system setting',
    descriptionAr: 'يتغير المظهر تلقائيًا وفق إعداد النظام.',
    descriptionEn: 'Automatically follows the operating system preference.',
    icon: Monitor,
  },
];

function AccountSection() {
  const { user, signOut } = useAuth();
  return (
    <Card>
      <CardContent className="space-y-3 p-6">
        <h2 className="text-sm font-semibold text-foreground">الحساب</h2>
        <p className="text-sm text-muted-foreground">مسجل الدخول باسم: {user?.email}</p>
        <Button variant="secondary" onClick={() => signOut()}>تسجيل الخروج</Button>
      </CardContent>
    </Card>
  );
}

function SettingsPage() {
  const { t, locale, setLocale } = useI18n();
  const { mode, setMode } = useTheme();

  return (
    <>
      <PageHeader title={t('nav_settings')} />
      <div className="grid gap-4 xl:grid-cols-3">
        <Card>
          <CardContent>
            <h3 className="mb-4 text-lg font-bold">{locale === 'ar' ? 'اللغة والاتجاه' : 'Language & Direction'}</h3>
            <div className="flex flex-col gap-2">
              {LOCALES.map((item) => (
                <button
                  key={item.value}
                  onClick={() => setLocale(item.value)}
                  className={[
                    'flex min-h-12 items-center justify-between rounded-xl border px-4 py-3 text-start text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
                    locale === item.value
                      ? 'border-primary bg-primary/10 text-primary'
                      : 'border-border bg-card/70 text-muted-foreground hover:bg-muted hover:text-foreground',
                  ].join(' ')}
                  aria-pressed={locale === item.value}
                >
                  {item.label}
                  {locale === item.value && <span className="text-xs opacity-70">{locale === 'ar' ? 'نشط' : 'Active'}</span>}
                </button>
              ))}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent>
            <h3 className="mb-4 text-lg font-bold">{locale === 'ar' ? 'المظهر' : 'Appearance'}</h3>
            <div className="flex flex-col gap-2">
              {THEME_OPTIONS.map((item) => {
                const Icon = item.icon;
                const isActive = mode === item.value;
                return (
                  <button
                    key={item.value}
                    onClick={() => setMode(item.value)}
                    className={[
                      'flex min-h-14 items-start gap-3 rounded-xl border px-4 py-3 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
                      isActive
                        ? 'border-primary bg-primary/10 text-primary'
                        : 'border-border bg-card/70 text-muted-foreground hover:bg-muted hover:text-foreground',
                    ].join(' ')}
                    aria-pressed={isActive}
                  >
                    <Icon className="mt-0.5 h-5 w-5 shrink-0" aria-hidden="true" />
                    <span>
                      <span className="block text-sm font-bold">{locale === 'ar' ? item.labelAr : item.labelEn}</span>
                      <span className="mt-1 block text-xs leading-5 opacity-80">
                        {locale === 'ar' ? item.descriptionAr : item.descriptionEn}
                      </span>
                    </span>
                  </button>
                );
              })}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent>
            <h3 className="mb-2 text-lg font-bold">{locale === 'ar' ? 'عملة التقارير' : 'Reporting Currency'}</h3>
            <p className="mb-4 text-sm leading-7 text-muted-foreground">
              {locale === 'ar'
                ? 'الجنيه المصري (EGP) هو العملة الأساسية لجميع تقارير الربحية الموحدة.'
                : 'Egyptian Pound (EGP) is the base currency for all consolidated P&L reporting.'}
            </p>
            <div className="rounded-2xl border border-border bg-muted p-3 text-center">
              <span className="text-2xl font-bold">EGP — ج.م</span>
            </div>
          </CardContent>
        </Card>

        <BackupRestoreSection locale={locale} />
        <ExchangeRateSection locale={locale} />
        <AccountSection />
      </div>
    </>
  );
}

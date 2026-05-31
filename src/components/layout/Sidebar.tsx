import { useRouter, useLocation } from '@tanstack/react-router';
import { useI18n } from '../../core/i18n';
import { cn } from '../../core/lib/cn';
import { getNavItemLabel, isNavItemActive, NAV_ITEMS } from './navigation';

export function Sidebar() {
  const { t, locale } = useI18n();
  const router = useRouter();
  const { pathname } = useLocation();

  return (
    <aside className="surface-glass hidden w-72 shrink-0 border-s px-4 py-5 lg:block">
      <div className="mb-8 rounded-2xl border border-border bg-card/60 p-4 shadow-sm">
        <p className="text-xs font-medium text-muted-foreground">{t('env_badge')}</p>
        <h1 className="mt-2 text-xl font-extrabold tracking-tight text-foreground">{t('app_tagline')}</h1>
      </div>

      <nav aria-label={locale === 'ar' ? 'التنقل الرئيسي' : 'Main navigation'}>
        <ul className="space-y-1" role="list">
          {NAV_ITEMS.map((item) => {
            const Icon = item.icon;
            const isActive = isNavItemActive(pathname, item);
            return (
              <li key={item.id}>
                <button
                  onClick={() => router.navigate({ to: item.to })}
                  className={cn(
                    'flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-3 text-start text-sm font-semibold transition duration-200 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary',
                    isActive
                      ? 'bg-primary text-primary-foreground shadow-sm'
                      : 'text-muted-foreground hover:bg-muted hover:text-foreground',
                  )}
                  aria-current={isActive ? 'page' : undefined}
                >
                  <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
                  <span>{getNavItemLabel(item, locale)}</span>
                </button>
              </li>
            );
          })}
        </ul>
      </nav>
    </aside>
  );
}

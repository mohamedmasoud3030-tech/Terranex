import { useState } from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { useLocation, useRouter } from '@tanstack/react-router';
import { Menu, Moon, Sun, X } from 'lucide-react';

import { useI18n } from '../../core/i18n';
import { useTheme } from '../../core/theme';
import { cn } from '../../core/lib/cn';
import { getNavItemLabel, isNavItemActive, NAV_ITEMS } from './navigation';

export function TopBar() {
  const { t, locale, setLocale } = useI18n();
  const { resolvedTheme, setMode } = useTheme();
  const router = useRouter();
  const { pathname } = useLocation();
  const [isMobileNavOpen, setIsMobileNavOpen] = useState(false);

  function navigateFromMobileMenu(to: string) {
    router.navigate({ to });
    setIsMobileNavOpen(false);
  }

  function toggleTheme() {
    setMode(resolvedTheme === 'dark' ? 'light' : 'dark');
  }

  const themeLabel = resolvedTheme === 'dark'
    ? (locale === 'ar' ? 'تفعيل الوضع النهاري' : 'Switch to light mode')
    : (locale === 'ar' ? 'تفعيل الوضع الليلي' : 'Switch to dark mode');

  return (
    <header className="surface-glass sticky top-0 z-30 border-b px-4 py-3 lg:px-8">
      <div className="mx-auto flex w-full max-w-[1440px] flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-xs font-medium text-muted-foreground">{t('env_badge')}</p>
          <p className="mt-1 text-sm font-bold text-foreground">{t('app_name')} — {t('app_tagline')}</p>
        </div>

        <div className="flex items-center gap-2 sm:gap-3">
          <Dialog.Root open={isMobileNavOpen} onOpenChange={setIsMobileNavOpen}>
            <Dialog.Trigger asChild>
              <button
                className="inline-flex h-11 items-center gap-2 rounded-xl bg-primary px-3 text-sm font-semibold text-primary-foreground shadow-sm transition hover:bg-primary/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary lg:hidden"
                aria-label={locale === 'ar' ? 'فتح التنقل الرئيسي' : 'Open main navigation'}
              >
                <Menu className="h-5 w-5" aria-hidden="true" />
                <span>{locale === 'ar' ? 'القائمة' : 'Menu'}</span>
              </button>
            </Dialog.Trigger>
            <Dialog.Portal>
              <Dialog.Overlay className="fixed inset-0 z-40 bg-slate-950/55 backdrop-blur-sm lg:hidden" />
              <Dialog.Content className="surface-glass fixed inset-y-0 end-0 z-50 flex w-[min(22rem,calc(100vw-1.5rem))] flex-col overflow-y-auto border-s p-4 focus-visible:outline-none lg:hidden">
                <div className="mb-5 flex items-start justify-between gap-3 rounded-2xl border border-border bg-card/70 p-4 shadow-sm">
                  <div>
                    <Dialog.Title className="text-base font-bold text-foreground">
                      {locale === 'ar' ? 'تنقل Terranex' : 'Terranex navigation'}
                    </Dialog.Title>
                    <Dialog.Description className="mt-1 text-xs leading-6 text-muted-foreground">
                      {locale === 'ar'
                        ? 'انتقل بين أقسام نظام التشغيل الاستثماري.'
                        : 'Move between investment operating system sections.'}
                    </Dialog.Description>
                  </div>
                  <Dialog.Close asChild>
                    <button
                      className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-border bg-card/80 text-muted-foreground transition hover:bg-muted hover:text-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                      aria-label={t('action_close')}
                    >
                      <X className="h-5 w-5" aria-hidden="true" />
                    </button>
                  </Dialog.Close>
                </div>

                <nav aria-label={locale === 'ar' ? 'التنقل الرئيسي للجوال' : 'Mobile main navigation'}>
                  <ul className="space-y-2" role="list">
                    {NAV_ITEMS.map((item) => {
                      const Icon = item.icon;
                      const isActive = isNavItemActive(pathname, item);

                      return (
                        <li key={item.id}>
                          <button
                            onClick={() => navigateFromMobileMenu(item.to)}
                            className={cn(
                              'flex min-h-12 w-full items-center gap-3 rounded-2xl px-4 py-3 text-start text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
                              isActive
                                ? 'bg-primary text-primary-foreground shadow-sm'
                                : 'border border-border bg-card/70 text-foreground hover:bg-muted',
                            )}
                            aria-current={isActive ? 'page' : undefined}
                          >
                            <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
                            <span className="min-w-0 whitespace-normal leading-6">{getNavItemLabel(item, locale)}</span>
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                </nav>
              </Dialog.Content>
            </Dialog.Portal>
          </Dialog.Root>

          <button
            onClick={toggleTheme}
            className="inline-flex h-11 w-11 items-center justify-center rounded-xl border border-border bg-card/80 text-muted-foreground shadow-sm transition hover:bg-muted hover:text-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            aria-label={themeLabel}
            title={themeLabel}
          >
            {resolvedTheme === 'dark'
              ? <Sun className="h-5 w-5" aria-hidden="true" />
              : <Moon className="h-5 w-5" aria-hidden="true" />}
          </button>

          <button
            onClick={() => setLocale(locale === 'ar' ? 'en' : 'ar')}
            className="h-11 rounded-xl border border-border bg-card/80 px-3 text-sm font-semibold text-muted-foreground shadow-sm transition hover:bg-muted hover:text-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            aria-label="Toggle language"
          >
            {locale === 'ar' ? 'EN' : 'عر'}
          </button>
        </div>
      </div>
    </header>
  );
}

import { useState } from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { useLocation, useRouter } from '@tanstack/react-router';
import { Menu, X } from 'lucide-react';

import { useI18n } from '../../core/i18n';
import { cn } from '../../core/lib/cn';
import { getNavItemLabel, isNavItemActive, NAV_ITEMS } from './navigation';

export function TopBar() {
  const { t, locale, setLocale } = useI18n();
  const router = useRouter();
  const { pathname } = useLocation();
  const [isMobileNavOpen, setIsMobileNavOpen] = useState(false);

  function navigateFromMobileMenu(to: string) {
    router.navigate({ to });
    setIsMobileNavOpen(false);
  }

  return (
    <header className="sticky top-0 z-10 border-b border-border bg-card/95 px-4 py-3 backdrop-blur lg:px-8">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-xs text-muted-foreground">{t('env_badge')}</p>
          <p className="text-sm font-semibold">{t('app_name')} — {t('app_tagline')}</p>
        </div>

        <div className="flex items-center gap-3">
          <Dialog.Root open={isMobileNavOpen} onOpenChange={setIsMobileNavOpen}>
            <Dialog.Trigger asChild>
              <button
                className="inline-flex h-11 items-center gap-2 rounded-xl border border-border bg-primary px-3 text-sm font-semibold text-white transition hover:bg-primary/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary lg:hidden"
                aria-label={locale === 'ar' ? 'فتح التنقل الرئيسي' : 'Open main navigation'}
              >
                <Menu className="h-5 w-5" aria-hidden="true" />
                <span>{locale === 'ar' ? 'القائمة' : 'Menu'}</span>
              </button>
            </Dialog.Trigger>
            <Dialog.Portal>
              <Dialog.Overlay className="fixed inset-0 z-40 bg-slate-950/45 backdrop-blur-sm lg:hidden" />
              <Dialog.Content className="fixed inset-y-0 end-0 z-50 flex w-[min(22rem,calc(100vw-1.5rem))] flex-col overflow-y-auto border-s border-border bg-card p-4 shadow-2xl focus-visible:outline-none lg:hidden">
                <div className="mb-5 flex items-start justify-between gap-3 rounded-2xl border border-border p-4">
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
                      className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-border text-muted-foreground transition hover:bg-muted hover:text-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
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
                                ? 'bg-primary text-white shadow-sm'
                                : 'border border-border text-foreground hover:bg-muted',
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
            onClick={() => setLocale(locale === 'ar' ? 'en' : 'ar')}
            className="h-11 rounded-xl border border-border bg-card px-3 text-sm font-semibold text-muted-foreground hover:bg-muted hover:text-foreground transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            aria-label="Toggle language"
          >
            {locale === 'ar' ? 'EN' : 'عر'}
          </button>
        </div>
      </div>
    </header>
  );
}

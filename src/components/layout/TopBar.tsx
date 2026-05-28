import { useI18n } from '../../core/i18n';

export function TopBar() {
  const { t, locale, setLocale } = useI18n();

  return (
    <header className="sticky top-0 z-10 border-b border-border bg-card/95 px-4 py-3 backdrop-blur lg:px-8">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-xs text-muted-foreground">{t('env_badge')}</p>
          <p className="text-sm font-semibold">{t('app_name')} — {t('app_tagline')}</p>
        </div>

        <div className="flex items-center gap-3">
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

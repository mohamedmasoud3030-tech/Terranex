import { createContext, useContext, useState, useEffect, type ReactNode } from 'react';
import { ar, type TranslationKey } from './ar';
import { en } from './en';
import type { Locale, Direction } from '../types';

interface I18nContextValue {
  locale: Locale;
  direction: Direction;
  t: (key: TranslationKey) => string;
  setLocale: (locale: Locale) => void;
}

const I18nContext = createContext<I18nContextValue | null>(null);

const translations: Record<Locale, Record<TranslationKey, string>> = { ar, en };

interface I18nProviderProps {
  children: ReactNode;
  defaultLocale?: Locale;
}

export function I18nProvider({ children, defaultLocale = 'ar' }: I18nProviderProps) {
  const [locale, setLocaleState] = useState<Locale>(defaultLocale);

  const direction: Direction = locale === 'ar' ? 'rtl' : 'ltr';

  // Sync html[dir] and html[lang] whenever locale changes
  useEffect(() => {
    document.documentElement.setAttribute('dir', direction);
    document.documentElement.setAttribute('lang', locale);
  }, [locale, direction]);

  function setLocale(next: Locale) {
    setLocaleState(next);
  }

  function t(key: TranslationKey): string {
    return translations[locale][key] ?? translations['ar'][key] ?? key;
  }

  return (
    <I18nContext.Provider value={{ locale, direction, t, setLocale }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n(): I18nContextValue {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error('useI18n must be used inside <I18nProvider>');
  return ctx;
}

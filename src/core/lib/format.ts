import type { Currency, Locale } from '../types';

/**
 * Format a monetary value with its currency symbol.
 * Uses Arabic locale for RTL display, English for LTR.
 */
export function formatMoney(
  value: number,
  currency: Currency,
  locale: Locale = 'ar',
): string {
  const localeStr = locale === 'ar' ? 'ar-EG' : 'en-US';
  return new Intl.NumberFormat(localeStr, {
    style: 'currency',
    currency,
    maximumFractionDigits: currency === 'EGP' ? 0 : 2,
  }).format(value);
}

/**
 * Format a plain number without currency.
 */
export function formatNumber(value: number, locale: Locale = 'ar'): string {
  const localeStr = locale === 'ar' ? 'ar-EG' : 'en-US';
  return new Intl.NumberFormat(localeStr).format(value);
}

/**
 * Format a percentage to one decimal place.
 */
export function formatPercent(value: number, locale: Locale = 'ar'): string {
  const localeStr = locale === 'ar' ? 'ar-EG' : 'en-US';
  return new Intl.NumberFormat(localeStr, {
    style: 'percent',
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  }).format(value / 100);
}

/**
 * Convert a foreign-currency amount to EGP using a given rate.
 * Stored at transaction time — never recalculated retroactively.
 */
export function toEgp(amount: number, fxRate: number): number {
  return Math.round(amount * fxRate * 100) / 100;
}

/**
 * Sum an array of EGP amounts.
 */
export function sumEgp(amounts: number[]): number {
  return amounts.reduce((acc, v) => acc + v, 0);
}

/**
 * Compute profit: income - expense.
 */
export function computeProfit(totalIncomeEgp: number, totalExpenseEgp: number): number {
  return totalIncomeEgp - totalExpenseEgp;
}

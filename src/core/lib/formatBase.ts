/**
 * Base-currency aware formatting helpers.
 *
 * Historically Terranex used EGP as the only operating currency and many
 * columns are still named `*_egp`. The company_settings.base_currency field
 * lets a tenant run on OMR / SAR / AED / USD / etc.; these helpers format a
 * stored `amount_egp` value (which is already expressed in the tenant's base
 * currency at write time — the column is mis-named for legacy reasons) using
 * the appropriate Intl.NumberFormat locale + currency.
 *
 * A later migration can rename `amount_egp` columns to `amount_base`; until
 * then these helpers are the single place that bridges the two worlds.
 */
import { formatMoney } from './format';
import type { Currency } from '../types/domain';

export function formatBase(
  amount: number,
  currency: Currency = 'OMR',
  locale: 'ar' | 'en' = 'ar',
): string {
  return formatMoney(amount, currency, locale);
}

/** Compact (short-scale) formatting for KPIs, e.g. 1.2م / 23ك / 1.5M */
export function formatBaseShort(
  value: number,
  currency: Currency = 'OMR',
  locale: 'ar' | 'en' = 'ar',
): string {
  const abs = Math.abs(value);
  let num: number;
  let suffix: string;
  if (abs >= 1_000_000) { num = value / 1_000_000; suffix = locale === 'ar' ? 'م' : 'M'; }
  else if (abs >= 1_000) { num = value / 1_000; suffix = locale === 'ar' ? 'ك' : 'K'; }
  else { num = value; suffix = ''; }
  const fractionDigits = abs >= 1_000_000 ? 1 : 0;
  const formatted = new Intl.NumberFormat(locale === 'ar' ? 'ar-EG' : 'en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: fractionDigits,
  }).format(num);
  return `${formatted}${suffix} ${currency}`;
}

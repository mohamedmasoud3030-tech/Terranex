import { format, parseISO, startOfMonth, endOfMonth, startOfQuarter, endOfQuarter, startOfYear, endOfYear } from 'date-fns';
import { arEG } from 'date-fns/locale';
import type { DateRange, Locale, PeriodFilter } from '../types';

export function formatDate(isoDate: string, locale: Locale = 'ar'): string {
  const date = parseISO(isoDate);
  return format(date, 'dd MMMM yyyy', { locale: locale === 'ar' ? arEG : undefined });
}

export function formatDateShort(isoDate: string): string {
  return format(parseISO(isoDate), 'yyyy-MM-dd');
}

export function periodToDateRange(period: PeriodFilter, referenceDate = new Date()): DateRange | null {
  switch (period) {
    case 'month':
      return {
        from: formatDateShort(startOfMonth(referenceDate).toISOString()),
        to: formatDateShort(endOfMonth(referenceDate).toISOString()),
      };
    case 'quarter':
      return {
        from: formatDateShort(startOfQuarter(referenceDate).toISOString()),
        to: formatDateShort(endOfQuarter(referenceDate).toISOString()),
      };
    case 'year':
      return {
        from: formatDateShort(startOfYear(referenceDate).toISOString()),
        to: formatDateShort(endOfYear(referenceDate).toISOString()),
      };
    case 'all':
    case 'custom':
      return null;
    default:
      return null;
  }
}

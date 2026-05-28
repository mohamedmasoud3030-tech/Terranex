import type { Currency } from '../data/fixtures';

export function formatMoney(value: number, currency: Currency): string {
  return new Intl.NumberFormat('ar-OM', {
    style: 'currency',
    currency,
    maximumFractionDigits: 0,
  }).format(value);
}

export function formatNumber(value: number): string {
  return new Intl.NumberFormat('ar-OM').format(value);
}

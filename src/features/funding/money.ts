// Exact-money formatting. All stored amounts are integer minor units; the
// browser only formats them for display and never performs money arithmetic.
const DECIMALS: Record<string, number> = { EGP: 2, USD: 2, EUR: 2, SAR: 2, AED: 2 };

export function formatMinorUnits(minorUnits: number | bigint | string, currency: string): string {
  const amount = typeof minorUnits === 'bigint' ? Number(minorUnits) : Number(minorUnits);
  if (!Number.isFinite(amount)) return '—';
  const decimals = DECIMALS[currency] ?? 2;
  const major = amount / 10 ** decimals;
  try {
    return new Intl.NumberFormat('ar-EG', {
      style: 'currency',
      currency,
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    }).format(major);
  } catch {
    return `${major.toLocaleString('ar-EG')} ${currency}`;
  }
}

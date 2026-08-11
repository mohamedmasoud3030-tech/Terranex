// Money stays exact end-to-end: form input is parsed as text into integer minor
// units, PostgreSQL stores bigint, and read views expose bigint values as text.
const DECIMALS: Record<string, number> = { EGP: 2, USD: 2, EUR: 2, SAR: 2, AED: 2 };
const INT64_MAX = 9_223_372_036_854_775_807n;
const ARABIC_DIGITS: Record<string, string> = {
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
};

function normalizeMoneyInput(value: string): string {
  return value
    .trim()
    .replace(/[٠-٩]/g, (digit) => ARABIC_DIGITS[digit] ?? digit)
    .replace(/٫/g, '.')
    .replace(/[٬,\s]/g, '');
}

export function parseMajorUnitsToMinor(value: string, currency: string): string {
  const decimals = DECIMALS[currency] ?? 2;
  const normalized = normalizeMoneyInput(value);
  const pattern = decimals === 0
    ? /^(\d+)$/
    : new RegExp(`^(\\d+)(?:\\.(\\d{1,${decimals}}))?$`);
  const match = normalized.match(pattern);
  if (!match) throw new Error('invalid money amount');

  const whole = BigInt(match[1]);
  const fraction = decimals === 0
    ? 0n
    : BigInt((match[2] ?? '').padEnd(decimals, '0'));
  const scale = 10n ** BigInt(decimals);
  const minor = whole * scale + fraction;
  if (minor <= 0n || minor > INT64_MAX) throw new Error('money amount out of range');
  return minor.toString();
}

export function isValidMajorMoney(value: string, currency = 'EGP'): boolean {
  try {
    parseMajorUnitsToMinor(value, currency);
    return true;
  } catch {
    return false;
  }
}

function parseExactInteger(value: string | number | bigint): bigint | null {
  if (typeof value === 'bigint') return value;
  if (typeof value === 'number') return Number.isSafeInteger(value) ? BigInt(value) : null;
  if (!/^-?\d+$/.test(value)) return null;
  try {
    return BigInt(value);
  } catch {
    return null;
  }
}

export function formatMinorUnits(minorUnits: string | number | bigint, currency: string): string {
  const amount = parseExactInteger(minorUnits);
  if (amount === null) return '—';

  const decimals = DECIMALS[currency] ?? 2;
  const scale = 10n ** BigInt(decimals);
  const negative = amount < 0n;
  const absolute = negative ? -amount : amount;
  const whole = absolute / scale;
  const fraction = absolute % scale;
  const integerFormatter = new Intl.NumberFormat('ar-EG', {
    useGrouping: true,
    maximumFractionDigits: 0,
  });
  const wholeText = integerFormatter.format(whole);
  const decimalSeparator = new Intl.NumberFormat('ar-EG')
    .formatToParts(1.1)
    .find((part) => part.type === 'decimal')?.value ?? '.';
  const fractionText = decimals === 0
    ? ''
    : new Intl.NumberFormat('ar-EG', {
        useGrouping: false,
        minimumIntegerDigits: decimals,
        maximumFractionDigits: 0,
      }).format(Number(fraction));
  const currencyText = new Intl.NumberFormat('ar-EG', {
    style: 'currency',
    currency,
    currencyDisplay: 'narrowSymbol',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).formatToParts(0).find((part) => part.type === 'currency')?.value ?? currency;

  return `${negative ? '−' : ''}${wholeText}${decimals ? `${decimalSeparator}${fractionText}` : ''} ${currencyText}`;
}

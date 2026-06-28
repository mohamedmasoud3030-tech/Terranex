const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const DAYS_PER_MONTH = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] as const;

function isLeapYear(year: number): boolean {
  return year % 400 === 0 || (year % 4 === 0 && year % 100 !== 0);
}

/** Returns a validated calendar date without time-zone conversion. */
export function toDateOnly(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const date = value.slice(0, 10);
  if (!DATE_ONLY.test(date)) return undefined;

  const [yearText, monthText, dayText] = date.split('-');
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  if (month < 1 || month > 12 || day < 1) return undefined;

  const maximumDay = month === 2 && isLeapYear(year) ? 29 : DAYS_PER_MONTH[month - 1];
  if (day > maximumDay) return undefined;
  return date;
}

export function requireDateOnly(value: string, label: string): string {
  const date = toDateOnly(value);
  if (!date) throw new Error(`${label} يجب أن يكون تاريخاً صالحاً بصيغة YYYY-MM-DD.`);
  return date;
}

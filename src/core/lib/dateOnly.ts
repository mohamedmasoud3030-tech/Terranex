const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

function isLeapYear(year: number): boolean {
  return year % 400 === 0 || (year % 4 === 0 && year % 100 !== 0);
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) return isLeapYear(year) ? 29 : 28;
  if (month === 4 || month === 6 || month === 9 || month === 11) return 30;
  if (month === 1 || month === 3 || month === 5 || month === 7 || month === 8 || month === 10 || month === 12) return 31;
  return 0;
}

/** Returns a validated calendar date without time-zone conversion. */
export function toDateOnly(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const date = value.slice(0, 10);
  if (!DATE_ONLY.test(date)) return undefined;

  const year = Number(date.slice(0, 4));
  const month = Number(date.slice(5, 7));
  const day = Number(date.slice(8, 10));
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return undefined;
  return date;
}

export function requireDateOnly(value: string, label: string): string {
  const date = toDateOnly(value);
  if (!date) throw new Error(`${label} يجب أن يكون تاريخاً صالحاً بصيغة YYYY-MM-DD.`);
  return date;
}

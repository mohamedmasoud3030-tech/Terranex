const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/** Returns a validated calendar date without time-zone conversion. */
export function toDateOnly(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const date = value.slice(0, 10);
  if (!DATE_ONLY.test(date)) return undefined;

  const [yearText, monthText, dayText] = date.split('-');
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const parsed = new Date(Date.UTC(0, month - 1, day));
  parsed.setUTCFullYear(year);

  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return undefined;
  }

  return date;
}

export function requireDateOnly(value: string, label: string): string {
  const date = toDateOnly(value);
  if (!date) throw new Error(`${label} يجب أن يكون تاريخاً صالحاً بصيغة YYYY-MM-DD.`);
  return date;
}

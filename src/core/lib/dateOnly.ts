const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

export function toDateOnly(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const date = value.slice(0, 10);
  if (!DATE_ONLY.test(date)) return undefined;

  const timestamp = Date.parse(`${date}T00:00:00Z`);
  if (Number.isNaN(timestamp)) return undefined;
  if (new Date(timestamp).toISOString().slice(0, 10) !== date) return undefined;
  return date;
}

export function requireDateOnly(value: string, label: string): string {
  const date = toDateOnly(value);
  if (!date) throw new Error(`${label} يجب أن يكون تاريخاً صالحاً بصيغة YYYY-MM-DD.`);
  return date;
}

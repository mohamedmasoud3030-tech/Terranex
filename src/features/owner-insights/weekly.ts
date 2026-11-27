import type { OwnerWeeklyCashRow } from './queries';

// Pure weekly-summary model, unit-tested without a database.

export type WeekTotal = {
  weekStart: string;
  currency: string;
  inMinor: bigint;
  outMinor: bigint;
  netMinor: bigint;
};

export type WeeklySummary = {
  currentWeekStart: string | null;
  current: WeekTotal[];
  previous: WeekTotal[];
  recentWeeks: WeekTotal[];
};

/** Monday of the week containing `date` (YYYY-MM-DD), matching date_trunc('week'). */
export function weekStartOf(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  const day = d.getUTCDay();
  const diff = (day + 6) % 7; // days since Monday
  d.setUTCDate(d.getUTCDate() - diff);
  return d.toISOString().slice(0, 10);
}

export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/**
 * Build the weekly summary from org rows. `today` anchors "this week" so the
 * summary stays meaningful even in a week with no postings yet.
 */
export function buildWeeklySummary(rows: readonly OwnerWeeklyCashRow[], today: string, weekCount = 8): WeeklySummary {
  const currentWeekStart = weekStartOf(today);
  const previousWeekStart = addDays(currentWeekStart, -7);
  const byKey = new Map<string, WeekTotal>();
  for (const row of rows) {
    const key = `${row.week_start}|${row.currency}`;
    const existing = byKey.get(key);
    const inMinor = BigInt(row.in_minor_units);
    const outMinor = BigInt(row.out_minor_units);
    if (existing) {
      existing.inMinor += inMinor;
      existing.outMinor += outMinor;
      existing.netMinor = existing.inMinor - existing.outMinor;
    } else {
      byKey.set(key, { weekStart: row.week_start, currency: row.currency, inMinor, outMinor, netMinor: inMinor - outMinor });
    }
  }
  const all = [...byKey.values()];
  const pick = (weekStart: string) => all.filter((t) => t.weekStart === weekStart).sort((a, b) => a.currency.localeCompare(b.currency));
  const earliest = addDays(currentWeekStart, -7 * (weekCount - 1));
  const recentWeeks = all
    .filter((t) => t.weekStart >= earliest && t.weekStart <= currentWeekStart)
    .sort((a, b) => (a.weekStart === b.weekStart ? a.currency.localeCompare(b.currency) : a.weekStart < b.weekStart ? -1 : 1));
  return {
    currentWeekStart,
    current: pick(currentWeekStart),
    previous: pick(previousWeekStart),
    recentWeeks,
  };
}

/** Percent delta of current vs previous; null when there is no previous base. */
export function weekOverWeekDelta(currentMinor: bigint, previousMinor: bigint): number | null {
  if (previousMinor === 0n) return null;
  return Number((currentMinor - previousMinor) * 10000n / previousMinor) / 100;
}

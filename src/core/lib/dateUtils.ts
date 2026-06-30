/**
 * Shared date helpers — single source of truth
 * No external dependencies.
 */

/** Returns today's date as ISO 8601 string (YYYY-MM-DD) in local time. */
export function todayIso(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Returns the number of calendar days between two ISO date strings. Positive = b is after a. */
export function daysBetween(a: string, b: string): number {
  return Math.round((new Date(b).getTime() - new Date(a).getTime()) / 86_400_000);
}

/** Returns true if ISO date string is in the past relative to asOf (default: today). */
export function isPast(dateIso: string, asOf?: string): boolean {
  return (asOf ?? todayIso()) > dateIso;
}

import { describe, expect, it } from 'vitest';
import { addDays, buildWeeklySummary, weekOverWeekDelta, weekStartOf } from '@/features/owner-insights/weekly';
import type { OwnerWeeklyCashRow } from '@/features/owner-insights/queries';

const row = (weekStart: string, currency: string, inMinor: string, outMinor: string): OwnerWeeklyCashRow => ({
  organization_id: 'org',
  week_start: weekStart,
  currency,
  in_minor_units: inMinor,
  out_minor_units: outMinor,
});

describe('weekStartOf', () => {
  it('anchors on Monday like date_trunc(week)', () => {
    expect(weekStartOf('2026-11-27')).toBe('2026-11-23'); // Friday
    expect(weekStartOf('2026-11-23')).toBe('2026-11-23'); // Monday itself
    expect(weekStartOf('2026-11-22')).toBe('2026-11-16'); // Sunday belongs to the previous week
  });
  it('addDays moves across month boundaries', () => {
    expect(addDays('2026-11-30', 7)).toBe('2026-12-07');
  });
});

describe('buildWeeklySummary', () => {
  const rows = [
    row('2026-11-23', 'EGP', '100000', '40000'),
    row('2026-11-16', 'EGP', '80000', '50000'),
    row('2026-11-16', 'USD', '10000', '0'),
  ];

  it('picks the current and previous week per currency', () => {
    const summary = buildWeeklySummary(rows, '2026-11-27');
    expect(summary.currentWeekStart).toBe('2026-11-23');
    expect(summary.current).toHaveLength(1);
    expect(summary.current[0].netMinor).toBe(60000n);
    expect(summary.previous).toHaveLength(2);
  });

  it('handles an empty week without inventing numbers', () => {
    const summary = buildWeeklySummary([], '2026-11-27');
    expect(summary.current).toHaveLength(0);
    expect(summary.recentWeeks).toHaveLength(0);
  });

  it('keeps only the requested week window', () => {
    const old = [row('2026-09-01', 'EGP', '1000', '0')];
    const summary = buildWeeklySummary(old, '2026-11-27', 8);
    expect(summary.recentWeeks).toHaveLength(0);
  });
});

describe('weekOverWeekDelta', () => {
  it('returns null without a previous base', () => {
    expect(weekOverWeekDelta(100n, 0n)).toBeNull();
  });
  it('computes signed percent change', () => {
    expect(weekOverWeekDelta(150n, 100n)).toBe(50);
    expect(weekOverWeekDelta(50n, 100n)).toBe(-50);
  });
});

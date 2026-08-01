const test = require('node:test');
const assert = require('node:assert/strict');

const {
  computeProfit,
  formatMoney,
  formatNumber,
  formatPercent,
  roundEgp,
  sumEgp,
  toEgp,
} = require('./.compiled/core/lib/format.js');

const { daysBetween, isPast, todayIso } = require('./.compiled/core/lib/dateUtils.js');

test('formatMoney drops fractions for EGP but keeps two decimals for foreign currencies', () => {
  const egp = formatMoney(1234.56, 'EGP', 'en');
  assert.match(egp, /1,235/);
  assert.doesNotMatch(egp, /\.\d/);

  assert.match(formatMoney(1234.5, 'USD', 'en'), /1,234\.50/);
  assert.match(formatMoney(-1234.5, 'USD', 'en'), /1,234\.50/);
});

test('formatMoney and formatNumber follow the requested locale', () => {
  assert.notEqual(formatNumber(1234.5, 'ar'), formatNumber(1234.5, 'en'));
  assert.equal(formatNumber(1234.5, 'en'), '1,234.5');
  assert.equal(formatNumber(1234.5), formatNumber(1234.5, 'ar'));
  assert.notEqual(formatMoney(1000, 'EGP', 'ar'), formatMoney(1000, 'EGP', 'en'));
});

test('formatPercent renders a 0-100 scale with one decimal place', () => {
  assert.match(formatPercent(12.34, 'en'), /^12\.3%$/);
  assert.match(formatPercent(0, 'en'), /^0\.0%$/);
  assert.match(formatPercent(-5, 'en'), /5\.0%/);
  assert.equal(formatPercent(12.34), formatPercent(12.34, 'ar'));
});

test('toEgp converts at the stored rate and rounds to the piaster', () => {
  assert.equal(toEgp(100, 48.5), 4850);
  assert.equal(toEgp(10, 48.567), 485.67);
  assert.equal(toEgp(0.001, 48.5), 0.05);
  assert.equal(toEgp(-10, 48.567), -485.67);
});

test('roundEgp normalizes float arithmetic before comparison or summing', () => {
  assert.equal(roundEgp(0.1 + 0.2), 0.3);
  assert.equal(roundEgp(1.005), 1.0);
  assert.equal(roundEgp(-2.5678), -2.57);
  assert.equal(roundEgp(1000), 1000);
});

test('sumEgp and computeProfit aggregate amounts', () => {
  assert.equal(sumEgp([]), 0);
  assert.equal(sumEgp([100.25, -50.25, 10]), 60);
  assert.equal(computeProfit(1000, 400), 600);
  assert.equal(computeProfit(400, 1000), -600);
});

test('todayIso returns the local calendar date as YYYY-MM-DD', () => {
  const today = todayIso();
  assert.match(today, /^\d{4}-\d{2}-\d{2}$/);

  const now = new Date();
  const expected = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  assert.equal(today, expected);
});

test('daysBetween counts calendar days in both directions and across DST shifts', () => {
  assert.equal(daysBetween('2026-01-01', '2026-01-31'), 30);
  assert.equal(daysBetween('2026-01-31', '2026-01-01'), -30);
  assert.equal(daysBetween('2026-01-01', '2026-01-01'), 0);
  assert.equal(daysBetween('2026-02-28', '2026-03-01'), 1);
  assert.equal(daysBetween('2024-02-28', '2024-03-01'), 2);
});

test('isPast compares against an explicit as-of date, defaulting to today', () => {
  assert.equal(isPast('2026-01-01', '2026-01-02'), true);
  assert.equal(isPast('2026-01-02', '2026-01-02'), false);
  assert.equal(isPast('2026-01-03', '2026-01-02'), false);
  assert.equal(isPast(todayIso()), false);
  assert.equal(isPast('1999-01-01'), true);
});

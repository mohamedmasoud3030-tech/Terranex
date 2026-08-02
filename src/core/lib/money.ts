/**
 * Safe monetary arithmetic helpers.
 *
 * We work exclusively with integer minor units under the hood so classic
 * JS float errors (0.1 + 0.2 ≠ 0.3) cannot creep into addition, subtraction
 * or FX conversion. For the MVP we use a tiny internal calculator that
 * mirrors the API of Dinero.js v2 — full Dinero.js can be swapped in later
 * without changing call sites.
 *
 * All currencies are stored in Postgres as `numeric(18,3)`; the internal
 * scale below is 3 for every currency to keep FX math exact (1 baisa =
 * 1/1000 OMR, 1 millième = 1/1000 EGP/USD/etc.). Display formatting is
 * handled by `formatMoney` in format.ts with per-currency decimal places.
 */
import type { Currency } from '../types/domain';

/** Internal precision: 3 minor units per major unit (1000 per 1). */
export const MONEY_SCALE = 3;
const FACTOR = Math.pow(10, MONEY_SCALE);

/** Convert a major-unit amount to integer minor units safely rounded half-up. */
function toMinor(amount: number): number {
  if (!Number.isFinite(amount)) return 0;
  return Math.round(amount * FACTOR);
}

/** Convert minor integer units back to a major-unit number. */
function toMajor(minor: number): number {
  return Math.round(minor) / FACTOR;
}

export interface MoneyAmount {
  minor: number;
  currency: Currency;
}

export function toMoney(amount: number, currency: Currency): MoneyAmount {
  return { minor: toMinor(amount), currency };
}

export function toAmount(m: MoneyAmount): number {
  return toMajor(m.minor);
}

/** Zero value in a given currency. */
export function zero(currency: Currency): MoneyAmount {
  return { minor: 0, currency };
}

/** Add two money amounts (must share currency; returns 0 if mismatched). */
export function add(a: MoneyAmount, b: MoneyAmount): MoneyAmount {
  if (a.currency !== b.currency) return a; // safety fallback; caller shouldn't mix
  return { minor: a.minor + b.minor, currency: a.currency };
}

/** a - b (same currency). */
export function subtract(a: MoneyAmount, b: MoneyAmount): MoneyAmount {
  if (a.currency !== b.currency) return a;
  return { minor: a.minor - b.minor, currency: a.currency };
}

/** Multiply by a scalar (used for FX and allocations). */
export function multiply(a: MoneyAmount, factor: number): MoneyAmount {
  return { minor: Math.round(a.minor * factor), currency: a.currency };
}

/** Sum an array of numbers in a given currency. */
export function sumAmounts(amounts: number[], currency: Currency): number {
  const total = amounts.reduce<number>((acc, v) => acc + toMinor(v), 0);
  return toMajor(total);
}

/** Display precision (number of fractional digits shown to the user). */
export const CURRENCY_DISPLAY_SCALE: Record<Currency, number> = {
  OMR: 3,
  EGP: 0,
  USD: 2,
  SAR: 2,
  AED: 2,
  EUR: 2,
  GBP: 2,
};

/** Round a major-unit amount to the currency's display precision (half-up). */
export function roundForDisplay(amount: number, currency: Currency): number {
  const scale = CURRENCY_DISPLAY_SCALE[currency];
  const f = Math.pow(10, scale);
  return Math.round(amount * f) / f;
}

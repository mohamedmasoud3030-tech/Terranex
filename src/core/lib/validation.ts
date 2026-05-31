import { z } from 'zod';

export const finitePositiveNumberSchema = z
  .number({ error: 'يجب إدخال رقم صحيح.' })
  .finite('القيمة يجب أن تكون رقماً صالحاً.')
  .positive('القيمة يجب أن تكون أكبر من صفر.');

export function parseFinitePositiveAmount(value: unknown) {
  const numeric = typeof value === 'string' ? Number(value) : value;
  return finitePositiveNumberSchema.safeParse(numeric);
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

export function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

export function clampRemainingBalance(total: number, settled: number) {
  return Math.max(0, total - settled);
}

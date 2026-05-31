import { z } from 'zod';
import type { Currency } from '../types/domain';

export const AR_VALIDATION = {
  required: 'هذا الحقل مطلوب',
  positive: 'يجب أن تكون القيمة أكبر من صفر',
  finite: 'يجب إدخال رقم صالح',
  isoDate: 'يجب إدخال تاريخ صالح بصيغة ISO',
  enumValue: 'القيمة المختارة غير صالحة',
  relationshipId: 'المرجع المرتبط غير صالح',
  currencyConversion: 'بيانات تحويل العملة غير صالحة',
};

export const requiredString = z.string().trim().min(1, AR_VALIDATION.required);
export const finiteNumber = z.number().finite(AR_VALIDATION.finite);
export const positiveNumber = finiteNumber.positive(AR_VALIDATION.positive);
export const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, AR_VALIDATION.isoDate);
export const relationshipId = z.string().trim().min(1, AR_VALIDATION.relationshipId);

export function enumValue<T extends readonly [string, ...string[]]>(values: T) {
  return z.enum(values, { error: AR_VALIDATION.enumValue });
}

export const currencyConversionInput = z.object({
  amount: positiveNumber,
  currency: enumValue(['EGP', 'USD', 'SAR', 'AED', 'EUR', 'GBP'] as const),
  fx_rate: positiveNumber,
}).refine((value) => value.currency !== 'EGP' || value.fx_rate === 1, {
  message: AR_VALIDATION.currencyConversion,
  path: ['fx_rate'],
});

export function toValidationErrorMap(error: z.ZodError) {
  return Object.fromEntries(error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message]));
}

export function isCurrency(value: string): value is Currency {
  return ['EGP', 'USD', 'SAR', 'AED', 'EUR', 'GBP'].includes(value);
}

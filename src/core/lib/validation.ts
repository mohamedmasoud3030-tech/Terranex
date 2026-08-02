import { z } from 'zod';
import { toDateOnly } from './dateOnly';
import type {
  AssetStatus,
  AssetType,
  Currency,
  ProjectStatus,
  SectorId,
  TransactionCategory,
  TransactionDirection,
} from '../types/domain';

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

// ─── Zod Schemas — P2 Unified Validation ───────────────────────────────────

const currencyEnum: [Currency, ...Currency[]] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];
const sectorEnum: [SectorId, ...SectorId[]] = ['real-estate', 'agriculture', 'livestock'];
const projectStatusEnum: [ProjectStatus, ...ProjectStatus[]] = ['planning', 'active', 'on_hold', 'completed', 'cancelled'];
const txDirectionEnum: [TransactionDirection, ...TransactionDirection[]] = ['income', 'expense'];

const arabicText = z.string().trim().min(2, 'يجب إدخال نص عربي صحيح (حرفان على الأقل)').max(200, 'النص طويل جداً');
const optionalText = z.string().trim().max(2000, 'النص طويل جداً').optional().or(z.literal(''));
/**
 * Validates a real calendar date (YYYY-MM-DD). A plain regex cannot see that
 * 2026-02-30 or 2026-13-01 do not exist, so we delegate to `toDateOnly` which
 * checks the actual day/month/year against the calendar.
 */
const isoDate = z.string().refine((value) => {
  try {
    return toDateOnly(value) !== undefined;
  } catch {
    return false;
  }
}, 'التاريخ المدخل غير موجود في التقويم، يرجى التحقق من اليوم والشهر والسنة.');

const moneyAmount = z.coerce
  .number({ error: 'أدخل مبلغاً رقمياً صحيحاً' })
  .finite('المبلغ غير صالح')
  .positive('المبلغ يجب أن يكون أكبر من صفر')
  .max(1_000_000_000_000, 'المبلغ كبير جداً');

const fxRateSchema = z.coerce
  .number({ error: 'سعر الصرف مطلوب' })
  .finite('سعر الصرف غير صالح')
  .min(0.000001, 'سعر الصرف يجب أن يكون أكبر من صفر')
  .max(1_000_000, 'سعر الصرف كبير جداً');

const equityPctSchema = z.coerce
  .number({ error: 'أدخل نسبة صحيحة' })
  .finite('النسبة غير صالحة')
  .min(0.01, 'النسبة يجب أن تكون أكبر من صفر')
  .max(100, 'النسبة لا تتجاوز 100%');

// ─── Project ───────────────────────────────────────────────────────────────

export const projectSchema = z.object({
  sector_id: z.enum(sectorEnum, { error: 'اختر القطاع' }),
  name_ar: arabicText,
  name_en: z.string().trim().max(200).optional().or(z.literal('')),
  description_ar: optionalText,
  description_en: optionalText,
  status: z.enum(projectStatusEnum).default('active'),
  start_date: isoDate,
  end_date: isoDate.optional().or(z.literal('')),
  base_currency: z.enum(currencyEnum),
}).refine((data) => {
  if (!data.end_date) return true;
  return data.end_date >= data.start_date;
}, {
  message: 'تاريخ الانتهاء يجب أن يكون بعد تاريخ البدء',
  path: ['end_date'],
});

export type ProjectFormValues = z.infer<typeof projectSchema>;

// ─── Asset ─────────────────────────────────────────────────────────────────

const assetTypeEnum: [AssetType, ...AssetType[]] = [
  'land',
  'building',
  'farm',
  'equipment',
  'herd',
  'animal_group',
  'crop',
  'other',
];
const assetStatusEnum: [AssetStatus, ...AssetStatus[]] = [
  'owned',
  'leased',
  'sold',
  'disposed',
];
const optionalNonNegativeNumber = z.preprocess(
  (value) => value === '' || value === null ? undefined : value,
  z.coerce.number().finite('القيمة غير صالحة').min(0, 'القيمة لا يمكن أن تكون سالبة').optional(),
);

export const assetSchema = z.object({
  project_id: z.string().min(1, 'اختر المشروع'),
  sector_id: z.enum(sectorEnum, { error: 'اختر القطاع' }),
  type: z.enum(assetTypeEnum, { error: 'اختر نوع الأصل' }),
  name_ar: arabicText,
  name_en: z.string().trim().max(200).optional().or(z.literal('')),
  acquisition_date: isoDate,
  acquisition_cost: z.coerce.number().finite().min(0, 'تكلفة الاقتناء لا يمكن أن تكون سالبة'),
  acquisition_currency: z.enum(currencyEnum),
  fx_rate: z.coerce.number().finite().positive('سعر الصرف يجب أن يكون أكبر من صفر').default(1),
  acquisition_cost_egp: z.coerce.number().finite().min(0, 'التكلفة بالجنيه لا يمكن أن تكون سالبة'),
  current_value_egp: optionalNonNegativeNumber,
  status: z.enum(assetStatusEnum),
  quantity: optionalNonNegativeNumber,
  unit: z.string().trim().max(40).optional().or(z.literal('')),
  notes: optionalText,
});

export type AssetFormValues = z.infer<typeof assetSchema>;

// ─── Transaction ───────────────────────────────────────────────────────────

const txCategoryValues: [TransactionCategory, ...TransactionCategory[]] = [
  'acquisition','sale','development_cost','maintenance','salary','tax','legal_fee','transport','utility',
  'seed_input','fertilizer','harvest_revenue','irrigation',
  'feed','veterinary','vaccination','livestock_purchase','livestock_sale',
  'loan_disbursement','loan_repayment','interest','dividend','other'
];

export const transactionSchema = z.object({
  project_id: z.string().min(1, 'اختر المشروع'),
  asset_id: z.string().optional().or(z.literal('')),
  partner_id: z.string().optional().or(z.literal('')),
  bank_account_id: z.string().optional().or(z.literal('')),
  direction: z.enum(txDirectionEnum, { error: 'اختر اتجاه المعاملة' }),
  category: z.enum(txCategoryValues, { error: 'اختر التصنيف' }),
  amount: moneyAmount,
  currency: z.enum(currencyEnum, { error: 'اختر العملة' }),
  fx_rate: fxRateSchema,
  transaction_date: isoDate,
  document_id: z.string().optional().or(z.literal('')),
  description: optionalText,
  notes: optionalText,
}).superRefine((data, ctx) => {
  // EGP must have fx_rate = 1
  if (data.currency === 'EGP' && Math.abs(data.fx_rate - 1) > 0.0001) {
    ctx.addIssue({
      code: 'custom',
      message: 'سعر صرف الجنيه المصري يجب أن يساوي 1',
      path: ['fx_rate'],
    });
  }
});

export type TransactionFormValues = z.infer<typeof transactionSchema>;

// ─── Partner ───────────────────────────────────────────────────────────────

export const partnerSchema = z.object({
  name_ar: arabicText,
  name_en: z.string().trim().max(200).optional().or(z.literal('')),
  category: z.enum(['equity_partner', 'counterparty'] as const, { error: 'اختر التصنيف' }),
  counterparty_role: z.enum(['supplier','client','service_provider','lender','government','other'] as const).optional(),
  phone: z.string().trim().max(30).optional().or(z.literal('')),
  email: z.string().email('بريد إلكتروني غير صالح').optional().or(z.literal('')),
  address: optionalText,
  notes: optionalText,
}).superRefine((data, ctx) => {
  if (data.category === 'counterparty' && !data.counterparty_role) {
    ctx.addIssue({
      code: 'custom',
      message: 'حدد دور الطرف عند اختيار "طرف تعامل"',
      path: ['counterparty_role'],
    });
  }
});

export type PartnerFormValues = z.infer<typeof partnerSchema>;

// ─── ProjectPartner (Equity) ───────────────────────────────────────────────

export const projectPartnerSchema = z.object({
  project_id: z.string().min(1, 'المشروع مطلوب'),
  partner_id: z.string().min(1, 'اختر الشريك'),
  equity_pct: equityPctSchema,
  effective_from: isoDate,
  effective_to: isoDate.optional().or(z.literal('')),
  notes: optionalText,
}).refine((d) => !d.effective_to || d.effective_to >= d.effective_from, {
  message: 'تاريخ الانتهاء يجب أن يكون بعد تاريخ السريان',
  path: ['effective_to'],
});

export type ProjectPartnerFormValues = z.infer<typeof projectPartnerSchema>;

// ─── Obligation ────────────────────────────────────────────────────────────

export const obligationSchema = z.object({
  project_id: z.string().optional().or(z.literal('')),
  partner_id: z.string().min(1, 'اختر الطرف'),
  direction: z.enum(['receivable', 'payable'] as const, { error: 'اختر نوع الالتزام' }),
  amount: moneyAmount,
  currency: z.enum(currencyEnum),
  due_date: isoDate.optional().or(z.literal('')),
  document_id: z.string().optional().or(z.literal('')),
  notes: optionalText,
});

export type ObligationFormValues = z.infer<typeof obligationSchema>;

// ─── Operational Event ─────────────────────────────────────────────────────
// ملاحظة معمارية: EventForm يعتمد حالياً على تحقق يدوي في
// features/operations/model.ts، وتبقى هذه السكيمة مرجعاً لمدخلات الأحداث.

export const operationalEventSchema = z.object({
  asset_id: z.string().min(1, 'اختر الأصل'),
  project_id: z.string().min(1, 'اختر المشروع'),
  type: z.enum([
    'birth','death','purchase','sale','vaccination','treatment','feed_consumption','weighing','transfer',
    'planting','irrigation','fertilization','pest_control','harvest','crop_loss'
  ] as const, { error: 'اختر نوع الحدث' }),
  event_date: isoDate,
  quantity_delta: z.coerce.number().finite().optional(),
  weight_kg: z.coerce.number().positive('الوزن يجب أن يكون موجباً').optional().or(z.literal('')),
  unit_cost_egp: z.coerce.number().min(0).optional().or(z.literal('')),
  total_cost_egp: z.coerce.number().min(0).optional().or(z.literal('')),
  description: optionalText,
  document_id: z.string().optional().or(z.literal('')),
});

export type OperationalEventFormValues = z.infer<typeof operationalEventSchema>;

// ─── Equity Change Event ──────────────────────────────────────────────────

export const equityChangeSchema = z.object({
  project_id: z.string().min(1, 'المشروع مطلوب'),
  partner_id: z.string().min(1, 'اختر الشريك'),
  effective_date: isoDate,
  previous_pct: z.coerce.number().finite().min(0).max(100),
  new_pct: z.coerce.number().finite().min(0).max(100),
  change_type: z.enum(['entry', 'increase', 'decrease', 'exit', 'correction'] as const),
  consideration_amount: z.coerce.number().finite().min(0).optional().or(z.literal('')),
  consideration_currency: z.enum(currencyEnum).optional(),
  supporting_document_id: z.string().optional().or(z.literal('')),
  reason: optionalText,
  notes: optionalText,
}).refine((d) => {
  if (d.change_type === 'entry' && d.new_pct <= d.previous_pct) return false;
  if (d.change_type === 'exit' && d.new_pct > 0) return false;
  if (d.change_type === 'increase' && d.new_pct <= d.previous_pct) return false;
  if (d.change_type === 'decrease' && d.new_pct >= d.previous_pct) return false;
  return true;
}, {
  message: 'نوع التغيير غير متوافق مع اتجاه تغيير النسبة',
  path: ['change_type'],
});

export type EquityChangeFormValues = z.infer<typeof equityChangeSchema>;

// ─── Partner Ledger Entry ─────────────────────────────────────────────────

export const partnerLedgerEntrySchema = z.object({
  project_id: z.string().min(1, 'المشروع مطلوب'),
  partner_id: z.string().min(1, 'اختر الشريك'),
  entry_type: z.enum([
    'capital_contribution', 'withdrawal', 'distribution_entitlement',
    'distribution_payment', 'correction', 'reversal'
  ] as const),
  amount: moneyAmount,
  currency: z.enum(currencyEnum),
  fx_rate: fxRateSchema,
  posting_date: isoDate,
  supporting_document_id: z.string().optional().or(z.literal('')),
  related_equity_event_id: z.string().optional().or(z.literal('')),
  related_distribution_id: z.string().optional().or(z.literal('')),
  notes: optionalText,
});

export type PartnerLedgerEntryFormValues = z.infer<typeof partnerLedgerEntrySchema>;

// ─── Distribution ─────────────────────────────────────────────────────────

export const distributionSchema = z.object({
  project_id: z.string().min(1, 'المشروع مطلوب'),
  distribution_date: isoDate,
  ownership_as_of_date: isoDate,
  total_amount: moneyAmount,
  currency: z.enum(currencyEnum),
  fx_rate: fxRateSchema,
  notes: optionalText,
  supporting_document_id: z.string().optional().or(z.literal('')),
}).refine((d) => d.ownership_as_of_date <= d.distribution_date, {
  message: 'تاريخ ملكية التوزيع يجب أن يكون قبل أو مساويًا لتاريخ التوزيع',
  path: ['ownership_as_of_date'],
});

export type DistributionFormValues = z.infer<typeof distributionSchema>;

// ─── Helpers ───────────────────────────────────────────────────────────────

export function getZodFieldError<T>(result: z.ZodSafeParseResult<T>, field: string): string | undefined {
  if (result.success) return undefined;
  const issue = result.error.issues.find(i => i.path[0] === field);
  return issue?.message;
}

export function zodToRHF<T extends z.ZodTypeAny>(schema: T) {
  // helper type bridge — actual resolver is @hookform/resolvers/zod
  return schema;
}

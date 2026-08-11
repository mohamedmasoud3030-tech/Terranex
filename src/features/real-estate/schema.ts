import { z } from 'zod';
import { isValidMajorMoney } from '@/features/funding/money';

const moneyAmount = z
  .string({ error: 'أدخل مبلغًا صحيحًا' })
  .trim()
  .refine((value) => isValidMajorMoney(value, 'EGP'), 'أدخل مبلغًا موجبًا بحد أقصى خانتين عشريتين');

const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);

export const propertyAssetSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  displayName: z.string().trim().min(2, 'اسم العقار مطلوب').max(160),
  strategy: z.enum(['ACQUIRE_HOLD', 'DEVELOP_SELL', 'LAND_TRADE']),
  jurisdiction: z.string().trim().max(80).optional().or(z.literal('')),
  titleStatus: z.enum(['PENDING', 'CLEAR', 'DISPUTED', 'LEASED']).optional(),
  acquiredOn: z.string().min(1).optional(),
  acquisitionCost: z.string().trim().optional().or(z.literal('')),
  currency: z.string().regex(/^[A-Z]{3}$/),
  idempotencyKey,
});

export const propertyCostItemSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  propertyAssetId: z.string().uuid(),
  parcelId: z.string().uuid().optional(),
  costCategory: z.string().trim().min(2, 'فئة التكلفة مطلوبة').max(80),
  isCapitalizable: z.boolean().default(true),
  costAmount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/),
  description: z.string().trim().max(500).optional().or(z.literal('')),
  occurredOn: z.string().min(1, 'تاريخ التكلفة مطلوب'),
  obligationId: z.string().uuid().optional(),
  idempotencyKey,
});

export const propertyValuationSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  propertyAssetId: z.string().uuid(),
  effectiveDate: z.string().min(1, 'تاريخ التقييم مطلوب'),
  valuerSource: z.string().trim().min(2, 'مصدر التقييم مطلوب').max(160),
  method: z.string().trim().min(2, 'طريقة التقييم مطلوبة').max(80),
  valuationAmount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/),
  assumptions: z.string().trim().max(2000).optional().or(z.literal('')),
  confidence: z.enum(['LOW', 'MEDIUM', 'HIGH']).optional(),
  idempotencyKey,
});

export const dispositionSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  propertyAssetId: z.string().uuid(),
  buyerPartyId: z.string().uuid(),
  agreedProceeds: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/),
  agreementDate: z.string().min(1, 'تاريخ الاتفاق مطلوب'),
  sellingCosts: z.string().trim().optional().or(z.literal('')),
  contractReference: z.string().trim().max(120).optional().or(z.literal('')),
  idempotencyKey,
});

export const recognizeSaleSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  dispositionId: z.string().uuid(),
  controlTransferDate: z.string().min(1, 'تاريخ نقل السيطرة مطلوب'),
  idempotencyKey,
});

export const collectionSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  saleReceivableId: z.string().uuid(),
  collectionAmount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/),
  collectedOn: z.string().min(1, 'تاريخ التحصيل مطلوب'),
  cashAccountId: z.string().uuid(),
  idempotencyKey,
});

export const obligationSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  supplierPartyId: z.string().uuid(),
  amount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/),
  costCategory: z.string().trim().min(2, 'فئة التكلفة مطلوبة').max(80),
  description: z.string().trim().max(500).optional().or(z.literal('')),
  occurredOn: z.string().min(1, 'تاريخ الالتزام مطلوب'),
  idempotencyKey,
});

export type PropertyAssetInput = z.infer<typeof propertyAssetSchema>;
export type PropertyCostItemInput = z.infer<typeof propertyCostItemSchema>;
export type PropertyValuationInput = z.infer<typeof propertyValuationSchema>;
export type DispositionInput = z.infer<typeof dispositionSchema>;
export type RecognizeSaleInput = z.infer<typeof recognizeSaleSchema>;
export type CollectionInput = z.infer<typeof collectionSchema>;
export type ObligationInput = z.infer<typeof obligationSchema>;

import { z } from 'zod';
import { isValidMajorMoney } from '@/shared/money';

const moneyAmount = z
  .string({ error: 'أدخل مبلغًا صحيحًا' })
  .trim()
  .refine((value) => isValidMajorMoney(value, 'EGP'), 'أدخل مبلغًا موجبًا بحد أقصى خانتين عشريتين');

const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);

export const partySchema = z.object({
  organizationId: z.string().uuid(),
  legalName: z.string().trim().min(2, 'اسم الطرف مطلوب').max(160),
  partyType: z.enum(['PERSON', 'ORGANIZATION']).default('PERSON'),
});

export const participantSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  partyId: z.string().uuid(),
});

export const agreementDraftSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  effectiveDate: z.string().min(1, 'تاريخ السريان مطلوب'),
  idempotencyKey,
  participants: z
    .array(
      z.object({
        participantId: z.string().uuid(),
        commitmentAmount: moneyAmount,
      }),
    )
    .min(1, 'أضف مشاركًا واحدًا على الأقل'),
});

export const activateVersionSchema = z.object({
  organizationId: z.string().uuid(),
  versionId: z.string().uuid(),
});

const rawCapitalCallLine = z.object({
  participantId: z.string().uuid(),
  amount: z.string().trim(),
});
const capitalCallLine = z.object({
  participantId: z.string().uuid(),
  amount: moneyAmount,
});

export const capitalCallSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  agreementVersionId: z.string().uuid(),
  dueDate: z.string().min(1, 'تاريخ الاستحقاق مطلوب'),
  reference: z.string().trim().max(80).optional().or(z.literal('')),
  idempotencyKey,
  lines: z
    .array(rawCapitalCallLine)
    .transform((lines) => lines.filter((line) => line.amount !== ''))
    .pipe(z.array(capitalCallLine).min(1, 'أدخل مبلغًا لمستثمر واحد على الأقل')),
});

export const contributionSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  participantId: z.string().uuid(),
  agreementVersionId: z.string().uuid(),
  capitalCallId: z.string().uuid(),
  amount: moneyAmount,
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة'),
  occurredOn: z.string().min(1, 'تاريخ الاستلام مطلوب'),
  idempotencyKey,
});

export type PartyInput = z.infer<typeof partySchema>;
export type AgreementDraftInput = z.infer<typeof agreementDraftSchema>;
export type CapitalCallInput = z.infer<typeof capitalCallSchema>;
export type ContributionInput = z.infer<typeof contributionSchema>;

import { z } from 'zod';

const minorUnits = z
  .number({ error: 'أدخل رقمًا صحيحًا' })
  .int('المبلغ يجب أن يكون عددًا صحيحًا بالوحدات الصغرى')
  .positive('المبلغ يجب أن يكون أكبر من صفر');

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
  participants: z
    .array(
      z.object({
        participantId: z.string().uuid(),
        commitmentMinorUnits: minorUnits,
      }),
    )
    .min(1, 'أضف مشاركًا واحدًا على الأقل'),
});

export const activateVersionSchema = z.object({
  organizationId: z.string().uuid(),
  versionId: z.string().uuid(),
});

export const capitalCallSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  agreementVersionId: z.string().uuid(),
  dueDate: z.string().min(1, 'تاريخ الاستحقاق مطلوب'),
  reference: z.string().trim().max(80).optional().or(z.literal('')),
  lines: z
    .array(
      z.object({
        participantId: z.string().uuid(),
        amountMinorUnits: minorUnits,
      }),
    )
    .min(1, 'أضف بند طلب واحد على الأقل'),
});

export const contributionSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  participantId: z.string().uuid(),
  agreementVersionId: z.string().uuid(),
  capitalCallId: z.string().uuid(),
  contributionMinorUnits: minorUnits,
  currency: z.string().regex(/^[A-Z]{3}$/, 'عملة غير صحيحة'),
  occurredOn: z.string().min(1, 'تاريخ الاستلام مطلوب'),
  idempotencyKey: z.string().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120),
});

export type PartyInput = z.infer<typeof partySchema>;
export type AgreementDraftInput = z.infer<typeof agreementDraftSchema>;
export type CapitalCallInput = z.infer<typeof capitalCallSchema>;
export type ContributionInput = z.infer<typeof contributionSchema>;

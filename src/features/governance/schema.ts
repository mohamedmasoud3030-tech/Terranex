import { z } from 'zod';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const optionalText = (max: number) => z.preprocess(
  (value) => value === '' ? null : value,
  z.string().trim().min(3, 'أدخل ثلاثة أحرف على الأقل').max(max).nullable(),
);

export const projectRiskSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  title: z.string().trim().min(3, 'عنوان الخطر مطلوب').max(160),
  description: z.string().trim().min(3, 'وصف الخطر مطلوب').max(2000),
  severity: z.enum(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']),
  ownerUserId: uuid,
  dueDate: z.preprocess((value) => value === '' ? null : value, z.string().nullable()),
  sourceReference: optionalText(200),
  idempotencyKey,
});

export const riskResolutionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  riskItemId: uuid,
  outcome: z.string().trim().min(3, 'نتيجة الحسم مطلوبة').max(1000),
  evidenceReference: optionalText(200),
  idempotencyKey,
});

export const projectDecisionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  title: z.string().trim().min(3, 'عنوان القرار مطلوب').max(160),
  decisionText: z.string().trim().min(3, 'نص القرار مطلوب').max(4000),
  rationale: optionalText(4000),
  decisionDate: z.string().min(1, 'تاريخ القرار مطلوب'),
  evidenceReference: z.string().trim().min(3, 'مرجع الدليل مطلوب').max(200),
  idempotencyKey,
}).superRefine((value, ctx) => {
  const today = new Date().toISOString().slice(0, 10);
  if (value.decisionDate > today) ctx.addIssue({ code: 'custom', path: ['decisionDate'], message: 'لا يمكن تسجيل قرار بتاريخ مستقبلي' });
});

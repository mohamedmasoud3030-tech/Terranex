import { z } from 'zod';

const uuid = z.string().uuid();
const evidenceReference = z.string().trim()
  .min(3, 'مرجع الدليل مطلوب (3 أحرف على الأقل)')
  .max(200, 'مرجع الدليل طويل جدًا');

export const minorUnitsText = z.string().trim()
  .regex(/^\d{1,19}$/, 'القيمة يجب أن تكون عددًا صحيحًا غير سالب بالوحدات الصغرى');

export const CONDITIONAL_SECTION_CODES = [
  'HISTORICAL_CALLS',
  'HISTORICAL_CONTRIBUTIONS',
  'ACQUISITION_BASIS',
  'DEVELOPMENT_BASELINE',
  'UNPAID_SUPPLIERS',
  'SALES_DISPOSITIONS',
  'HISTORICAL_DISTRIBUTIONS',
  'BANK_STATEMENTS',
] as const;

export const conditionalSectionCode = z.enum(CONDITIONAL_SECTION_CODES);

export const recordFreezeDateSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  freezeDate: z.string().date(),
  evidenceReference,
});

export const declareControlTotalsSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  declaredDebitTotal: minorUnitsText,
  declaredCreditTotal: minorUnitsText,
  evidenceReference,
}).superRefine((value, ctx) => {
  if (value.declaredDebitTotal !== value.declaredCreditTotal) {
    ctx.addIssue({
      code: 'custom',
      path: ['declaredCreditTotal'],
      message: 'إجمالي المدين المعلن يجب أن يساوي إجمالي الدائن. تيرانكس لا تقبل قيد تسوية.',
    });
  }
});

export const recordSetupReferencesSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  agreementTitleOrReference: z.string().trim().max(160).optional().or(z.literal('')),
  organizationEvidenceReference: z.string().trim().max(200).optional().or(z.literal('')),
  projectEvidenceReference: z.string().trim().max(200).optional().or(z.literal('')),
}).superRefine((value, ctx) => {
  const title = value.agreementTitleOrReference?.trim() ?? '';
  const orgEvidence = value.organizationEvidenceReference?.trim() ?? '';
  const projectEvidence = value.projectEvidenceReference?.trim() ?? '';
  if (!title && !orgEvidence && !projectEvidence) {
    ctx.addIssue({
      code: 'custom',
      path: ['agreementTitleOrReference'],
      message: 'أدخل مرجع الاتفاقية أو دليل المنظمة أو دليل نطاق المشروع.',
    });
  }
  if (title && title.length < 2) {
    ctx.addIssue({
      code: 'custom',
      path: ['agreementTitleOrReference'],
      message: 'عنوان الاتفاقية أو مرجعها قصير جدًا.',
    });
  }
  if (orgEvidence && orgEvidence.length < 3) {
    ctx.addIssue({
      code: 'custom',
      path: ['organizationEvidenceReference'],
      message: 'مرجع السجل التجاري قصير جدًا.',
    });
  }
  if (projectEvidence && projectEvidence.length < 3) {
    ctx.addIssue({
      code: 'custom',
      path: ['projectEvidenceReference'],
      message: 'مرجع نطاق المشروع التجريبي قصير جدًا.',
    });
  }
});

export const declareSectionApplicabilitySchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  sectionCode: conditionalSectionCode,
  applicable: z.enum(['true', 'false']),
  reason: z.string().trim().min(3, 'سبب التصنيف مطلوب (3 أحرف على الأقل)').max(500),
  evidenceReference: z.string().trim().max(200).optional().or(z.literal('')),
});

export const reportModellingGapSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  sourceReference: evidenceReference,
  description: z.string().trim().min(3, 'وصف الرصيد مطلوب').max(500),
  amountMinorUnits: minorUnitsText.optional().or(z.literal('')),
  whyUnmappable: z.string().trim()
    .min(3, 'اشرح لماذا لا يناسب أي ترميز افتتاحي معتمد')
    .max(1000),
});

export const acceptModellingGapSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  gapId: uuid,
  resolutionEvidenceReference: evidenceReference,
});

export const recordEvidenceItemSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  evidenceIdentifier: evidenceReference,
  linkedFact: z.string().trim().min(3, 'الحقيقة المرتبطة مطلوبة').max(200),
  customerStorageLocation: z.string().trim()
    .min(3, 'موقع حفظ العميل مطلوب')
    .max(300),
});

export const createAccountingPeriodSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  startDate: z.string().date(),
  endDate: z.string().date(),
}).superRefine((value, ctx) => {
  if (value.startDate > value.endDate) {
    ctx.addIssue({
      code: 'custom',
      path: ['endDate'],
      message: 'تاريخ نهاية الفترة يجب أن يكون في أو بعد تاريخ البداية.',
    });
  }
});

export type RecordFreezeDateInput = z.infer<typeof recordFreezeDateSchema>;
export type DeclareControlTotalsInput = z.infer<typeof declareControlTotalsSchema>;
export type ConditionalSectionCode = z.infer<typeof conditionalSectionCode>;

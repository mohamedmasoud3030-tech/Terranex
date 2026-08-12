import { z } from 'zod';

// GF-009 / S7 — pilot hardening command input contracts.
//
// Every rule here is a client-side convenience mirror of a rule PostgreSQL
// enforces authoritatively. The browser can never be the source of truth for a
// balance, a control total, or an approval right; these schemas only stop
// obviously malformed input from reaching a server command.

const uuid = z.string().uuid();
const idempotencyKey = z.string().trim().min(8, 'مفتاح إعادة المحاولة قصير جدًا').max(120);
const evidenceReference = z.string().trim()
  .min(3, 'مرجع الدليل مطلوب (3 أحرف على الأقل)')
  .max(200, 'مرجع الدليل طويل جدًا');

/** Non-negative integer minor units as exact text; never a JavaScript number. */
export const minorUnitsText = z.string().trim()
  .regex(/^\d{1,19}$/, 'القيمة يجب أن تكون عددًا صحيحًا غير سالب بالوحدات الصغرى');

/** Signed integer minor units as exact text, for an external control total. */
export const signedMinorUnitsText = z.string().trim()
  .regex(/^-?\d{1,19}$/, 'القيمة يجب أن تكون عددًا صحيحًا بالوحدات الصغرى');

export const OPENING_SCHEMA_VERSION = 'S7.OPENING.V1';

export const openingMappingCode = z.enum([
  'OPENING_BANK_CASH',
  'OPENING_DEVELOPMENT_WIP',
  'OPENING_CUSTOMER_RECEIVABLE',
  'OPENING_SUPPLIER_PAYABLE',
  'OPENING_CONTRIBUTED_CAPITAL',
  'OPENING_DISTRIBUTION_PAYABLE',
]);

export const reconciliationCheckpointCode = z.enum([
  'PROJECT_CASH',
  'SUPPLIER_OBLIGATION_POSITION',
  'CUSTOMER_RECEIVABLE_POSITION',
  'REALIZED_RESULT',
  'CONTRIBUTED_CAPITAL',
  'PARTNER_CAPITAL',
  'DISTRIBUTION_PAYABLE',
  'DISTRIBUTION_PAID',
  'INVESTOR_STATEMENT_TOTAL',
]);

export const exceptionSeverity = z.enum(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']);

export const stageOpeningImportSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  schemaVersion: z.literal(OPENING_SCHEMA_VERSION),
  sourceFileName: z.string().trim()
    .min(3, 'اسم ملف المصدر مطلوب')
    .max(200, 'اسم ملف المصدر طويل جدًا'),
  sourceFileChecksum: z.string().trim().toLowerCase()
    .regex(/^[0-9a-f]{64}$/, 'بصمة SHA-256 للملف مطلوبة (64 خانة ست عشرية)'),
  declaredDebitTotal: minorUnitsText,
  declaredCreditTotal: minorUnitsText,
  idempotencyKey,
});

export const openingImportRowSchema = z.object({
  mappingCode: openingMappingCode,
  partyId: uuid.optional().or(z.literal('')),
  cashAccountId: uuid.optional().or(z.literal('')),
  debit: minorUnitsText.or(z.literal('')),
  credit: minorUnitsText.or(z.literal('')),
  description: z.string().trim()
    .min(1, 'وصف السطر مطلوب')
    .max(500, 'وصف السطر طويل جدًا'),
});

export const validateOpeningImportSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  importId: uuid,
  idempotencyKey,
});

export const reviewOpeningImportSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  importId: uuid,
  reviewNotes: z.string().trim().max(2000, 'الملاحظات طويلة جدًا').optional().or(z.literal('')),
  idempotencyKey,
});

export const approveOpeningImportSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  importId: uuid,
  postingDate: z.string().date(),
  idempotencyKey,
});

export const rejectOpeningImportSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  importId: uuid,
  reason: z.string().trim()
    .min(3, 'سبب الرفض مطلوب (3 أحرف على الأقل)')
    .max(2000, 'سبب الرفض طويل جدًا'),
  idempotencyKey,
});

export const recordCheckpointSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  checkpointCode: reconciliationCheckpointCode,
  asOfDate: z.string().date(),
  externalValue: signedMinorUnitsText,
  externalSourceReference: z.string().trim()
    .min(3, 'مرجع المصدر الخارجي مطلوب')
    .max(200, 'مرجع المصدر الخارجي طويل جدًا'),
  externalEvidenceReference: evidenceReference,
  exceptionOwnerId: uuid.optional().or(z.literal('')),
  exceptionSeverity: exceptionSeverity.optional().or(z.literal('')),
  idempotencyKey,
});

export const resolveExceptionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  exceptionId: uuid,
  resolution: z.string().trim()
    .min(3, 'بيان المعالجة مطلوب (3 أحرف على الأقل)')
    .max(2000, 'بيان المعالجة طويل جدًا'),
  evidenceReference,
  idempotencyKey,
});

export const signOffCheckpointSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  checkpointId: uuid,
  evidenceReference,
  idempotencyKey,
});

export const setMembershipStatusSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  userId: uuid,
  status: z.enum(['ACTIVE', 'INACTIVE']),
  reason: z.string().trim()
    .min(3, 'سبب تغيير العضوية مطلوب (3 أحرف على الأقل)')
    .max(500, 'سبب تغيير العضوية طويل جدًا'),
  idempotencyKey,
});

export const registerUatTaskSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  taskCode: z.string().trim().toUpperCase()
    .regex(/^S7-UAT-[A-Z0-9-]{2,40}$/, 'رمز مهمة الاختبار يجب أن يبدأ بـ S7-UAT-'),
  title: z.string().trim().min(3, 'عنوان المهمة مطلوب').max(200, 'عنوان المهمة طويل جدًا'),
  expectedOutcome: z.string().trim()
    .min(3, 'النتيجة المتوقعة مطلوبة')
    .max(2000, 'النتيجة المتوقعة طويلة جدًا'),
  idempotencyKey,
});

export const recordUatExecutionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  taskId: uuid,
  evidenceReference,
  notes: z.string().trim().max(2000, 'الملاحظات طويلة جدًا').optional().or(z.literal('')),
  idempotencyKey,
});

export const acceptUatTaskSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  taskId: uuid,
  acceptanceEvidenceReference: evidenceReference,
  idempotencyKey,
});

export const rejectUatTaskSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  taskId: uuid,
  rejectionReason: z.string().trim()
    .min(3, 'سبب رفض الاختبار مطلوب (3 أحرف على الأقل)')
    .max(2000, 'سبب رفض الاختبار طويل جدًا'),
  idempotencyKey,
});

/**
 * Neutralizes a value that could be interpreted as a formula by spreadsheet
 * software when an operator exports or copies a preview table. PostgreSQL
 * applies the same rule to everything leaving a read model; this mirror exists
 * so client-rendered previews of not-yet-submitted rows are equally safe.
 */
export function exportSafeText(value: string): string {
  return /^[=+@\-\t\r]/.test(value) ? `'${value}` : value;
}

/** One submitted opening row slot exactly as the browser posted it. */
export type OpeningRowSlot = {
  mappingCode: string;
  partyId: string;
  cashAccountId: string;
  debit: string;
  credit: string;
  description: string;
};

/**
 * Drops the opening row slots the operator left completely blank.
 *
 * The staging form renders a fixed number of slots, so an unused slot arrives
 * as an all-empty tuple. Such a slot is not an opening fact and must never be
 * sent to PostgreSQL, where a blank mapping code would be recorded as a
 * rejected `UNKNOWN_MAPPING_CODE` row and would then block approval. A slot
 * that carries any value at all is kept verbatim — including a missing mapping
 * code — so validation reports the real mistake instead of silently discarding
 * an amount the operator typed.
 */
export function compactOpeningRowSlots(rows: OpeningRowSlot[]): OpeningRowSlot[] {
  return rows.filter((row) =>
    [row.mappingCode, row.partyId, row.cashAccountId, row.debit, row.credit, row.description]
      .some((value) => (value ?? '').trim().length > 0));
}

export type StageOpeningImportInput = z.infer<typeof stageOpeningImportSchema>;
export type OpeningImportRowInput = z.infer<typeof openingImportRowSchema>;
export type RecordCheckpointInput = z.infer<typeof recordCheckpointSchema>;
export type SignOffCheckpointInput = z.infer<typeof signOffCheckpointSchema>;
export type SetMembershipStatusInput = z.infer<typeof setMembershipStatusSchema>;
export type RegisterUatTaskInput = z.infer<typeof registerUatTaskSchema>;

import { z } from 'zod';

const uuid = z.string().uuid('معرّف غير صالح');
const optionalText = (max: number) => z.preprocess(
  (value) => {
    if (value === undefined || value === null) return null;
    if (typeof value === 'string' && value.trim() === '') return null;
    return value;
  },
  z.string().trim().max(max).nullable().optional(),
);
const idempotencyKey = z.string().trim().min(8).max(120, 'مفتاح العملية يجب أن يكون بين 8 و 120 حرفًا');

const areaUnit = z.enum(['M2', 'HECTARE', 'FEDDAN']);

const areaQuantity = z.string().trim().regex(/^(?:[1-9]\d{0,13})(?:\.\d{1,6})?$/, 'أدخل مساحة موجبة حتى 6 خانات عشرية')
  .refine((v) => Number(v) > 0, 'أدخل مساحة موجبة حتى 6 خانات عشرية');

export const agricultureProfileSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  notes: optionalText(2000),
  idempotencyKey,
});

export const farmSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  name: z.string().trim().min(2, 'اسم المزرعة مطلوب').max(160),
  internalReference: optionalText(80),
  operatingLocation: optionalText(200),
  tenureDescription: optionalText(1000),
  timezone: z.string().trim().min(1, 'المنطقة الزمنية مطلوبة').max(64),
  mapReference: optionalText(200),
  idempotencyKey,
});

export const fieldSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  farmId: uuid,
  identifier: z.string().trim().min(1, 'معرّف الحقل مطلوب').max(100),
  areaQuantity: areaQuantity,
  areaUnit,
  soilNotes: optionalText(2000),
  irrigationNotes: optionalText(2000),
  idempotencyKey,
});

const dateRequired = z.string().min(1, 'التاريخ مطلوب');
const yieldQuantity = z.preprocess(
  (value) => {
    if (value === undefined || value === null) return null;
    if (typeof value === 'string' && value.trim() === '') return null;
    return value;
  },
  z.string().trim().regex(/^(?:[1-9]\d{0,13})(?:\.\d{1,6})?$/).nullable().optional(),
);
const yieldUnit = optionalText(40);

export const cropCycleSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  crop: z.string().trim().min(2, 'المحصول مطلوب').max(80),
  variety: optionalText(80),
  seasonReference: z.string().trim().min(2, 'مرجع الموسم مطلوب').max(80),
  plannedStartDate: dateRequired,
  plannedEndDate: dateRequired,
  targetYieldQuantity: yieldQuantity,
  targetYieldUnit: yieldUnit,
  idempotencyKey,
}).superRefine((data, ctx) => {
  if ((data.targetYieldQuantity === null) !== (data.targetYieldUnit === null)) {
    ctx.addIssue({ code: 'custom', path: ['targetYieldQuantity'], message: 'كمية المحصول المستهدف ووحدتها يجب إدخالهما معًا' });
  }
  if (data.plannedEndDate < data.plannedStartDate) {
    ctx.addIssue({ code: 'custom', path: ['plannedEndDate'], message: 'تاريخ النهاية يجب أن يكون بعد أو يساوي تاريخ البداية' });
  }
});

export const cropAssignmentSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  cropCycleId: uuid,
  fieldId: uuid,
  assignedAreaQuantity: areaQuantity,
  assignedAreaUnit: areaUnit,
  plannedStartDate: dateRequired,
  plannedEndDate: dateRequired,
  idempotencyKey,
}).superRefine((data, ctx) => {
  if (data.plannedEndDate < data.plannedStartDate) {
    ctx.addIssue({ code: 'custom', path: ['plannedEndDate'], message: 'تاريخ النهاية يجب أن يكون بعد أو يساوي تاريخ البداية' });
  }
});

export const CYCLE_STATES = ['PLANNED', 'ESTABLISHED', 'GROWING', 'HARVESTING', 'CLOSED', 'CANCELLED', 'FAILED'] as const;
export const CYCLE_TRANSITIONS: Record<typeof CYCLE_STATES[number], ReadonlyArray<typeof CYCLE_STATES[number]>> = {
  PLANNED:     ['ESTABLISHED', 'CANCELLED'],
  ESTABLISHED: ['GROWING'],
  GROWING:     ['HARVESTING', 'FAILED'],
  HARVESTING:  ['CLOSED'],
  CLOSED:      [],
  CANCELLED:   [],
  FAILED:      [],
};

export const cycleTransitionSchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  cropCycleId: uuid,
  expectedState: z.enum(CYCLE_STATES),
  newState: z.enum(CYCLE_STATES),
  reason: z.string().trim().min(3, 'سبب الانتقال مطلوب').max(500),
  evidenceReference: optionalText(200),
  idempotencyKey,
}).superRefine((data, ctx) => {
  const allowed = CYCLE_TRANSITIONS[data.expectedState] ?? [];
  if (!allowed.includes(data.newState)) {
    ctx.addIssue({
      code: 'custom',
      path: ['newState'],
      message: `الانتقال من ${data.expectedState} إلى ${data.newState} غير مسموح وفق دورة حياة المحصول`,
    });
  }
});

export type AgricultureProfileInput = z.infer<typeof agricultureProfileSchema>;
export type FarmInput = z.infer<typeof farmSchema>;
export type FieldInput = z.infer<typeof fieldSchema>;
export type CropCycleInput = z.infer<typeof cropCycleSchema>;
export type CropAssignmentInput = z.infer<typeof cropAssignmentSchema>;
export const FIELD_ACTIVITY_TYPES = [
  'PREPARE', 'PLANT', 'IRRIGATE', 'FERTILIZE', 'SPRAY', 'SCOUT', 'WEED', 'OTHER',
] as const;

const activityQuantity = z.preprocess(
  (value) => {
    if (value === undefined || value === null) return null;
    if (typeof value === 'string' && value.trim() === '') return null;
    return value;
  },
  z.string().trim().regex(/^(?:[1-9]\d{0,13})(?:\.\d{1,6})?$/).nullable().optional(),
);

export const fieldActivitySchema = z.object({
  organizationId: uuid,
  projectId: uuid,
  cropCycleId: uuid,
  fieldId: uuid,
  assignmentId: uuid,
  activityDate: dateRequired,
  activityType: z.enum(FIELD_ACTIVITY_TYPES, { message: 'نوع النشاط غير صالح' }),
  quantity: activityQuantity,
  unit: optionalText(40),
  notes: optionalText(2000),
  evidenceReference: optionalText(200),
  idempotencyKey,
}).superRefine((data, ctx) => {
  const hasQty = data.quantity != null;
  const hasUnit = data.unit != null;
  if (hasQty !== hasUnit) {
    ctx.addIssue({
      code: 'custom',
      path: ['quantity'],
      message: 'الكمية ووحدتها يجب إدخالهما معًا أو تركهما معًا',
    });
  }
});

export type CycleTransitionInput = z.infer<typeof cycleTransitionSchema>;
export type FieldActivityInput = z.infer<typeof fieldActivitySchema>;

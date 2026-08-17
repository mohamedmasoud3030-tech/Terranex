import { z } from 'zod';

export const SECTORS = ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK'] as const;

const idempotencyKey = z
  .string()
  .trim()
  .min(8, 'مفتاح العملية غير صالح')
  .max(120, 'مفتاح العملية غير صالح');

export const projectSchema = z.object({
  organizationId: z.string().uuid(),
  sector: z.enum(SECTORS),
  name: z.string().trim().min(2, 'اسم المشروع مطلوب').max(160),
  internalReference: z.string().trim().max(80).optional().or(z.literal('')),
  description: z.string().trim().max(2000).optional().or(z.literal('')),
  idempotencyKey,
});
export type ProjectInput = z.infer<typeof projectSchema>;

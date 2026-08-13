import { z } from 'zod';

export const SECTORS = ['REAL_ESTATE', 'AGRICULTURE'] as const;

export const projectSchema = z.object({
  organizationId: z.string().uuid(),
  sector: z.enum(SECTORS),
  name: z.string().trim().min(2, 'اسم المشروع مطلوب').max(160),
  internalReference: z.string().trim().max(80).optional().or(z.literal('')),
  description: z.string().trim().max(2000).optional().or(z.literal('')),
});
export type ProjectInput = z.infer<typeof projectSchema>;

import { z } from 'zod';
export const projectSchema = z.object({ organizationId: z.string().uuid(), name: z.string().trim().min(2, 'اسم المشروع مطلوب').max(160), internalReference: z.string().trim().max(80).optional().or(z.literal('')), description: z.string().trim().max(2000).optional().or(z.literal('')) });
export type ProjectInput = z.infer<typeof projectSchema>;

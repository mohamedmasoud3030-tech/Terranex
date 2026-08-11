import { z } from 'zod';
export const organizationSchema = z.object({ name: z.string().trim().min(2, 'اسم المنظمة مطلوب').max(120, 'الاسم طويل جدًا') });

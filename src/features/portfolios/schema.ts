import { z } from 'zod';

/**
 * R1 — Portfolio Foundation validation.
 *
 * Portfolio is a management/reporting parent only. These schemas accept
 * nothing but safe management metadata: identity, management purpose,
 * lifecycle intent, and membership commands. No ownership, capital,
 * investor, fee, or economic field exists here by design
 * (docs/OPEN_BUSINESS_DECISIONS.md BD-001 … BD-012 remain OPEN).
 */

export const PORTFOLIO_STATUSES = ['DRAFT', 'ACTIVE', 'ARCHIVED'] as const;
export type PortfolioStatus = (typeof PORTFOLIO_STATUSES)[number];

const idempotencyKey = z
  .string()
  .trim()
  .min(8, 'مفتاح العملية غير صالح')
  .max(120, 'مفتاح العملية غير صالح');

const managerId = z
  .string()
  .uuid('المدير المسؤول غير صالح')
  .optional()
  .or(z.literal(''));

export const createPortfolioSchema = z.object({
  organizationId: z.string().uuid(),
  name: z.string().trim().min(2, 'اسم المحفظة مطلوب').max(120, 'اسم المحفظة طويل جدًا'),
  description: z.string().trim().max(2000).optional().or(z.literal('')),
  responsibleManagerId: managerId,
  idempotencyKey,
});
export type CreatePortfolioInput = z.infer<typeof createPortfolioSchema>;

export const updatePortfolioSchema = z.object({
  organizationId: z.string().uuid(),
  portfolioId: z.string().uuid(),
  name: z.string().trim().min(2, 'اسم المحفظة مطلوب').max(120, 'اسم المحفظة طويل جدًا'),
  description: z.string().trim().max(2000).optional().or(z.literal('')),
  responsibleManagerId: managerId,
  idempotencyKey,
});
export type UpdatePortfolioInput = z.infer<typeof updatePortfolioSchema>;

export const portfolioTransitionSchema = z.object({
  organizationId: z.string().uuid(),
  portfolioId: z.string().uuid(),
  expectedStatus: z.enum(PORTFOLIO_STATUSES),
  newStatus: z.enum(PORTFOLIO_STATUSES),
  reason: z
    .string()
    .trim()
    .min(3, 'سبب تغيير الحالة مطلوب (٣ أحرف على الأقل)')
    .max(500, 'سبب تغيير الحالة طويل جدًا'),
  idempotencyKey,
});
export type PortfolioTransitionInput = z.infer<typeof portfolioTransitionSchema>;

export const assignProjectSchema = z.object({
  organizationId: z.string().uuid(),
  portfolioId: z.string().uuid(),
  projectId: z.string().uuid('اختر مشروعًا من قائمة المشاريع'),
  idempotencyKey,
});
export type AssignProjectInput = z.infer<typeof assignProjectSchema>;

export const removeProjectSchema = z.object({
  organizationId: z.string().uuid(),
  portfolioId: z.string().uuid(),
  projectId: z.string().uuid(),
  reason: z
    .string()
    .trim()
    .min(3, 'سبب الإزالة مطلوب (٣ أحرف على الأقل)')
    .max(500, 'سبب الإزالة طويل جدًا'),
  idempotencyKey,
});
export type RemoveProjectInput = z.infer<typeof removeProjectSchema>;

export const moveProjectSchema = z.object({
  organizationId: z.string().uuid(),
  projectId: z.string().uuid(),
  targetPortfolioId: z.string().uuid('اختر محفظة وجهة من القائمة'),
  reason: z
    .string()
    .trim()
    .min(3, 'سبب النقل مطلوب (٣ أحرف على الأقل)')
    .max(500, 'سبب النقل طويل جدًا'),
  idempotencyKey,
});
export type MoveProjectInput = z.infer<typeof moveProjectSchema>;

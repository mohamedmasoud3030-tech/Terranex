import { z } from 'zod';

const uuid = z.string().uuid('معرّف غير صالح');
const idempotencyKey = z.string().trim().min(8).max(120);
const optionalUuid = z.preprocess(
  (value) => (value === '' ? null : value),
  z.string().uuid().nullable(),
);

export const DOCUMENT_CATEGORIES = [
  'CONTRACT',
  'LICENSE',
  'CERTIFICATE',
  'CORRESPONDENCE',
  'FINANCIAL',
  'GENERAL',
] as const;

export const generalDocumentSchema = z.object({
  organizationId: uuid,
  projectId: optionalUuid,
  documentId: optionalUuid,
  category: z.enum(DOCUMENT_CATEGORIES),
  title: z.string().trim().min(3, 'عنوان المستند مطلوب').max(200, 'العنوان طويل جدًا'),
  idempotencyKey,
});

import { describe, expect, it } from 'vitest';
import { DOCUMENT_CATEGORIES, generalDocumentSchema } from '../src/features/documents/schema';
import { DOCUMENT_CATEGORY_LABEL } from '../src/features/documents/labels';

const ORG = '10000000-0000-4000-8000-000000000201';
const PROJECT = '20000000-0000-4000-8000-000000000201';

describe('general document validation', () => {
  it('accepts an org-level upload without a project', () => {
    const parsed = generalDocumentSchema.safeParse({
      organizationId: ORG,
      projectId: '',
      documentId: '',
      category: 'CONTRACT',
      title: 'عقد إيجار المحل',
      idempotencyKey: 'gd-upload-test-0001',
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.projectId).toBeNull();
      expect(parsed.data.documentId).toBeNull();
    }
  });

  it('accepts a project-linked upload', () => {
    expect(generalDocumentSchema.safeParse({
      organizationId: ORG,
      projectId: PROJECT,
      documentId: '',
      category: 'LICENSE',
      title: 'ترخيص المشروع',
      idempotencyKey: 'gd-upload-test-0002',
    }).success).toBe(true);
  });

  it('rejects unknown categories, bad titles and short command keys', () => {
    expect(generalDocumentSchema.safeParse({
      organizationId: ORG, projectId: '', documentId: '',
      category: 'OTHER', title: 'عنوان صالح', idempotencyKey: 'gd-upload-test-0003',
    }).success).toBe(false);
    expect(generalDocumentSchema.safeParse({
      organizationId: ORG, projectId: '', documentId: '',
      category: 'GENERAL', title: 'ab', idempotencyKey: 'gd-upload-test-0004',
    }).success).toBe(false);
    expect(generalDocumentSchema.safeParse({
      organizationId: ORG, projectId: '', documentId: '',
      category: 'GENERAL', title: 'عنوان صالح', idempotencyKey: 'short',
    }).success).toBe(false);
  });

  it('labels every category in Arabic', () => {
    for (const category of DOCUMENT_CATEGORIES) {
      expect(DOCUMENT_CATEGORY_LABEL[category]).toBeTruthy();
      expect(DOCUMENT_CATEGORY_LABEL[category]).not.toBe(category);
    }
  });
});

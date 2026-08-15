// @vitest-environment jsdom
import { describe, expect, it, vi } from 'vitest';
import { renderToString } from 'react-dom/server';
import {
  approvePurchaseOrderSchema,
  purchaseOrderSchema,
  purchaseRequestSchema,
  submitPurchaseRequestSchema,
  supplierSchema,
} from '@/features/procurement/schema';
import { sectionsFor } from '@/features/workspace/nav';
import { PurchaseOrderForm, PurchaseRequestForm, SupplierForm } from '@/app/(app)/projects/[projectId]/procurement/forms';

vi.mock('@/features/procurement/actions', () => ({
  createSupplier: vi.fn(),
  createPurchaseRequest: vi.fn(),
  createPurchaseOrder: vi.fn(),
  submitPurchaseRequest: vi.fn(),
  approvePurchaseRequest: vi.fn(),
  submitPurchaseOrder: vi.fn(),
  approvePurchaseOrder: vi.fn(),
}));

const org = '10000000-0000-4000-8000-000000000001';
const project = '20000000-0000-4000-8000-000000000002';
const lines = JSON.stringify([
  { itemDescription: 'سماد يوريا', quantity: '100', unit: 'كجم' },
  { itemDescription: 'مبيد حشري', quantity: '20', unit: 'لتر' },
]);

describe('GF-025 / R4 Procurement Foundation', () => {
  it('supplier schema accepts a valid supplier and rejects empty name', () => {
    const ok = supplierSchema.safeParse({
      organizationId: org,
      name: 'مورد الأسمدة المصرية',
      idempotencyKey: 'gf25-test-key-001',
    });
    expect(ok.success).toBe(true);
    const bad = supplierSchema.safeParse({ organizationId: org, name: '', idempotencyKey: 'gf25-test-key-002' });
    expect(bad.success).toBe(false);
  });

  it('purchase request requires at least one line and positive quantity', () => {
    const good = purchaseRequestSchema.safeParse({
      organizationId: org,
      projectId: project,
      internalReference: 'PR-001',
      linesJson: lines,
      idempotencyKey: 'gf25-pr-key-001',
    });
    expect(good.success).toBe(true);

    const noLines = purchaseRequestSchema.safeParse({
      organizationId: org,
      projectId: project,
      internalReference: 'PR-002',
      linesJson: JSON.stringify([]),
      idempotencyKey: 'gf25-pr-key-002',
    });
    expect(noLines.success).toBe(false);

    const negativeQty = purchaseRequestSchema.safeParse({
      organizationId: org,
      projectId: project,
      internalReference: 'PR-003',
      linesJson: JSON.stringify([{ itemDescription: 'شيء', quantity: '-5', unit: 'قطعة' }]),
      idempotencyKey: 'gf25-pr-key-003',
    });
    expect(negativeQty.success).toBe(false);
  });

  it('purchase order accepts an optional supplier and future delivery date', () => {
    const good = purchaseOrderSchema.safeParse({
      organizationId: org,
      projectId: project,
      internalReference: 'PO-001',
      supplierId: '30000000-0000-4000-8000-000000000003',
      linesJson: lines,
      idempotencyKey: 'gf25-po-key-001',
    });
    expect(good.success).toBe(true);
  });

  it('document action schemas carry the request/order id', () => {
    const ok = submitPurchaseRequestSchema.safeParse({
      organizationId: org,
      projectId: project,
      purchaseRequestId: project,
      idempotencyKey: 'gf25-act-key-001',
    });
    expect(ok.success).toBe(true);
    const bad = approvePurchaseOrderSchema.safeParse({
      organizationId: org,
      projectId: project,
      purchaseOrderId: 'not-a-uuid',
      idempotencyKey: 'gf25-act-key-002',
    });
    expect(bad.success).toBe(false);
  });

  it('adds the procurement section to every sector workspace', () => {
    for (const sector of ['REAL_ESTATE', 'AGRICULTURE', 'LIVESTOCK'] as const) {
      expect(sectionsFor(sector).map((s) => s.id)).toContain('procurement');
    }
  });

  it('renders the procurement command forms with an idempotency key', () => {
    const supplierHtml = renderToString(<SupplierForm organizationId={org} projectId={project} />);
    expect(supplierHtml).toMatch(/name="idempotencyKey"/);

    const requestHtml = renderToString(<PurchaseRequestForm organizationId={org} projectId={project} />);
    expect(requestHtml).toMatch(/name="idempotencyKey"/);

    const orderHtml = renderToString(<PurchaseOrderForm organizationId={org} projectId={project} suppliers={[]} requests={[]} />);
    expect(orderHtml).toMatch(/name="idempotencyKey"/);
  });
});

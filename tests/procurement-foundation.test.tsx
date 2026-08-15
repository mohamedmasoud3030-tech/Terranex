// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToString } from 'react-dom/server';
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import type { ActionState } from '@/features/auth/actions';
import { createSupplier } from '@/features/procurement/actions';
import {
  approvePurchaseOrderSchema,
  purchaseOrderSchema,
  purchaseReceiptSchema,
  purchaseRequestSchema,
  submitPurchaseRequestSchema,
  supplierSchema,
} from '@/features/procurement/schema';
import { sectionsFor } from '@/features/workspace/nav';
import {
  PurchaseOrderForm,
  PurchaseRequestForm,
  ReceiptForm,
  SupplierForm,
} from '@/app/(app)/projects/[projectId]/procurement/forms';

vi.mock('@/features/procurement/actions', () => ({
  createSupplier: vi.fn(),
  createPurchaseRequest: vi.fn(),
  createPurchaseOrder: vi.fn(),
  submitPurchaseRequest: vi.fn(),
  approvePurchaseRequest: vi.fn(),
  submitPurchaseOrder: vi.fn(),
  approvePurchaseOrder: vi.fn(),
  createPurchaseReceipt: vi.fn(),
}));

const org = '10000000-0000-4000-8000-000000000001';
const project = '20000000-0000-4000-8000-000000000002';
const nonce = '99999999-aaaa-4bbb-8ccc-000000000099';
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

  it('renders the procurement command forms with a canonical idempotency key', () => {
    const supplierHtml = renderToString(<SupplierForm organizationId={org} projectId={project} serverNonce={nonce} />);
    expect(supplierHtml).toMatch(/name="idempotencyKey"/);
    // The server nonce makes the first key deterministic (no client-render randomness).
    expect(supplierHtml).toContain(`value="gf25-supplier-${nonce}-0"`);

    const requestHtml = renderToString(<PurchaseRequestForm organizationId={org} projectId={project} serverNonce={nonce} />);
    expect(requestHtml).toMatch(/name="idempotencyKey"/);

    const orderHtml = renderToString(<PurchaseOrderForm organizationId={org} projectId={project} suppliers={[]} requests={[]} serverNonce={nonce} />);
    expect(orderHtml).toMatch(/name="idempotencyKey"/);
  });

  it('receiving schema requires positive quantity and rejects empty lines', () => {
    const orderLineId = '30000000-0000-4000-8000-000000000003';
    const good = purchaseReceiptSchema.safeParse({
      organizationId: org,
      projectId: project,
      purchaseOrderId: '30000000-0000-4000-8000-000000000004',
      evidenceReference: 'سند استلام-001',
      linesJson: JSON.stringify([{ purchaseOrderLineId: orderLineId, quantityReceived: '40' }]),
      idempotencyKey: 'gf26-rec-key-001',
    });
    expect(good.success).toBe(true);

    const noLines = purchaseReceiptSchema.safeParse({
      organizationId: org,
      projectId: project,
      purchaseOrderId: '30000000-0000-4000-8000-000000000004',
      evidenceReference: 'سند استلام-002',
      linesJson: JSON.stringify([]),
      idempotencyKey: 'gf26-rec-key-002',
    });
    expect(noLines.success).toBe(false);

    const missingEvidence = purchaseReceiptSchema.safeParse({
      organizationId: org,
      projectId: project,
      purchaseOrderId: '30000000-0000-4000-8000-000000000004',
      evidenceReference: 'ab',
      linesJson: JSON.stringify([{ purchaseOrderLineId: orderLineId, quantityReceived: '1' }]),
      idempotencyKey: 'gf26-rec-key-003',
    });
    expect(missingEvidence.success).toBe(false);
  });

  it('renders the receiving form with an idempotency key', () => {
    const order = {
      id: '30000000-0000-4000-8000-000000000004',
      organization_id: org,
      project_id: project,
      internal_reference: 'PO-1',
      supplier_id: null,
      supplier_name: null,
      source_purchase_request_id: null,
      description: null,
      status: 'APPROVED' as const,
      expected_delivery_date: null,
      requested_by: 'x',
      submitted_by: null,
      submitted_at: null,
      approved_by: null,
      approved_at: null,
      rejection_reason: null,
      created_at: '2026-01-01T00:00:00Z',
      line_count: 1,
    };
    const lines = [{
      id: '30000000-0000-4000-8000-000000000003',
      organization_id: org,
      project_id: project,
      purchase_order_id: order.id,
      item_description: 'علف ذرة',
      quantity: '100',
      unit: 'كجم',
      notes: null,
      created_at: '2026-01-01T00:00:00Z',
    }];
    const html = renderToString(<ReceiptForm organizationId={org} projectId={project} order={order} lines={lines} serverNonce={nonce} />);
    expect(html).toMatch(/name="idempotencyKey"/);
    expect(html).toMatch(/علف ذرة/);
  });
});

describe('R4 idempotency-key lifecycle (SupplierForm integration)', () => {
  beforeEach(() => {
    vi.mocked(createSupplier).mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  const keyAt = (successCount: number) => `gf25-supplier-${nonce}-${successCount}`;

  function formElement(container: HTMLElement): HTMLFormElement {
    const form = container.querySelector('form');
    if (!form) throw new Error('form not found');
    return form;
  }

  function currentKey(container: HTMLElement): string {
    const input = container.querySelector<HTMLInputElement>('input[name="idempotencyKey"]');
    return input?.value ?? '';
  }

  function submitButton(): HTMLButtonElement {
    return screen.getByRole('button', { name: 'تسجيل المورد' }) as HTMLButtonElement;
  }

  async function submitAndSettle(container: HTMLElement) {
    fireEvent.submit(formElement(container));
    await waitFor(() => expect(submitButton().disabled).toBe(false));
  }

  function fillSupplier(container: HTMLElement, name: string) {
    const nameInput = container.querySelector<HTMLInputElement>('input[name="name"]');
    if (!nameInput) throw new Error('Supplier input not found');
    fireEvent.change(nameInput, { target: { value: name } });
  }

  it('CASE A: a failed attempt preserves the same key for the retried command', async () => {
    const submitted: string[] = [];
    vi.mocked(createSupplier).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return { error: 'تعذر تسجيل المورد.', successCount: prev.successCount ?? 0 };
    });

    const { container } = render(
      <SupplierForm organizationId={org} projectId={project} serverNonce={nonce} />,
    );
    expect(currentKey(container)).toBe(keyAt(0));

    fillSupplier(container, 'مورد الاختبار');
    await act(async () => {
      await submitAndSettle(container);
    });
    await act(async () => {
      await submitAndSettle(container);
    });

    expect(submitted).toHaveLength(2);
    expect(submitted[0]).toBe(keyAt(0));
    expect(submitted[1]).toBe(keyAt(0));
  });

  it('CASE B: a confirmed success rotates the key for the next logical command', async () => {
    const submitted: string[] = [];
    vi.mocked(createSupplier).mockImplementation(async (prev, formData) => {
      submitted.push(String(formData.get('idempotencyKey')));
      return { successCount: (prev.successCount ?? 0) + 1 };
    });

    const { container } = render(
      <SupplierForm organizationId={org} projectId={project} serverNonce={nonce} />,
    );
    expect(currentKey(container)).toBe(keyAt(0));

    fillSupplier(container, 'مورد أول');
    await act(async () => {
      await submitAndSettle(container);
    });
    expect(currentKey(container)).toBe(keyAt(1));

    fillSupplier(container, 'مورد ثانٍ');
    await act(async () => {
      await submitAndSettle(container);
    });

    expect(submitted).toHaveLength(2);
    expect(submitted[0]).toBe(keyAt(0));
    expect(submitted[1]).toBe(keyAt(1));
  });
});

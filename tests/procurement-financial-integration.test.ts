import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { supplierInvoiceSchema, supplierPaymentSchema } from '@/features/procurement/schema';

const migration = fs.readFileSync(path.join(process.cwd(), 'supabase/migrations/20260815034000_r4_procurement_financial_integration.sql'), 'utf8');
const org = '10000000-0000-4000-8000-000000000001';
const project = '20000000-0000-4000-8000-000000000002';
const id = '30000000-0000-4000-8000-000000000003';

describe('R4 procurement financial integration contract', () => {
  it('validates received-basis invoice lines and exact-money payment input', () => {
    expect(supplierInvoiceSchema.safeParse({
      organizationId: org, projectId: project, purchaseOrderId: id,
      invoiceReference: 'INV-1', invoiceDate: '2026-08-15', currency: 'EGP',
      costTreatment: 'EXPENSE', evidenceReference: 'فاتورة موثقة',
      linesJson: JSON.stringify([{ purchaseReceiptLineId: id, quantityInvoiced: '2.5', unitPrice: '100.00' }]),
      idempotencyKey: 'r4-invoice-key-1',
    }).success).toBe(true);
    expect(supplierPaymentSchema.safeParse({
      organizationId: org, projectId: project, obligationId: id, cashAccountId: id,
      amount: '100.25', currency: 'EGP', paymentDate: '2026-08-15', idempotencyKey: 'r4-payment-key-1',
    }).success).toBe(true);
    expect(supplierPaymentSchema.safeParse({
      organizationId: org, projectId: project, obligationId: id, cashAccountId: id,
      amount: '100.251', currency: 'EGP', paymentDate: '2026-08-15', idempotencyKey: 'r4-payment-key-2',
    }).success).toBe(false);
  });

  it('derives commercial totals in PostgreSQL and never accepts browser totals', () => {
    expect(migration).toContain('line_amount_minor_units bigint generated always as');
    expect(migration).toContain('purchase order commercial total must be positive');
    expect(migration).not.toMatch(/p_(?:line_)?total_minor_units/);
  });

  it('keeps order commitment unposted and creates payables only from approved invoices', () => {
    expect(migration).toContain("'UNPOSTED_PURCHASE_COMMITMENT'::text as accounting_effect");
    expect(migration).toContain('insert into public.cost_obligations');
    expect(migration).toContain('public.authorize_cost_obligation');
    expect(migration).toContain('source_supplier_invoice_id');
  });

  it('reuses shared payment and bank reconciliation truth', () => {
    expect(migration).toContain('public.payment_status_read');
    expect(migration).toContain("'PAID_UNRECONCILED'");
    expect(migration).toContain("'RECONCILED'");
    expect(migration).not.toMatch(/create table public\.(procurement_payments|procurement_payables|procurement_ledger)/);
  });

  it('structurally enforces tenant/project coherence and locks financial ceilings', () => {
    expect(migration).toContain('foreign key (purchase_order_id, supplier_id, project_id, organization_id)');
    expect(migration).toContain('foreign key (supplier_invoice_id, purchase_order_id, project_id, organization_id)');
    expect(migration).toContain('for update;');
    expect(migration).toContain('supplier invoice quantity exceeds remaining received quantity');
  });

  it('keeps invoice and posting correction append-only', () => {
    expect(migration).toContain('supplier invoice is immutable after recording');
    expect(migration).toContain('supplier_invoice_lines_append_only');
    expect(migration).not.toMatch(/delete from public\.(supplier_invoices|cost_obligations|project_payments)/);
  });
});

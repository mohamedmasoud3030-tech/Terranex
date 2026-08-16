import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { supplierInvoiceSchema, supplierPaymentSchema } from '@/features/procurement/schema';

const migration = fs.readFileSync(path.join(process.cwd(), 'supabase/migrations/20260815034000_r4_procurement_financial_integration.sql'), 'utf8');
const p2Migration = fs.readFileSync(path.join(process.cwd(), 'supabase/migrations/20260816000100_p2_vendor_finance_hardening.sql'), 'utf8');
const historicalS2Suite = fs.readFileSync(path.join(process.cwd(), 'supabase/tests/04_s2_cost_and_cash.sql'), 'utf8');
const historicalPhase2CSuite = fs.readFileSync(path.join(process.cwd(), 'supabase/tests/28_phase2c_financial_integrity.sql'), 'utf8');
const r4Suite = fs.readFileSync(path.join(process.cwd(), 'supabase/tests/83_r4_procurement_financial_integration.sql'), 'utf8');
const org = '10000000-0000-4000-8000-000000000001';
const project = '20000000-0000-4000-8000-000000000002';
const id = '30000000-0000-4000-8000-000000000003';

describe('R4 procurement financial integration contract', () => {
  it('validates received-basis invoice lines, independent supplier total, and exact-money payment input', () => {
    expect(supplierInvoiceSchema.safeParse({
      organizationId: org, projectId: project, purchaseOrderId: id,
      invoiceReference: 'INV-1', invoiceDate: '2026-08-15', currency: 'EGP',
      costTreatment: 'EXPENSE', evidenceReference: 'فاتورة موثقة', supplierStatedTotal: '250.00',
      linesJson: JSON.stringify([{ purchaseReceiptLineId: id, quantityInvoiced: '2.5', unitPrice: '100.00' }]),
      idempotencyKey: 'r4-invoice-key-1',
    }).success).toBe(true);
    expect(supplierInvoiceSchema.safeParse({
      organizationId: org, projectId: project, purchaseOrderId: id,
      invoiceReference: 'INV-2', invoiceDate: '2026-08-15', currency: 'EGP',
      costTreatment: 'EXPENSE', evidenceReference: 'فاتورة موثقة',
      linesJson: JSON.stringify([{ purchaseReceiptLineId: id, quantityInvoiced: '2.5', unitPrice: '100.00' }]),
      idempotencyKey: 'r4-invoice-key-2',
    }).success).toBe(false);
    expect(supplierPaymentSchema.safeParse({
      organizationId: org, projectId: project, obligationId: id, cashAccountId: id,
      amount: '100.25', currency: 'EGP', paymentDate: '2026-08-15', idempotencyKey: 'r4-payment-key-1',
    }).success).toBe(true);
    expect(supplierPaymentSchema.safeParse({
      organizationId: org, projectId: project, obligationId: id, cashAccountId: id,
      amount: '100.251', currency: 'EGP', paymentDate: '2026-08-15', idempotencyKey: 'r4-payment-key-2',
    }).success).toBe(false);
  });

  it('keeps calculated totals server-derived while separately capturing the supplier document total', () => {
    expect(migration).toContain('line_amount_minor_units bigint generated always as');
    expect(migration).toContain('purchase order commercial total must be positive');
    expect(migration).not.toMatch(/p_(?:line_)?total_minor_units/);
    expect(p2Migration).toContain('supplier_stated_total_minor_units');
    expect(p2Migration).toContain('supplier stated total is required for every supplier invoice');
    expect(p2Migration).toContain('does not match calculated total');
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

  it('requires a shared Finance maker/checker proposal and sufficient locked cash', () => {
    expect(migration).toContain('create table public.cost_payment_proposals');
    expect(migration).toContain('maker/checker: payment preparer cannot approve');
    expect(migration).toContain('for update;');
    expect(migration).toContain('payment exceeds available cash');
    expect(migration).toContain("select * into v_account from public.project_cash_accounts");
    expect(migration).toContain('direct payment posting disabled; prepare and approve a payment proposal');
    expect(migration).toMatch(/revoke all on function public\.pay_cost_obligation[\s\S]*from public, anon, authenticated/);
    expect(migration).toContain('public.prepare_cost_payment');
    expect(migration).toContain('public.approve_cost_payment');
  });

  it('keeps historical payment fixtures replayable without weakening current R4 proofs', () => {
    const paymentSignature = 'public.prepare_cost_payment(uuid,uuid,uuid,bigint,date,text)';
    expect(historicalS2Suite).toContain(`to_regprocedure('${paymentSignature}') is null`);
    expect(historicalS2Suite).toContain("execute 'select public.pay_cost_obligation($1,$2,$3,$4,$5,$6)'");
    expect(historicalS2Suite).toContain("execute 'select public.prepare_cost_payment($1,$2,$3,$4,$5,$6)'");
    expect(historicalPhase2CSuite).toContain(`to_regprocedure('${paymentSignature}') is null`);
    expect(r4Suite).toContain('s83_payment_member_cannot_approve');
    expect(r4Suite).toContain('s83_payment_maker_checker_persisted');
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

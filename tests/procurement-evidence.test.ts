import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { procurementEvidenceSchema } from '@/features/procurement/schema';

const migration = fs.readFileSync(
  path.join(process.cwd(), 'supabase/migrations/20260815035000_r4_procurement_contracts_evidence.sql'),
  'utf8',
);
const org = '10000000-0000-4000-8000-000000000001';
const project = '20000000-0000-4000-8000-000000000002';
const subject = '30000000-0000-4000-8000-000000000003';

describe('R4 Procurement Contracts & Evidence Closure', () => {
  it('accepts only one typed Procurement subject', () => {
    expect(procurementEvidenceSchema.safeParse({
      organizationId: org, projectId: project, classification: 'CONTRACT',
      title: 'عقد توريد معتمد', purchaseOrderId: subject, idempotencyKey: 'evidence-key-001',
    }).success).toBe(true);
    expect(procurementEvidenceSchema.safeParse({
      organizationId: org, projectId: project, classification: 'RECEIPT',
      title: 'سند استلام', purchaseOrderId: subject, idempotencyKey: 'evidence-key-002',
    }).success).toBe(false);
    expect(procurementEvidenceSchema.safeParse({
      organizationId: org, projectId: project, classification: 'SUPPLIER_INVOICE',
      title: 'فاتورة', purchaseReceiptId: subject, supplierInvoiceId: subject,
      idempotencyKey: 'evidence-key-003',
    }).success).toBe(false);
  });

  it('uses a private bounded bucket and immutable version metadata', () => {
    expect(migration).toContain("'procurement-evidence', 'procurement-evidence', false, 10485760");
    expect(migration).toContain("'application/pdf','image/jpeg','image/png'");
    expect(migration).toContain('procurement_evidence_versions_append_only');
    expect(migration).toContain('sha256 text not null');
    expect(migration).toContain('unique (document_id, version_number)');
    expect(migration).not.toMatch(/policy .*update on storage\.objects/i);
  });

  it('enforces exact tenant/project and typed subject coherence', () => {
    expect(migration).toContain('foreign key (evidence_version_id, project_id, organization_id)');
    expect(migration).toContain('foreign key (purchase_order_id, project_id, organization_id)');
    expect(migration).toContain('foreign key (purchase_receipt_id, project_id, organization_id)');
    expect(migration).toContain('foreign key (supplier_invoice_id, project_id, organization_id)');
    expect(migration).toContain('num_nonnulls(purchase_order_id, purchase_receipt_id, supplier_invoice_id) = 1');
  });

  it('requires the actual locked Storage object and trusted transport metadata', () => {
    expect(migration).toContain("from storage.objects o");
    expect(migration).toContain("for share;");
    expect(migration).toContain('procurement evidence storage object not found');
    expect(migration).toContain("v_object.metadata->>'size'");
    expect(migration).toContain("v_object.metadata->>'mimetype'");
  });

  it('gates PO and payable approval on non-orphan immutable files', () => {
    expect(migration).toContain('purchase order approval requires an immutable contract or purchase order file');
    expect(migration).toContain('supplier invoice approval requires an immutable invoice file');
    expect(migration).toContain('supplier invoice approval requires immutable evidence for every matched receipt');
    expect(migration.match(/join storage\.objects o/g)?.length).toBeGreaterThanOrEqual(3);
  });

  it('does not invent a contract suite, document workflow or duplicate audit core', () => {
    expect(migration).not.toMatch(/create table public\.(contract_terms|contract_obligations|document_approvals|procurement_audit)/);
    expect(migration).toContain("'PROCUREMENT_EVIDENCE_LINKED'");
    expect(migration).toContain('insert into public.audit_events');
  });
});

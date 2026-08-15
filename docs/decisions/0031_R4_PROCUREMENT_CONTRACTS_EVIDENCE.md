# ADR 0031 — R4 Procurement Contracts & Evidence Closure

- **Status:** Accepted
- **Date:** 2026-08-15
- **Scope:** Private, immutable, versioned files proving Procurement Purchase Orders/contracts, receipts and Supplier Invoices.
- **Depends on:** ADR 0030 (R4 financial procure-to-pay), Greenfield Documents & Workflow aggregate, Supabase private Storage and the existing tenant/Project/audit boundaries.

## Context

ADR 0030 connected commercial and financial facts from Purchase Order through receipt-matched Supplier Invoice, Finance Core payable, payment and bank reconciliation. Those facts retained text evidence references, but a reference was not an actual controlled file. An approver or auditor therefore could not reproduce the complete commercial/evidence chain inside Terranex.

The canonical domain model requires versioned evidence linked to the fact it supports. The active R4 scope needs that behavior for Purchase Orders, contracts used as their commercial basis, receipts and Supplier Invoices. It does not authorize a general contract-management suite, electronic signature, legal interpretation, retention schedule or arbitrary document taxonomy.

## Decision

### Private file and metadata boundary

Procurement evidence uses one private Supabase Storage bucket, `procurement-evidence`. Object names contain only server-derived Organization ID, Project ID and an opaque UUID; original filenames remain metadata. The bucket accepts PDF, JPEG and PNG up to 10 MB. Active Organization members may upload into a Project belonging to that Organization and may read only registered objects in their Organization. Registered objects have no update or delete policy. A narrowly bounded delete policy permits application compensation only while an upload has no registered metadata version.

The database owns three facts:

1. `procurement_evidence_documents` — stable document identity, Project, classification and title;
2. `procurement_evidence_versions` — immutable version number, private object path, original filename, MIME type, byte size, SHA-256 and uploader/time;
3. `procurement_evidence_links` — an immutable typed link from one exact version to one Purchase Order, Purchase Receipt or Supplier Invoice.

Replacing a file creates a new version; it never overwrites the old object or metadata. Each Project/Organization relationship is enforced by composite foreign keys. Classification is intentionally closed to `CONTRACT | PURCHASE_ORDER | RECEIPT | SUPPLIER_INVOICE` for this slice.

### Command, idempotency and audit

`register_procurement_evidence` atomically creates a document or its next version, creates the typed subject link and appends one audit event containing IDs, classification, checksum and size—not file content or secrets. It is active-member gated, request-fingerprinted and retry-safe. The application computes SHA-256 over the uploaded bytes and uses an object name stable for a retry of the same command/file payload.

A contract is represented only as a classified, versioned commercial document linked to the Purchase Order it supports. Terranex does not infer legal terms, effective rights, renewal, termination, signature validity or accounting treatment from that classification.

### Approval evidence gates

A commercial Purchase Order cannot transition from `SUBMITTED` to `APPROVED` without at least one registered `PURCHASE_ORDER` or `CONTRACT` file version linked to that order.

A Supplier Invoice cannot transition to `APPROVED` unless:

- a registered `SUPPLIER_INVOICE` file version is linked to the invoice; and
- every Purchase Receipt consumed by its lines has a registered `RECEIPT` file version.

The existing text references remain human/business labels and preserve historical compatibility; they no longer satisfy these approval gates. Receipt remains an append-only quantity fact and may be recorded before its file is attached, but no matched Supplier Invoice can become a Finance Core payable until the receipt evidence exists.

### Access and user experience

The Arabic/RTL Procurement workspace exposes upload/version actions and short-lived signed download links at the exact PO, receipt and invoice cards. It shows filename, version and checksum prefix, and truthfully flags missing actual evidence. Files are never public URLs.

## Explicit exclusions

- general organization-wide document management or arbitrary links;
- contract authoring, clause extraction, obligation calendars, renewals or termination;
- electronic signatures, signature/legal validity or counterparty portal;
- a document retention/deletion schedule, legal hold or malware-scanning provider;
- tax/VAT/e-invoice automation;
- inventory valuation, COGS, warehouse/bin/WMS behavior;
- any second approval, audit, Procurement ledger or Finance ledger.

The retention/legal-hold and malware-scanning production policies remain R12 hardening concerns and must be established before production use. BD-001 through BD-012 are unaffected; this slice does not interpret investor or Portfolio legal/economic terms.

## Consequences

The procure-to-pay chain now has reproducible in-product evidence and approval cannot outrun the PO/receipt/invoice files. Storage and metadata are tenant/Project scoped, append-only after registration and independently checksum-verifiable. R4 remains open only for the separately bounded shared inventory-value concepts and the subsequent R4 closeout audit.

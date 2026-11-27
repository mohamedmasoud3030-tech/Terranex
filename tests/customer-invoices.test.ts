import { describe, expect, it } from 'vitest';
import {
  customerInvoiceCollectionSchema,
  customerInvoiceIssueSchema,
  customerPartySchema,
} from '../src/features/invoices/schema';
import { customerInvoiceState } from '../src/features/invoices/labels';

const ORG = '10000000-0000-4000-8000-000000000301';
const PROJECT = '20000000-0000-4000-8000-000000000301';
const PARTY = '30000000-0000-4000-8000-000000000301';
const INVOICE = '40000000-0000-4000-8000-000000000301';
const CASH = '50000000-0000-4000-8000-000000000301';

const issue = {
  organizationId: ORG,
  projectId: PROJECT,
  customerPartyId: PARTY,
  invoiceReference: 'INV-0001',
  description: 'مقاولة شهر أكتوبر',
  amount: '25000.00',
  currency: 'EGP',
  invoiceDate: '2026-11-25',
  evidenceReference: 'سند-101',
  idempotencyKey: 'ci-issue-test-0001',
};

describe('customer invoice issue validation', () => {
  it('accepts a complete issue command', () => {
    const parsed = customerInvoiceIssueSchema.safeParse(issue);
    expect(parsed.success).toBe(true);
  });

  it('accepts an empty description as absent', () => {
    const parsed = customerInvoiceIssueSchema.safeParse({ ...issue, description: '' });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.description).toBeNull();
  });

  it('rejects a blank invoice reference and an over-precision amount', () => {
    expect(customerInvoiceIssueSchema.safeParse({ ...issue, invoiceReference: ' ' }).success).toBe(false);
    expect(customerInvoiceIssueSchema.safeParse({ ...issue, amount: '10.001' }).success).toBe(false);
    expect(customerInvoiceIssueSchema.safeParse({ ...issue, amount: '-5' }).success).toBe(false);
  });

  it('rejects a missing evidence reference', () => {
    expect(customerInvoiceIssueSchema.safeParse({ ...issue, evidenceReference: '' }).success).toBe(false);
  });
});

describe('customer invoice collection validation', () => {
  const collect = {
    organizationId: ORG,
    projectId: PROJECT,
    invoiceId: INVOICE,
    cashAccountId: CASH,
    amount: '10000',
    currency: 'EGP',
    collectionDate: '2026-11-27',
    evidenceReference: 'إيصال-201',
    idempotencyKey: 'ci-collect-test-0001',
  };

  it('accepts a complete collection command', () => {
    expect(customerInvoiceCollectionSchema.safeParse(collect).success).toBe(true);
  });

  it('rejects an invalid cash account id', () => {
    expect(customerInvoiceCollectionSchema.safeParse({ ...collect, cashAccountId: 'x' }).success).toBe(false);
  });
});

describe('customer party validation', () => {
  it('accepts an organization customer and rejects a blank name', () => {
    expect(customerPartySchema.safeParse({
      organizationId: ORG, legalName: 'شركة العميل الأول', partyType: 'ORGANIZATION',
    }).success).toBe(true);
    expect(customerPartySchema.safeParse({
      organizationId: ORG, legalName: ' ', partyType: 'PERSON',
    }).success).toBe(false);
  });
});

describe('customer invoice state labels', () => {
  it('maps outstanding and reversal to a readable state', () => {
    expect(customerInvoiceState('0', false).key).toBe('SETTLED');
    expect(customerInvoiceState('1500000', false).key).toBe('OPEN');
    expect(customerInvoiceState('0', true).key).toBe('REVERSED');
  });
});

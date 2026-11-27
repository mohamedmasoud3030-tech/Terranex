import { describe, expect, it } from 'vitest';

import { buildPartyDirectory, partyRolesAr, type PartyBase } from '@/features/parties/directory';

const parties: PartyBase[] = [
  { id: 'p1', legal_name: 'شركة البناء الحديث', party_type: 'ORGANIZATION', created_at: '2026-01-01' },
  { id: 'p2', legal_name: 'مستثمر خاص', party_type: 'PERSON', created_at: '2026-01-02' },
  { id: 'p3', legal_name: 'طرف غير مستخدم', party_type: 'PERSON', created_at: '2026-01-03' },
];

describe('party directory', () => {
  it('aggregates investor and supplier roles per party without double counting projects', () => {
    const rows = buildPartyDirectory(
      parties,
      [
        { party_id: 'p2', project_id: 'pr1' },
        { party_id: 'p2', project_id: 'pr1' }, // duplicate participation row must not inflate
        { party_id: 'p2', project_id: 'pr2' },
      ],
      [
        { party_id: 'p1', currency: 'EGP', outstanding_minor_units: '5000', is_posted: true },
        { party_id: 'p1', currency: 'EGP', outstanding_minor_units: '3000', is_posted: true },
        { party_id: 'p1', currency: 'OMR', outstanding_minor_units: '100', is_posted: true },
        { party_id: 'p1', currency: 'EGP', outstanding_minor_units: '999', is_posted: false }, // unposted: excluded
        { party_id: 'p2', currency: 'EGP', outstanding_minor_units: '0', is_posted: true }, // settled: excluded
      ],
    );
    const supplier = rows.find((row) => row.id === 'p1')!;
    expect(supplier.openObligationCount).toBe(3);
    expect(supplier.outstandingByCurrency).toEqual({ EGP: '8000', OMR: '100' });
    const investor = rows.find((row) => row.id === 'p2')!;
    expect(investor.investorProjectCount).toBe(2);
    expect(investor.openObligationCount).toBe(0);
  });

  it('sums bigint money exactly across rows of the same currency', () => {
    const rows = buildPartyDirectory(parties, [], [
      { party_id: 'p1', currency: 'EGP', outstanding_minor_units: '9007199254740993', is_posted: true },
      { party_id: 'p1', currency: 'EGP', outstanding_minor_units: '9007199254740993', is_posted: true },
    ]);
    expect(rows[0].outstandingByCurrency.EGP).toBe('18014398509481986');
  });

  it('says plainly when a party has no role yet', () => {
    const rows = buildPartyDirectory(
      parties,
      [{ party_id: 'p2', project_id: 'pr1' }],
      [{ party_id: 'p1', currency: 'EGP', outstanding_minor_units: '5000', is_posted: true }],
    );
    expect(partyRolesAr(rows.find((row) => row.id === 'p3')!)).toBe('لم يُستخدم بعد في أي مشروع');
    expect(partyRolesAr(rows.find((row) => row.id === 'p2')!)).toContain('مستثمر');
    expect(partyRolesAr(rows.find((row) => row.id === 'p1')!)).toContain('مورد');
  });
});

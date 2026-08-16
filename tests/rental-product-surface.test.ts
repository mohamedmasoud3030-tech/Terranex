import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { rentalCollectionSchema, rentalRecognitionSchema } from '@/features/revenue/schema';

const uuid=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const base={organizationId:uuid(1),projectId:uuid(2),propertyAssetId:uuid(3),tenantPartyId:uuid(4),contractReference:'LEASE-OMR',rentalPeriodStart:'2026-08-01',rentalPeriodEnd:'2026-08-31',recognitionDate:'2026-08-31',evidenceReference:'LEASE-EVIDENCE',idempotencyKey:'rental-command-001'};

describe('R5 rental operator workflow',()=>{
  it('accepts valid OMR 3dp and rejects excessive precision',()=>{
    expect(rentalRecognitionSchema.safeParse({...base,amount:'123.456',currency:'OMR'}).success).toBe(true);
    expect(rentalRecognitionSchema.safeParse({...base,amount:'123.4567',currency:'OMR'}).success).toBe(false);
    expect(rentalRecognitionSchema.safeParse({...base,amount:'123.456',currency:'EGP'}).success).toBe(false);
  });

  it('keeps collection currency-aware',()=>{
    const collection={organizationId:uuid(1),projectId:uuid(2),recognitionId:uuid(5),cashAccountId:uuid(6),amount:'1.001',currency:'OMR',collectionDate:'2026-08-31',evidenceReference:'BANK-1',idempotencyKey:'rental-collection-1'};
    expect(rentalCollectionSchema.safeParse(collection).success).toBe(true);
    expect(rentalCollectionSchema.safeParse({...collection,amount:'1.0001'}).success).toBe(false);
  });

  it('wires recognition, collection and reconciliation RPCs with retry-safe keys',()=>{
    const actions=readFileSync('src/features/revenue/actions.ts','utf8');
    const forms=readFileSync('src/app/(app)/projects/[projectId]/revenue/rental-forms.tsx','utf8');
    const page=readFileSync('src/app/(app)/projects/[projectId]/revenue/page.tsx','utf8');
    for(const rpc of ['recognize_property_rental_income','collect_property_rental_receivable','reconcile_property_rental_collection']) expect(actions).toContain(rpc);
    expect(actions).toMatch(/commandFailureState\(prev/); expect(actions).toMatch(/commandSuccessState\(prev\)/);
    expect(forms.match(/useCommandIdempotencyKey\(/g)?.length).toBe(3);
    expect(page).toMatch(/getRentalIncome/); expect(page).toMatch(/getRentalCollections/);
    expect(forms).not.toMatch(/parseFloat|toFixed|Number\(/);
  });
});

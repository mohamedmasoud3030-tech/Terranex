import { readFileSync } from 'node:fs';
import { describe,expect,it } from 'vitest';
import { acquisitionSchema,budgetSchema,parcelSchema,sectorEventSchema,transitionSchema,valuationSchema } from '../src/features/real-estate/schema';

const migration=readFileSync('supabase/migrations/20260811000400_s3_real_estate_operations.sql','utf8');
const integrityHardening=readFileSync('supabase/migrations/20260811000410_s3_integrity_hardening.sql','utf8');
const controlPrecedence=readFileSync('supabase/migrations/20260811000420_s3_control_precedence_hardening.sql','utf8');
const id=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const base={organizationId:id(1),projectId:id(2),idempotencyKey:'s3-test-key-0001'};

describe('S3 boundary validation',()=>{
  it('requires parcel quantity and an explicit supported area unit',()=>{
    const parcel={...base,propertyAssetId:id(3),identifier:'قطعة 1',cadastralReference:'CAD-1',legalDescription:'وصف',areaQuantity:'12.500000',areaUnit:'FEDDAN'};
    expect(parcelSchema.safeParse(parcel).success).toBe(true);
    expect(parcelSchema.safeParse({...parcel,areaQuantity:''}).success).toBe(false);
    expect(parcelSchema.safeParse({...parcel,areaUnit:'UNKNOWN'}).success).toBe(false);
  });
  it('keeps acquisition consideration exact and evidence-backed',()=>{
    const acquisition={...base,propertyAssetId:id(3),sellerPartyId:id(4),contractReference:'SALE-1',consideration:'500000.00',closingCosts:'0',currency:'EGP',contractDate:'2026-08-01',considerationObligationId:'',evidenceReference:'عقد موقع'};
    expect(acquisitionSchema.safeParse(acquisition).success).toBe(true);
    expect(acquisitionSchema.safeParse({...acquisition,consideration:'1.001'}).success).toBe(false);
    expect(acquisitionSchema.safeParse({...acquisition,evidenceReference:''}).success).toBe(false);
  });
  it('requires material transition reason and retry key',()=>{
    expect(transitionSchema.safeParse({...base,subjectId:id(3),expectedState:'CANDIDATE',newState:'DUE_DILIGENCE',reason:'بدء الفحص',evidenceReference:''}).success).toBe(true);
    expect(transitionSchema.safeParse({...base,subjectId:id(3),expectedState:'CANDIDATE',newState:'HELD',reason:'x',evidenceReference:''}).success).toBe(false);
  });
  it('allows quantity-free events but never a quantity without unit',()=>{
    const event={...base,propertyAssetId:id(3),parcelId:'',phaseId:'',milestoneId:'',eventType:'SITE_VISIT',occurredAt:'2026-08-11T10:00',quantity:'',unit:'',responsibleActorId:id(5),location:'الموقع',notes:'زيارة ميدانية',evidenceReference:''};
    expect(sectorEventSchema.safeParse(event).success).toBe(true);
    expect(sectorEventSchema.safeParse({...event,quantity:'10'}).success).toBe(false);
    expect(sectorEventSchema.safeParse({...event,quantity:'10.25',unit:'PERCENT'}).success).toBe(true);
  });
  it('validates exact budget and management valuation input',()=>{
    expect(budgetSchema.safeParse({...base,propertyAssetId:id(3),currency:'EGP',basisNotes:'خطة معتمدة',parcelId:'',phaseId:'',costCategory:'CONSTRUCTION',amount:'8000.00'}).success).toBe(true);
    expect(valuationSchema.safeParse({...base,propertyAssetId:id(3),effectiveDate:'2026-08-11',valuerSource:'مقيّم مستقل',method:'مقارنة سوقية',amount:'650000.00',currency:'EGP',assumptionsNotes:'مقارنات مماثلة',confidence:'MEDIUM',evidenceReference:'VAL-1'}).success).toBe(true);
  });
});

describe('S3 database contract',()=>{
  it('uses normalized hierarchy foreign keys instead of polymorphic tags',()=>{
    expect(migration).toContain('foreign key (parcel_id, organization_id, project_id, property_asset_id)');
    expect(migration).toContain('foreign key (milestone_id, organization_id, project_id, property_asset_id, phase_id)');
    expect(migration).not.toContain('sector_object_type');
    expect(migration).not.toContain('sector_object_id');
  });
  it('enforces lifecycle and current whole-asset evidence at the database boundary',()=>{
    expect(migration).toContain('property_transition_guard');
    expect(migration).toContain("v_current = 'ACQUIRING' and new.new_state = 'HELD'");
    expect(migration).toContain("s3_has_current_effective_control(new.property_asset_id,'TITLE')");
    expect(migration).toContain("s3_has_current_effective_control(new.property_asset_id,'POSSESSION')");
    expect(migration).toContain('for update');
    expect(migration).toContain('unique (property_asset_id, previous_history_id)');
    expect(controlPrecedence).toContain('left join lateral');
    expect(controlPrecedence).toContain("c.status is distinct from 'PASSED'");
  });
  it('keeps lifecycle orchestration canonical while forward migrations refine policy',()=>{
    const chain=`${migration}\n${integrityHardening}\n${controlPrecedence}`;
    expect(chain.match(/create or replace function public\.s3_validate_property_transition\(\)/g)).toHaveLength(1);
    expect(integrityHardening).toContain('refined evidence policy helper');
    expect(controlPrecedence).toContain('refined evidence policy helper');
  });
  it('extends S2 through dimension links and derived views without a second ledger',()=>{
    const costTable=migration.split('create table public.property_cost_items (')[1].split(');')[0];
    expect(costTable).toContain('cost_obligation_id uuid not null');
    expect(costTable).not.toContain('amount_minor_units');
    expect(migration).toContain('property_cost_drilldown_read');
    expect(migration).toContain("sa.role in ('PROJECT_EXPENSE','DEVELOPMENT_WIP')");
    expect(migration).not.toContain('create table public.property_journal');
  });
  it('keeps valuation outside posting commands',()=>{
    const proposal=migration.split('create or replace function public.propose_property_valuation(')[1].split('end $$')[0];
    const approval=migration.split('create or replace function public.approve_property_valuation(')[1].split('end $$')[0];
    expect(proposal).not.toContain('insert into public.journal_');
    expect(approval).not.toContain('insert into public.journal_');
    expect(migration).toContain("'accounting_effect','NONE'");
  });
  it('denies browser table writes and makes material facts immutable',()=>{
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.%I from anon, authenticated');
    expect(migration).toContain('confirmed S3 facts and history are immutable');
    expect(migration).not.toContain('grant insert on public.property_');
  });
});

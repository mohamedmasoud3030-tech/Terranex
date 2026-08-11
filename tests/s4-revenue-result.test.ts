import { readFileSync } from 'node:fs';
import { describe,expect,it } from 'vitest';
import {
  collectionReconciliationSchema,
  controlTransferSchema,
  dispositionSchema,
  saleCollectionSchema,
  saleRecognitionSchema,
  sellingCostClassificationSchema,
} from '../src/features/revenue/schema';

const migration=readFileSync('supabase/migrations/20260811000500_s4_revenue_and_realized_result.sql','utf8');
const id=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const context={organizationId:id(1),projectId:id(2)};

describe('S4 boundary validation',()=>{
  it('validates an evidence-backed whole-property disposition with exact proceeds',()=>{
    const disposition={...context,propertyAssetId:id(3),buyerPartyId:id(4),agreementReference:'DISP-1',agreementEvidenceReference:'عقد موقع',agreedProceeds:'1000000.00',currency:'EGP',agreementDate:'2026-08-10',expectedControlTransferDate:'2026-08-11',idempotencyKey:'s4-disp-0001'};
    expect(dispositionSchema.safeParse(disposition).success).toBe(true);
    expect(dispositionSchema.safeParse({...disposition,agreedProceeds:'1.001'}).success).toBe(false);
    expect(dispositionSchema.safeParse({...disposition,agreementEvidenceReference:''}).success).toBe(false);
  });

  it('validates control transfer, recognition, and partial collection as separate commands',()=>{
    const subject={...context,dispositionId:id(5),idempotencyKey:'s4-action-001'};
    expect(controlTransferSchema.safeParse({...subject,controlTransferDate:'2026-08-11',evidenceReference:'محضر إقفال'}).success).toBe(true);
    expect(saleRecognitionSchema.safeParse({...subject,recognitionDate:'2026-08-11'}).success).toBe(true);
    expect(saleCollectionSchema.safeParse({...context,recognitionId:id(6),cashAccountId:id(7),amount:'250000.00',currency:'EGP',collectionDate:'2026-08-11',evidenceReference:'إيصال تحويل',idempotencyKey:'s4-collect-001'}).success).toBe(true);
  });

  it('requires bank matching and selling-cost policy provenance',()=>{
    expect(collectionReconciliationSchema.safeParse({...context,collectionId:id(8),statementLineId:id(9),idempotencyKey:'s4-recon-0001'}).success).toBe(true);
    expect(sellingCostClassificationSchema.safeParse({...context,obligationId:id(10),propertyAssetId:id(3),parcelId:'',phaseId:'',policyReference:'عمولة بيع مرحلة في S2',idempotencyKey:'s4-selling-001'}).success).toBe(true);
  });
});

describe('S4 database contract',()=>{
  it('is whole-property only and database-protects the asset from a second disposition',()=>{
    const table=migration.split('create table public.property_dispositions (')[1].split(');')[0];
    expect(table).toContain('property_asset_id uuid not null');
    expect(table).toContain('unique (property_asset_id)');
    expect(table).not.toContain('parcel_id');
    expect(table).not.toContain('allocation_percentage');
  });

  it('keeps agreement, control transfer, recognition, and collection distinct',()=>{
    expect(migration).toContain("status in ('DRAFT','APPROVED','CONTROL_TRANSFERRED')");
    expect(migration).toContain('confirm_property_control_transfer');
    expect(migration).toContain('recognize_property_sale');
    expect(migration).toContain('collect_property_sale_receivable');
    expect(migration).not.toContain("'PAID' and");
  });

  it('reuses the S2 journal and cash accounts with exact required postings',()=>{
    expect(migration).toContain("'CUSTOMER_RECEIVABLE'");
    expect(migration).toContain("'REAL_ESTATE_SALE_REVENUE'");
    expect(migration).toContain("'REAL_ESTATE_COST_OF_SALE'");
    expect(migration).toContain("where role='DEVELOPMENT_WIP'");
    expect(migration).toContain("where role='BANK_CASH'");
    expect(migration).not.toContain('create table public.property_journal');
    expect(migration).not.toContain('create table public.sale_subledger');
  });

  it('derives carrying cost only from active posted WIP classified by S3',()=>{
    const fn=migration.split('create or replace function public.recognize_property_sale(')[1].split('end $$')[0];
    expect(fn).toContain('public.property_cost_items');
    expect(fn).toContain("o.cost_treatment='CAPITALIZABLE_WIP'");
    expect(fn).toContain("jb.source_type='COST_OBLIGATION'");
    expect(fn).toContain("sa.role='DEVELOPMENT_WIP'");
    expect(fn).toContain('authoritative posted carrying cost cannot be derived');
    expect(fn).not.toContain('property_budget_lines');
    expect(fn).not.toContain('property_valuations');
  });

  it('posts revenue and carrying derecognition atomically in one balanced batch command',()=>{
    const fn=migration.split('create or replace function public.recognize_property_sale(')[1].split('end $$')[0];
    expect(fn).toContain("'PROPERTY_SALE_RECOGNITION'");
    expect(fn).toContain('insert into public.journal_lines');
    expect(fn).toContain('v_receivable');
    expect(fn).toContain('v_revenue');
    expect(fn).toContain('v_cost_of_sale');
    expect(fn).toContain('v_wip');
  });

  it('serializes recognition and collection ceilings in the database',()=>{
    expect(migration).toContain("':s4-sale-recognize:'");
    expect(migration).toContain('where id=p_disposition_id and organization_id=p_organization_id for update');
    expect(migration).toContain('property_sale_collection_scope_and_ceiling');
    expect(migration).toContain('where id=new.recognition_id and organization_id=new.organization_id for update');
    expect(migration).toContain('collection exceeds outstanding receivable');
  });

  it('keeps approved management valuation separate from realized result',()=>{
    const view=migration.split('create or replace view public.property_realized_result_read')[1].split('create or replace view public.property_realized_result_drilldown_read')[0];
    expect(view).toContain('realized_result_minor_units');
    expect(view).toContain('latest_management_valuation_minor_units');
    expect(view).toContain("v.status='APPROVED'");
    expect(view).not.toContain('revenue+val');
  });

  it('keeps browser writes default-deny and exposes source-level drilldown',()=>{
    expect(migration).toContain('force row level security');
    expect(migration).toContain('revoke all on public.%I from anon,authenticated');
    expect(migration).toContain('property_realized_result_drilldown_read');
    expect(migration).toContain('journal_line_id');
    expect(migration).toContain('evidence_reference');
    expect(migration).not.toContain('grant insert on public.property_sale');
  });
});

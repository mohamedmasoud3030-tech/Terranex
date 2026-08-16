import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { projectDecisionSchema, projectRiskSchema, riskResolutionSchema } from '@/features/governance/schema';

const read = (path:string) => readFileSync(path,'utf8');
const uuid=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const common={organizationId:uuid(1),projectId:uuid(2),idempotencyKey:'governance-command-001'};

describe('R2 governance product surface',()=>{
  it('validates the exact risk, resolution and immutable decision command shapes',()=>{
    expect(projectRiskSchema.safeParse({...common,title:'خطر توريد',description:'تأخر مورد رئيسي',severity:'HIGH',ownerUserId:uuid(3),dueDate:'2026-08-20',sourceReference:'RISK-1'}).success).toBe(true);
    expect(projectRiskSchema.safeParse({...common,title:'خطر توريد',description:'تأخر',severity:'EXTREME',ownerUserId:uuid(3),dueDate:'',sourceReference:''}).success).toBe(false);
    expect(riskResolutionSchema.safeParse({...common,riskItemId:uuid(4),outcome:'تم استبدال المورد',evidenceReference:'EVID-1'}).success).toBe(true);
    expect(projectDecisionSchema.safeParse({...common,title:'اعتماد البديل',decisionText:'اعتماد المورد البديل',rationale:'استمرارية التشغيل',decisionDate:'2026-08-16',evidenceReference:'BOARD-1'}).success).toBe(true);
  });

  it('uses canonical RPCs only and preserves failure/success idempotency state',()=>{
    const actions=read('src/features/governance/actions.ts');
    expect(actions).toMatch(/rpc\(rpcName/);
    expect(actions).toMatch(/record_project_risk/);
    expect(actions).toMatch(/resolve_project_risk/);
    expect(actions).toMatch(/record_project_decision/);
    expect(actions).toMatch(/commandFailureState\(prev/);
    expect(actions).toMatch(/commandSuccessState\(prev\)/);
    expect(actions).not.toMatch(/\.from\(['"]project_(risk|decision)/);
  });

  it('exposes Arabic forms without update/delete history workflows',()=>{
    const page=read('src/app/(app)/projects/[projectId]/governance/page.tsx');
    const forms=read('src/app/(app)/projects/[projectId]/governance/forms.tsx');
    expect(page).toMatch(/RiskForm/); expect(page).toMatch(/DecisionForm/); expect(page).toMatch(/ResolveRiskForm/);
    expect(forms).toMatch(/غير قابلة للتعديل أو الحذف/);
    expect(forms).not.toMatch(/updateProjectDecision|deleteProjectDecision/);
    expect(forms).toMatch(/useCommandIdempotencyKey/);
  });
});

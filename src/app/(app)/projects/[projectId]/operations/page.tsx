import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getParties } from '@/features/funding/queries';
import { getCurrentMembership, getObligationPositions } from '@/features/finance/queries';
import { createClient } from '@/shared/supabase/server';
import { formatMinorUnits } from '@/shared/money';
import {
  getBudgets,getControls,getCostControls,getCostDrilldown,getMilestones,getParcels,
  getPhases,getPropertyWorkspaces,getRealEstateProfile,getSectorEvents,getTimeline,getValuations,
} from '@/features/real-estate/queries';
import {
  AcquisitionForm,ApprovalButton,ASSET_STATE,AssetForm,BudgetForm,CATEGORY,
  ControlForm,CostClassificationForm,MilestoneForm,MilestoneTransitionForm,
  ParcelForm,PhaseForm,PhaseTransitionForm,ProfileForm,PropertyTransitionForm,
  SectorEventForm,STEP_STATE,ValuationForm,
} from './forms';

export const dynamic='force-dynamic';

const CONTROL_LABEL:Record<string,string>={ACQUISITION_CHECK:'فحص استحواذ',TITLE:'سند الملكية',POSSESSION:'الحيازة',PERMIT:'تصريح',INSPECTION:'معاينة'};
const EVENT_LABEL:Record<string,string>={SITE_VISIT:'زيارة موقع',DEVELOPMENT_PROGRESS:'تقدم تطوير',CONTROL_OBSERVATION:'ملاحظة رقابية',MILESTONE_NOTE:'ملاحظة علامة',OTHER:'واقعة أخرى'};
const STRATEGY:Record<string,string>={ACQUIRE_HOLD:'استحواذ واحتفاظ',DEVELOP_SELL:'تطوير ثم بيع',LAND_TRADE:'تجارة أراضٍ'};
const PAYMENT:Record<string,string>={NOT_LINKED:'غير مربوط بالتزام',OBLIGATION_DRAFT:'التزام مسودة',UNPAID:'غير مدفوع',PARTIALLY_PAID:'مدفوع جزئيًا',PAID:'مدفوع',OBLIGATION_REVERSED:'التزام معكوس'};
function date(value:string|null|undefined){return value?new Date(value).toLocaleDateString('ar-EG'):'—';}
function dateTime(value:string){return new Date(value).toLocaleString('ar-EG');}
function areaUnit(value:string){return {FEDDAN:'فدان',M2:'م²',HECTARE:'هكتار'}[value]??value;}

export default async function OperationsPage({params}:{params:Promise<{projectId:string}>}){
  const {projectId}=await params;
  const project=await getProject(projectId); if(!project)notFound();
  const organizationId=project.organization_id;
  const supabase=await createClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user) return <section className="card"><h1>لا يمكن الوصول</h1><p className="error">انتهت جلسة الدخول. سجّل الدخول ثم أعد فتح المشروع.</p><Link className="button" href="/login">تسجيل الدخول</Link></section>;

  const [membership,profile,assets,parcels,controls,phases,milestones,budgets,valuations,events,costs,drilldown,timeline,parties,obligations]=await Promise.all([
    getCurrentMembership(organizationId),getRealEstateProfile(projectId),getPropertyWorkspaces(projectId),getParcels(projectId),getControls(projectId),getPhases(projectId),getMilestones(projectId),getBudgets(projectId),getValuations(projectId),getSectorEvents(projectId),getCostControls(projectId),getCostDrilldown(projectId),getTimeline(projectId),getParties(organizationId),getObligationPositions(projectId),
  ]);
  if(!membership) return <section className="card"><h1>غير مصرح</h1><p className="error">عضويتك الحالية لا تسمح بقراءة عمليات هذا المشروع.</p></section>;
  const isOwner=membership.role==='OWNER';
  const assetName=new Map(assets.map(a=>[a.property_asset_id,a.name]));
  const parcelName=new Map(parcels.map(p=>[p.id,p.identifier]));
  const phaseName=new Map(phases.map(p=>[p.phase_id,p.name]));
  const classified=new Set(drilldown.map(d=>d.obligation_id));
  const unclassified=obligations.filter(o=>!classified.has(o.obligation_id)&&!o.is_reversed);
  const total=(field:'budget_minor_units'|'committed_minor_units'|'actual_minor_units'|'variance_minor_units')=>costs.reduce((sum,row)=>sum+BigInt(row[field]),0n);

  return <section className="stack">
    <header className="project-context card">
      <div><Link className="muted" href={`/projects/${projectId}`}>← مساحة المشروع</Link><h1>العمليات العقارية</h1><p className="muted">{project.name} · {project.reporting_currency} · {profile?STRATEGY[profile.strategy]: 'لم يُنشأ الملف العقاري'}</p></div>
      <nav className="context-nav" aria-label="تنقل المشروع"><a href="#assets">الأصول والسيطرة</a><a href="#development">التطوير</a><a href="#cost-control">ضبط التكلفة</a><a href="#valuation">التقييم</a><a href="#timeline">السجل</a></nav>
    </header>

    {!profile&&<section className="card stack"><div><h2>ابدأ ملف العمليات العقارية</h2><p className="muted">حدّد استراتيجية المشروع فقط؛ السند والحيازة وحالة الأصل تُثبت لاحقًا كحقائق مستقلة.</p></div><ProfileForm {...{organizationId,projectId}}/></section>}

    {profile&&<>
      <section id="assets" className="stack scroll-target">
        <div className="section-heading"><div><h2>الأصول والقطع والسيطرة</h2><p className="muted">الأصل الاقتصادي منفصل عن المشروع والقطعة والعقد والدفع.</p></div><span className="status">{STRATEGY[profile.strategy]}{profile.jurisdiction?` · ${profile.jurisdiction}`:''}</span></div>
        {assets.length===0?<div className="card empty"><h3>لا توجد أصول عقارية</h3><p className="muted">أضف الأصل الاقتصادي الأول. سيبدأ تلقائيًا كمرشح، وليس كمملوك.</p><AssetForm {...{organizationId,projectId}}/></div>:<>
          <div className="asset-grid">{assets.map(asset=><article className="card stack" key={asset.property_asset_id}>
            <div className="topline"><div><h3>{asset.name}</h3><p className="muted">{asset.asset_reference||'دون مرجع داخلي'}</p></div><span className="status">{ASSET_STATE[asset.operational_state]??asset.operational_state}</span></div>
            <dl className="facts"><div><dt>سند الملكية</dt><dd>{asset.title_status?`${asset.title_status} · ${date(asset.title_effective_date)}`:'غير مثبت'}</dd></div><div><dt>الحيازة</dt><dd>{asset.possession_status?`${asset.possession_status} · ${date(asset.possession_effective_date)}`:'غير مثبتة'}</dd></div><div><dt>الاستحواذ</dt><dd>{asset.contract_reference?`${asset.contract_reference} · ${date(asset.contract_date)}`:'غير مسجل'}</dd></div><div><dt>حالة الدفع</dt><dd>{PAYMENT[asset.acquisition_payment_status]??asset.acquisition_payment_status}</dd></div></dl>
            {asset.consideration_minor_units&&<p><strong>مقابل العقد:</strong> {formatMinorUnits(asset.consideration_minor_units,asset.acquisition_currency??project.reporting_currency)} <span className="muted">(حقيقة عقدية؛ ليست دفعًا)</span></p>}
            {isOwner?<details><summary>تأكيد انتقال حالة الأصل</summary><PropertyTransitionForm {...{organizationId,projectId,asset}}/></details>:<p className="muted">انتقال حالة الأصل يؤكده مالك المنظمة بعد تحقق الأدلة.</p>}
          </article>)}</div>
          <details className="card"><summary>إضافة أصل عقاري آخر</summary><AssetForm {...{organizationId,projectId}}/></details>
          <div className="card stack"><h3>القطع</h3>{parcels.length===0?<p className="muted">لا توجد قطع مساحية. لا تُحفظ مساحة بلا وحدة.</p>:<div className="table-wrap"><table><thead><tr><th>الأصل</th><th>القطعة</th><th>المرجع</th><th>المساحة</th><th>الوصف</th></tr></thead><tbody>{parcels.map(p=><tr key={p.id}><td>{assetName.get(p.property_asset_id)}</td><td>{p.identifier}</td><td>{p.cadastral_reference||'—'}</td><td>{p.area_quantity} {areaUnit(p.area_unit)}</td><td>{p.legal_description||'—'}</td></tr>)}</tbody></table></div>}<details><summary>إضافة قطعة</summary><ParcelForm {...{organizationId,projectId,assets}}/></details></div>

          <div className="grid"><section className="card stack"><h3>الاستحواذ</h3>{assets.every(a=>a.acquisition_id)?<p className="muted">سُجل عقد استحواذ لكل أصل حالي.</p>:isOwner?<AcquisitionForm {...{organizationId,projectId,currency:project.reporting_currency,assets,parties,obligations}}/>:<p className="muted">تسجيل العقد حقيقة مادية يقتصر على مالك المنظمة.</p>}</section><section className="card stack"><h3>الفحص والسند والحيازة والتصاريح</h3><ControlForm {...{organizationId,projectId,userId:user.id,assets,parcels}}/></section></div>
          <section className="card stack"><h3>سجلات السيطرة والفحص المؤكدة</h3>{controls.length===0?<p className="muted">لا توجد سجلات بعد. الانتقال إلى «مُحتفظ به» يتطلب سندًا وحيازة ناجحين وساريين.</p>:<div className="table-wrap"><table><thead><tr><th>الأصل / القطعة</th><th>النوع</th><th>الحالة</th><th>السريان</th><th>الدليل</th></tr></thead><tbody>{controls.map(c=><tr key={c.id}><td>{assetName.get(c.property_asset_id)}{c.parcel_id?` · ${parcelName.get(c.parcel_id)}`:''}</td><td>{CONTROL_LABEL[c.record_type]??c.record_type}<br/><span className="muted">{c.control_type}</span></td><td><span className="status">{c.status}</span></td><td>{date(c.effective_date)}{c.expiry_date?` — ${date(c.expiry_date)}`:''}</td><td>{c.evidence_reference}</td></tr>)}</tbody></table></div>}</section>
        </>}
      </section>

      {assets.length>0&&<>
      <section id="development" className="stack scroll-target"><div className="section-heading"><div><h2>مراحل التطوير والعلامات</h2><p className="muted">حالات تشغيلية مدققة فقط؛ لا مهام أو لوحات عمل أو جدولة قوى عاملة.</p></div></div>
        <div className="grid"><details className="card" open={phases.length===0}><summary>إضافة مرحلة</summary><PhaseForm {...{organizationId,projectId,assets,parcels}}/></details>{phases.length>0&&<details className="card"><summary>إضافة علامة إلى مرحلة</summary><MilestoneForm {...{organizationId,projectId,phases}}/></details>}</div>
        {phases.length===0?<div className="card empty"><p className="muted">لا توجد مراحل تطوير مخططة.</p></div>:<div className="stack">{[...phases].sort((a,b)=>a.sequence_no-b.sequence_no).map(phase=><article className="card stack" key={phase.phase_id}><div className="topline"><div><h3>{phase.sequence_no}. {phase.name}</h3><p className="muted">مخطط: {date(phase.planned_start_date)} — {date(phase.planned_end_date)} · فعلي: {date(phase.actual_start_at)} — {date(phase.actual_end_at)}</p></div><span className="status">{STEP_STATE[phase.operational_state]??phase.operational_state}</span></div><PhaseTransitionForm {...{organizationId,projectId,phase}}/><div className="milestones">{milestones.filter(m=>m.phase_id===phase.phase_id).map(m=><div className="milestone" key={m.milestone_id}><div><strong>{m.sequence_no}. {m.name}</strong><p className="muted">{STEP_STATE[m.operational_state]??m.operational_state} · مخطط {date(m.planned_date)} · مكتمل {date(m.completed_at)}</p></div><MilestoneTransitionForm {...{organizationId,projectId,milestone:m}}/></div>)}{milestones.every(m=>m.phase_id!==phase.phase_id)&&<p className="muted">لا توجد علامات لهذه المرحلة.</p>}</div></article>)}</div>}
      </section>

      <section id="cost-control" className="stack scroll-target"><div className="section-heading"><div><h2>الميزانية مقابل الملتزم والفعلي</h2><p className="muted">الميزانية آخر نسخة معتمدة؛ الملتزم هو المتبقي في التزامات S2 المعتمدة والمفتوحة؛ الفعلي من قيود S2 المنشورة. لا تُجمع القيمتان لأنهما قد تتداخلان.</p></div><span className="status">كما هو الآن · {project.reporting_currency}</span></div>
        <div className="metric-grid"><a className="metric" href="#cost-breakdown"><span>الميزانية</span><strong>{formatMinorUnits(total('budget_minor_units'),project.reporting_currency)}</strong><small>افتح التفصيل</small></a><a className="metric" href="#cost-breakdown"><span>الملتزم المفتوح</span><strong>{formatMinorUnits(total('committed_minor_units'),project.reporting_currency)}</strong><small>من التزامات S2</small></a><a className="metric" href="#cost-breakdown"><span>الفعلي / حتى تاريخه</span><strong>{formatMinorUnits(total('actual_minor_units'),project.reporting_currency)}</strong><small>من القيود المنشورة</small></a><a className="metric" href="#cost-breakdown"><span>الانحراف (ميزانية − فعلي)</span><strong>{formatMinorUnits(total('variance_minor_units'),project.reporting_currency)}</strong><small>افتح المصدر</small></a></div>
        <div className="grid"><details className="card"><summary>اقتراح نسخة ميزانية</summary><BudgetForm {...{organizationId,projectId,currency:project.reporting_currency,assets,parcels,phases}}/></details><details className="card" open={unclassified.length>0}><summary>إسناد التزام S2 إلى بُعد عقاري ({unclassified.length})</summary>{unclassified.length===0?<p className="muted">كل التزامات S2 الحالية مصنفة أو معكوسة.</p>:<CostClassificationForm {...{organizationId,projectId,assets,parcels,phases,obligations:unclassified}}/>}</details></div>
        <section className="card stack"><h3>نسخ الميزانية</h3>{budgets.length===0?<p className="muted">لا توجد ميزانية مقترحة أو معتمدة.</p>:<div className="table-wrap"><table><thead><tr><th>الأصل</th><th>النسخة</th><th>الأساس</th><th>الإجمالي</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>{budgets.map(b=><tr key={b.budget_version_id}><td>{assetName.get(b.property_asset_id)}</td><td>{b.version_no}</td><td>{b.basis_notes}</td><td>{formatMinorUnits(b.total_minor_units,b.currency)}</td><td><span className="status">{b.status==='APPROVED'?'معتمدة':'مقترحة'}</span></td><td>{b.status==='PROPOSED'&&isOwner?<ApprovalButton kind="budget" organizationId={organizationId} projectId={projectId} subjectId={b.budget_version_id}/>:b.approved_at?dateTime(b.approved_at):'بانتظار المالك'}</td></tr>)}</tbody></table></div>}</section>
        <section id="cost-breakdown" className="card stack scroll-target"><h3>تفصيل التكلفة حسب الأصل والقطعة والمرحلة والفئة</h3>{costs.length===0?<div className="empty"><p className="muted">لا توجد ميزانية معتمدة أو تكاليف S2 مصنفة بعد.</p></div>:<div className="table-wrap"><table><thead><tr><th>البُعد</th><th>الفئة</th><th>الميزانية</th><th>الملتزم</th><th>الفعلي</th><th>الانحراف</th></tr></thead><tbody>{costs.map((c,index)=><tr key={`${c.property_asset_id}-${c.parcel_id}-${c.phase_id}-${c.cost_category}-${index}`}><td>{assetName.get(c.property_asset_id)}{c.parcel_id?` · ${parcelName.get(c.parcel_id)}`:''}{c.phase_id?` · ${phaseName.get(c.phase_id)}`:''}</td><td>{CATEGORY[c.cost_category]??c.cost_category}</td><td>{formatMinorUnits(c.budget_minor_units,c.currency)}</td><td>{formatMinorUnits(c.committed_minor_units,c.currency)}</td><td>{formatMinorUnits(c.actual_minor_units,c.currency)}</td><td>{formatMinorUnits(c.variance_minor_units,c.currency)}</td></tr>)}</tbody></table></div>}
          <h4>السجلات المالية الأصلية</h4>{drilldown.length===0?<p className="muted">لا توجد التزامات مالية مصنفة للتفصيل.</p>:drilldown.map(d=><details key={d.property_cost_item_id}><summary>{d.description} — فعلي {formatMinorUnits(d.actual_minor_units,d.currency)}</summary><dl className="facts"><div><dt>التزام S2</dt><dd><Link href={`/projects/${projectId}/costs#${d.obligation_id}`}>{d.obligation_id}</Link></dd></div><div><dt>القيد المنشور الأصلي</dt><dd>{d.originating_batch_id||'لم يُرحّل'}</dd></div><div><dt>الفئة / القرار</dt><dd>{CATEGORY[d.cost_category]} · {d.policy_reference}</dd></div><div><dt>الملتزم المفتوح</dt><dd>{formatMinorUnits(d.committed_minor_units,d.currency)}</dd></div></dl></details>)}</section>
      </section>

      <section id="valuation" className="stack scroll-target"><div className="section-heading"><div><h2>التقييم الإداري</h2><p className="muted">منفصل صراحة عن النقد والإيراد والنتيجة المحققة وأي معالجة IAS/IFRS.</p></div></div><details className="card" open={valuations.length===0}><summary>اقتراح تقييم إداري</summary><ValuationForm {...{organizationId,projectId,currency:project.reporting_currency,assets}}/></details><section className="card stack">{valuations.length===0?<p className="muted">لا توجد تقييمات. لا يُعرض رقم افتراضي.</p>:<div className="table-wrap"><table><thead><tr><th>الأصل / التاريخ</th><th>المصدر والطريقة</th><th>التقييم الإداري</th><th>الافتراضات</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>{valuations.map(v=><tr key={v.valuation_id}><td>{assetName.get(v.property_asset_id)}<br/>{date(v.effective_date)}</td><td>{v.valuer_source}<br/><span className="muted">{v.method}</span></td><td><strong>{formatMinorUnits(v.amount_minor_units,v.currency)}</strong><br/><span className="muted">ليس ربحًا محققًا</span></td><td>{v.assumptions_notes}<br/><small>{v.evidence_reference}</small></td><td><span className="status">{v.status==='APPROVED'?'معتمد':'مقترح'}</span></td><td>{v.status==='PROPOSED'&&isOwner?<ApprovalButton kind="valuation" organizationId={organizationId} projectId={projectId} subjectId={v.valuation_id}/>:v.reviewed_at?dateTime(v.reviewed_at):'بانتظار المالك'}</td></tr>)}</tbody></table></div>}</section></section>

      <section className="stack"><div className="section-heading"><div><h2>الوقائع القطاعية المؤكدة</h2><p className="muted">الكمية اختيارية، لكنها لا تُقبل دون وحدة صريحة.</p></div></div><details className="card"><summary>تأكيد واقعة عقارية</summary><SectorEventForm {...{organizationId,projectId,userId:user.id,assets,parcels,phases,milestones}}/></details><section className="card stack">{events.length===0?<p className="muted">لا توجد وقائع مؤكدة بعد.</p>:events.map(e=><article className="timeline-row" key={e.event_id}><div><strong>{EVENT_LABEL[e.event_type]??e.event_type}</strong><p>{e.notes}</p><small className="muted">{assetName.get(e.property_asset_id??'')||'المشروع'}{e.quantity?` · ${e.quantity} ${e.unit}`:''}{e.evidence_reference?` · دليل: ${e.evidence_reference}`:''}</small></div><time>{dateTime(e.occurred_at)}</time></article>)}</section></section>

      <section id="timeline" className="stack scroll-target"><div className="section-heading"><div><h2>السجل التشغيلي</h2><p className="muted">حقائق وانتقالات غير قابلة للتحرير المباشر، مع الفاعل والوقت والسبب والدليل.</p></div></div><section className="card timeline">{timeline.length===0?<p className="muted">لا يوجد سجل بعد.</p>:timeline.map(t=><article className="timeline-row" key={`${t.event_type}-${t.id}`}><div><strong>{t.event_type}</strong>{t.state&&<span className="status">{ASSET_STATE[t.state]??STEP_STATE[t.state]??t.state}</span>}<p>{t.reason}</p>{t.evidence_reference&&<small className="muted">دليل: {t.evidence_reference}</small>}</div><time>{dateTime(t.occurred_at)}</time></article>)}</section></section>
      </>}
    </>}
  </section>;
}

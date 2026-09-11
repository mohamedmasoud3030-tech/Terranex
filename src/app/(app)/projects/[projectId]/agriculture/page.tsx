import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCashAccountPositions, getCurrentMembership } from '@/features/finance/queries';
import { getParties } from '@/features/funding/queries';
import { formatMinorUnits } from '@/shared/money';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import { InPageTabs } from '@/shared/ui';
import {
  type CropAssignmentRead,
  type CropCycleCostSourceRead,
  type CropCycleIntegrityIssueRead,
  type CropCycleResultRead,
  type FieldRead,
  getAgriculturalLandAssets,
  getAgricultureSaleCollections,
  getAgricultureSaleLines,
  getAgricultureSales,
  getCropAssignments,
  getCropCycleCostSources,
  getCropCycleIntegrityIssues,
  getCropCycleResults,
  getCropCycles,
  getCropCycleTimeline,
  getFarms,
  getFieldActivities,
  getFields,
  getFarmLandAssetLinks,
  getHarvestEvents,
  getHarvestInventoryByLocation,
  getHarvestInventoryMovements,
  getHarvestLots,
  getHarvestLotSaleTraceability,
  getInputApplications,
  getInputItems,
  getInputLots,
  getStorageLocations,
} from '@/features/agriculture/queries';
import {
  AREA_UNIT_LABEL,
  CYCLE_STATE_LABEL,
  formatAgricultureSaleState,
  formatAreaUnit,
  formatDate,
  formatEvidenceCompleteness,
  formatFieldActivityType,
  formatHarvestMovementType,
  formatHarvestQuantity,
  formatInputCategory,
  formatInputQuantity,
  formatLandControlBasis,
  formatLotExpiryStatus,
  formatQuantity,
} from '@/features/agriculture/labels';
import {
  AgriculturalLandAssetForm,
  AgricultureSaleCollectionForm,
  AgricultureSaleForm,
  ApproveAgricultureSaleForm,
  AssignmentForm,
  CropCycleCloseoutForm,
  CropCycleCostAttributionForm,
  CropCycleForm,
  CycleTransitionForm,
  FarmForm,
  FarmLandAssetLinkForm,
  FieldActivityForm,
  FieldForm,
  HarvestEventForm,
  HarvestInventoryAdjustmentForm,
  InputApplicationForm,
  InputItemForm,
  InputLotForm,
  ProfileForm,
  RecognizeAgricultureSaleForm,
  StorageLocationForm,
  TransferHarvestInventoryForm,
} from './forms';

export const dynamic = 'force-dynamic';

function d(value: string | null | undefined) {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
}

function cycleArea(result: CropCycleResultRead) {
  if (!result.assigned_area_quantity || !result.area_unit) {
    return 'راجع الحقول — لا يوجد جمع بين وحدات مختلفة';
  }
  return `${result.assigned_area_quantity} ${formatAreaUnit(result.area_unit)}`;
}

function cycleQuantity(result: CropCycleResultRead, value: string | null) {
  return value && result.quantity_unit ? `${value} ${result.quantity_unit}` : 'غير متاح';
}

function ResultMetrics({ result }: Readonly<{ result: CropCycleResultRead }>) {
  const perArea = (value: string | null) => value && result.area_unit
    ? `${formatMinorUnits(value, result.currency)} / ${formatAreaUnit(result.area_unit)}`
    : 'غير متاح';
  return (
    <dl className="facts">
      <div><dt>المساحة المزروعة/المشغلة</dt><dd>{cycleArea(result)}</dd></div>
      <div><dt>أنشطة الحقل المسجلة</dt><dd>{result.activity_count}</dd></div>
      <div><dt>تطبيقات المدخلات المسجلة</dt><dd>{result.input_application_count}</dd></div>
      <div><dt>إجمالي الحصاد</dt><dd>{cycleQuantity(result, result.gross_harvest_quantity)}</dd></div>
      <div><dt>صافي الحصاد المقبول</dt><dd>{cycleQuantity(result, result.net_accepted_harvest_quantity)}</dd></div>
      <div><dt>فاقد الحصاد</dt><dd>{cycleQuantity(result, result.harvest_loss)}</dd></div>
      <div><dt>التالف أثناء التخزين</dt><dd>{cycleQuantity(result, result.spoilage_quantity)}</dd></div>
      <div><dt>الكمية المباعة</dt><dd>{cycleQuantity(result, result.quantity_sold)}</dd></div>
      <div><dt>المخزون المتبقي</dt><dd>{cycleQuantity(result, result.remaining_physical_inventory)}</dd></div>
      <div><dt>قيمة المخزون المتبقي</dt><dd>غير متاحة / غير معترف بها</dd></div>
      <div><dt>الإيراد المعترف به</dt><dd>{formatMinorUnits(result.recognized_revenue_minor_units, result.currency)}</dd></div>
      <div><dt>المحصل</dt><dd>{formatMinorUnits(result.cash_collected_minor_units, result.currency)}</dd></div>
      <div><dt>المتبقي للتحصيل</dt><dd>{formatMinorUnits(result.receivable_outstanding_minor_units, result.currency)}</dd></div>
      <div><dt>تكلفة التشغيل</dt><dd>{formatMinorUnits(result.attributed_operating_cost_minor_units, result.currency)}</dd></div>
      <div><dt>النتيجة التشغيلية الحالية</dt><dd>{formatMinorUnits(result.operating_result_to_date_minor_units, result.currency)}</dd></div>
      <div><dt>العائد لكل مساحة</dt><dd>{result.yield_per_area && result.quantity_unit && result.area_unit ? `${result.yield_per_area} ${result.quantity_unit}/${formatAreaUnit(result.area_unit)}` : 'غير متاح مع الوحدات الحالية'}</dd></div>
      <div><dt>الإيراد لكل مساحة</dt><dd>{perArea(result.recognized_revenue_minor_units_per_area)}</dd></div>
      <div><dt>تكلفة التشغيل لكل مساحة</dt><dd>{perArea(result.operating_cost_minor_units_per_area)}</dd></div>
      <div><dt>متوسط سعر البيع المحقق</dt><dd>{result.realized_average_selling_price_minor_units && result.quantity_unit ? `${formatMinorUnits(result.realized_average_selling_price_minor_units, result.currency)} / ${result.quantity_unit}` : 'غير متاح'}</dd></div>
      <div><dt>اكتمال المصادر والأدلة</dt><dd>{formatEvidenceCompleteness(result.source_evidence_completeness)}</dd></div>
    </dl>
  );
}

function ResultLandPosition({ result }: Readonly<{ result: CropCycleResultRead }>) {
  const landBasis = result.land_control_bases
    ?.split('، ')
    .map((basis) => formatLandControlBasis(basis))
    .join(' · ');
  return (
    <div className="card stack">
      <h4>الأرض كأصل استثماري</h4>
      <p>{result.land_asset_names ?? 'لا يوجد أصل أرض مرتبط بالمزرعة'}{landBasis ? ` · ${landBasis}` : ''}</p>
      {BigInt(result.land_consideration_minor_units) > 0n ? <p>مقابل شراء الأرض المنفصل: {formatMinorUnits(result.land_consideration_minor_units, result.currency)}</p> : null}
      <p className="muted">هذا المركز منفصل دائمًا عن تكلفة تشغيل دورة المحصول؛ لا إهلاك أو استهلاك أو قيمة عادلة تلقائية.</p>
    </div>
  );
}

function ResultIssues({ issues }: Readonly<{ issues: CropCycleIntegrityIssueRead[] }>) {
  if (issues.length === 0) return <p className="muted">لا توجد استثناءات مفتوحة.</p>;
  return (
    <div className="card stack" aria-label="استثناءات الدورة">
      <h4>الاستثناءات والمراكز المفتوحة</h4>
      <ul>{issues.map((issue, index) => <li key={`${issue.code}-${index}`} className={issue.severity === 'HARD' ? 'error' : undefined}>{issue.severity === 'HARD' ? 'مانع إغلاق: ' : 'مركز مفتوح: '}{issue.message_ar}</li>)}</ul>
    </div>
  );
}

function ResultCloseMetadata({ result }: Readonly<{ result: CropCycleResultRead }>) {
  if (!result.closed_at) return null;
  return (
    <div className="card stack">
      <h4>بيانات الإغلاق</h4>
      <p>أُغلقت في {d(result.closed_at)} · السبب: {result.close_reason}</p>
      <p className="muted">دليل الإغلاق: {result.close_evidence_reference}. التحصيلات والمخزون المفتوحان يظلان ظاهرين بعد الإغلاق.</p>
    </div>
  );
}

function ResultActions({ organizationId, projectId, result, assignments, fields, costSources, canClose }:
Readonly<{
  organizationId: string;
  projectId: string;
  result: CropCycleResultRead;
  assignments: CropAssignmentRead[];
  fields: FieldRead[];
  costSources: CropCycleCostSourceRead[];
  canClose: boolean;
}>) {
  if (!canClose) return <p className="muted">تحميل التكلفة والإغلاق يتطلبان صلاحية مالك المنظمة.</p>;
  return (
    <>
      <details><summary>تحميل تكلفة تشغيل من مصدر مالي معتمد</summary><CropCycleCostAttributionForm organizationId={organizationId} projectId={projectId} result={result} assignments={assignments} fields={fields} sources={costSources} /></details>
      {!result.closed_at ? <CropCycleCloseoutForm organizationId={organizationId} projectId={projectId} result={result} /> : null}
    </>
  );
}

function CropCycleResultCard({ organizationId, projectId, result, issues, assignments, fields, costSources, canClose }:
Readonly<{
  organizationId: string;
  projectId: string;
  result: CropCycleResultRead;
  issues: CropCycleIntegrityIssueRead[];
  assignments: CropAssignmentRead[];
  fields: FieldRead[];
  costSources: CropCycleCostSourceRead[];
  canClose: boolean;
}>) {
  return (
    <article className="card stack" aria-labelledby={`result-${result.crop_cycle_id}`}>
      <header className="topline">
        <div><h3 id={`result-${result.crop_cycle_id}`}>{result.crop} {result.variety ? `· ${result.variety}` : ''}</h3><p className="muted">{result.season_reference} · {result.farm_names} · {result.field_identifiers}</p></div>
        <span className="status">{CYCLE_STATE_LABEL[result.operational_state] ?? result.operational_state}</span>
      </header>
      <ResultMetrics result={result} />
      <ResultLandPosition result={result} />
      <ResultIssues issues={issues} />
      <ResultCloseMetadata result={result} />
      <ResultActions organizationId={organizationId} projectId={projectId} result={result} assignments={assignments} fields={fields} costSources={costSources} canClose={canClose} />
    </article>
  );
}

export default async function AgriculturePage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  if (project.sector !== 'AGRICULTURE') {
    // Real Estate projects must not render this Agriculture workspace.
    return (
      <ForbiddenCard
        projectId={projectId}
        message="هذا المشروع عقاري. ادخل إلى مساحة العقارات من صفحة المشروع."
      />
    );
  }
  const organizationId = project.organization_id;
  const currency = project.reporting_currency;

  const [
    membership, landAssets, farmLandLinks, parties, cashAccounts,
    farms, fields, cycles, assignments, timeline, activities,
    inputItems, inputLots, inputApplications,
    storages, harvestEvents, harvestLots, inventoryByLocation, inventoryMovements,
    sales, saleLines, saleCollections, lotSaleTraceability,
    cycleResults, cycleIssues, costSources,
  ] = await Promise.all([
    getCurrentMembership(organizationId),
    getAgriculturalLandAssets(projectId),
    getFarmLandAssetLinks(projectId),
    getParties(organizationId),
    getCashAccountPositions(projectId),
    getFarms(projectId),
    getFields(projectId),
    getCropCycles(projectId),
    getCropAssignments(projectId),
    getCropCycleTimeline(projectId),
    getFieldActivities(projectId),
    getInputItems(projectId),
    getInputLots(projectId),
    getInputApplications(projectId),
    getStorageLocations(projectId),
    getHarvestEvents(projectId),
    getHarvestLots(projectId),
    getHarvestInventoryByLocation(projectId),
    getHarvestInventoryMovements(projectId),
    getAgricultureSales(projectId),
    getAgricultureSaleLines(projectId),
    getAgricultureSaleCollections(projectId),
    getHarvestLotSaleTraceability(projectId),
    getCropCycleResults(projectId),
    getCropCycleIntegrityIssues(projectId),
    getCropCycleCostSources(projectId),
  ]);

  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="عضويتك الحالية لا تسمح بقراءة عمليات الزراعة لهذا المشروع." />;
  }

  const farmById = new Map(farms.map((f) => [f.id, f]));
  const fieldById = new Map(fields.map((f) => [f.id, f]));
  const cycleById = new Map(cycles.map((c) => [c.id, c]));
  const canPostSales = membership.role === 'OWNER';

  // No fabricated finance. We surface only the shared-core information
  // (project name, currency) plus truthful Farm / Field / CropCycle
  // summaries that the canonical read models return.
  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="agriculture"
        sector="AGRICULTURE"
        title="المزرعة والمحاصيل"
        subtitle={`${project.name} · ${currency} · مساحة الزراعة`}
        internalReference={project.internal_reference}
        lifecycleState={project.lifecycle_state}
      />
      <InPageTabs
        label="أقسام الزراعة"
        items={[
          { href: '#overview', label: 'نظرة' },
          { href: '#profile', label: 'الملف' },
          { href: '#land-assets', label: 'الأراضي' },
          { href: '#farms', label: 'المزارع' },
          { href: '#fields', label: 'الحقول' },
          { href: '#cycles', label: 'الدورات' },
          { href: '#assignments', label: 'التخصيص' },
          { href: '#activities', label: 'الأنشطة' },
          { href: '#inputs', label: 'المدخلات' },
          { href: '#harvest', label: 'الحصاد' },
          { href: '#sales', label: 'المبيعات' },
          { href: '#results-closeout', label: 'النتائج والإغلاق' },
          { href: '#timeline', label: 'السجل' },
        ]}
      />

      <section className="card stack scroll-target" id="overview">
        <h2>نظرة الزراعة</h2>
        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>عدد المزارع</span>
            <strong>{farms.length}</strong>
            <small>في هذا المشروع</small>
          </article>
          <article className="overview-kpi">
            <span>عدد الحقول</span>
            <strong>{fields.length}</strong>
            <small>ضمن المزارع المسجلة</small>
          </article>
          <article className="overview-kpi">
            <span>دورات المحصول</span>
            <strong>{cycles.length}</strong>
            <small>مخططة ونشطة ومكتملة</small>
          </article>
          <article className="overview-kpi">
            <span>تخصيصات نشطة</span>
            <strong>
              {assignments.filter((a) => {
                const c = cycleById.get(a.crop_cycle_id);
                return c && c.operational_state !== 'CANCELLED';
              }).length}
            </strong>
            <small>دورات غير ملغاة على حقول</small>
          </article>
          <article className="overview-kpi">
            <span>تطبيقات المدخلات</span>
            <strong>{inputApplications.length}</strong>
            <small>وقائع تطبيق فعلية مسجّلة</small>
          </article>
        </div>
        <p className="muted">
          هذه القيم مصدرها المباشر قواعد الزراعة في هذا المشروع. لا توجد حسابات مالية أو محصولية مُحتسبة هنا في هذه الشريحة.
        </p>
      </section>

      <section className="card stack scroll-target" id="profile">
        <h2>ملف الزراعة</h2>
        <p className="muted">ملف الزراعة يُنشأ مرة واحدة لكل مشروع زراعي.</p>
        {farms.length > 0 ? (
          <p className="muted">تم إنشاء ملف الزراعة. لا يلزم تسجيله مرة أخرى.</p>
        ) : (
          <ProfileForm organizationId={organizationId} projectId={projectId} />
        )}
      </section>

      <section className="card stack scroll-target" id="land-assets">
        <div className="section-heading">
          <div>
            <h2>الأراضي والأصول</h2>
            <p className="muted">الأرض أصل استثماري/قانوني · المزرعة وحدة تشغيل · الحقل وحدة زراعية.</p>
          </div>
          <span className="status">{landAssets.length} أصل</span>
        </div>
        {landAssets.length === 0 ? (
          <div className="card empty stack">
            <h3>لا توجد أرض استثمارية مسجلة</h3>
            <p className="muted">المزارع القائمة لن يُنشأ لها أصل وهمي. سجّل السيطرة الحقيقية ثم اربط المزرعة المناسبة.</p>
            <AgriculturalLandAssetForm organizationId={organizationId} projectId={projectId} currency={currency} parties={parties} />
          </div>
        ) : (
          <>
            <div className="asset-grid">
              {landAssets.map((asset) => (
                <article className="card stack" key={asset.id}>
                  <div className="topline"><div><h3>{asset.name}</h3><p className="muted">{asset.internal_reference}</p></div><span className="status">{formatLandControlBasis(asset.control_basis)}</span></div>
                  <dl className="facts">
                    <div><dt>المساحة القانونية/التعاقدية</dt><dd>{asset.legal_area_quantity} {formatAreaUnit(asset.area_unit)}</dd></div>
                    <div><dt>الطرف المقابل</dt><dd>{asset.counterparty_name}</dd></div>
                    <div><dt>فترة السيطرة</dt><dd>{formatDate(asset.control_start_date)} → {asset.control_end_date ? formatDate(asset.control_end_date) : 'مفتوحة'}</dd></div>
                    <div><dt>مرجع الاتفاق</dt><dd>{asset.agreement_reference}</dd></div>
                    <div><dt>مرجع قانوني/حيازي</dt><dd>{asset.legal_reference ?? 'غير مسجل'}</dd></div>
                    <div><dt>المزارع المرتبطة</dt><dd>{asset.linked_farm_count}</dd></div>
                  </dl>
                  {asset.agreed_consideration_minor_units && asset.consideration_currency ? (
                    <p><strong>المقابل المتفق عليه:</strong> {formatMinorUnits(asset.agreed_consideration_minor_units, asset.consideration_currency)}</p>
                  ) : <p className="muted">لا يوجد مقابل شراء موثق في هذا السجل.</p>}
                  <p className="muted">المقابل ليس سدادًا أو قيمة دفترية/تقييمًا، ولا يُحمّل تلقائيًا على دورة محصول. دليل السيطرة: {asset.evidence_reference}</p>
                </article>
              ))}
            </div>
            <details><summary>تسجيل أرض/أصل آخر</summary><AgriculturalLandAssetForm organizationId={organizationId} projectId={projectId} currency={currency} parties={parties} /></details>
          </>
        )}
        <div className="card stack">
          <h3>ربط المزرعة بالأرض الاستثمارية</h3>
          {farms.length === 0 ? <p className="muted">سجّل مزرعة تشغيلية أولًا.</p> : (
            <>
              <div className="table-wrap"><table className="table-stackable"><thead><tr><th>المزرعة</th><th>الأرض/الأصل</th><th>حالة الربط</th></tr></thead><tbody>{farms.map((farm) => {
                const link = farmLandLinks.find((item) => item.farm_id === farm.id);
                return <tr key={farm.id}><td data-label="المزرعة">{farm.name}</td><td data-label="الأرض/الأصل">{link?.land_asset_name ?? '—'}</td><td data-label="حالة الربط">{link ? 'مرتبط' : 'لا يوجد أصل استثماري مرتبط'}</td></tr>;
              })}</tbody></table></div>
              <FarmLandAssetLinkForm organizationId={organizationId} projectId={projectId} landAssets={landAssets} farms={farms} linkedFarmIds={farmLandLinks.map((link) => link.farm_id)} />
            </>
          )}
        </div>
      </section>

      <section className="card stack scroll-target" id="farms">
        <h2>المزارع</h2>
        {farms.length === 0 ? (
          <div className="card empty">
            <h3>لا توجد مزارع بعد</h3>
            <p className="muted">سجّل أول مزرعة. الحقول ودورات المحصول ترتبط بها لاحقًا.</p>
            <FarmForm organizationId={organizationId} projectId={projectId} />
          </div>
        ) : (
          <>
            <div className="table-wrap">
              <table className="table-stackable">
                <thead>
                  <tr>
                    <th>الاسم</th>
                    <th>المرجع</th>
                    <th>الموقع</th>
                    <th>المنطقة الزمنية</th>
                    <th>عدد الحقول</th>
                  </tr>
                </thead>
                <tbody>
                  {farms.map((f) => (
                    <tr key={f.id}>
                      <td data-label="الاسم">{f.name}</td>
                      <td data-label="المرجع">{f.internal_reference ?? '—'}</td>
                      <td data-label="الموقع">{f.operating_location ?? '—'}</td>
                      <td data-label="المنطقة الزمنية">{f.timezone}</td>
                      <td data-label="عدد الحقول">{fields.filter((fld) => fld.farm_id === f.id).length}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <details>
              <summary>إضافة مزرعة أخرى</summary>
              <FarmForm organizationId={organizationId} projectId={projectId} />
            </details>
          </>
        )}
      </section>

      <section className="card stack scroll-target" id="fields">
        <h2>الحقول</h2>
        {fields.length === 0 ? (
          <div className="card empty">
            <h3>لا توجد حقول</h3>
            <p className="muted">أضف مزرعة أولًا، ثم سجّل أول حقل بمساحة موجبة ووحدة مدعومة (م²، هكتار، فدان).</p>
            {farms.length > 0 ? (
              <FieldForm organizationId={organizationId} projectId={projectId} farms={farms} />
            ) : null}
          </div>
        ) : (
          <>
            <div className="table-wrap">
              <table className="table-stackable">
                <thead>
                  <tr>
                    <th>المزرعة</th>
                    <th>الحقل</th>
                    <th>المساحة</th>
                    <th>الوحدة</th>
                    <th>ملاحظات</th>
                  </tr>
                </thead>
                <tbody>
                  {fields.map((f) => (
                    <tr key={f.id}>
                      <td data-label="المزرعة">{farmById.get(f.farm_id)?.name ?? '—'}</td>
                      <td data-label="الحقل">{f.identifier}</td>
                      <td data-label="المساحة">{f.area_quantity}</td>
                      <td data-label="الوحدة">{formatAreaUnit(f.area_unit)}</td>
                      <td data-label="ملاحظات">
                        {f.soil_notes ? <div>تربة: {f.soil_notes}</div> : null}
                        {f.irrigation_notes ? <div>ري: {f.irrigation_notes}</div> : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {farms.length > 0 ? (
              <details>
                <summary>إضافة حقل</summary>
                <FieldForm organizationId={organizationId} projectId={projectId} farms={farms} />
              </details>
            ) : null}
          </>
        )}
      </section>

      <section className="card stack scroll-target" id="cycles">
        <h2>دورات المحصول</h2>
        {cycles.length === 0 ? (
          <div className="card empty">
            <h3>لا توجد دورات محصول</h3>
            <p className="muted">أنشئ أول دورة محصول. كل دورة تبدأ في الحالة &quot;مخططة&quot; ثم تنتقل وفق المسار الرسمي.</p>
            <CropCycleForm organizationId={organizationId} projectId={projectId} />
          </div>
        ) : (
          <>
            <div className="stack">
              {cycles.map((c) => {
                const cycleAssignments = assignments.filter((a) => a.crop_cycle_id === c.id);
                return (
                  <article key={c.id} className="card stack">
                    <header className="topline">
                      <div>
                        <h3>
                          {c.crop}
                          {c.variety ? ` · ${c.variety}` : ''}
                        </h3>
                        <p className="muted">
                          {c.season_reference} · {d(c.planned_start_date)} → {d(c.planned_end_date)}
                        </p>
                      </div>
                      <span className="status">{CYCLE_STATE_LABEL[c.operational_state] ?? c.operational_state}</span>
                    </header>
                    <div className="overview-kpis">
                      <article className="overview-kpi">
                        <span>الكمية المستهدفة</span>
                        <strong>{formatQuantity(c.target_yield_quantity, c.target_yield_unit)}</strong>
                        <small>من دورة حياة الدورة</small>
                      </article>
                      <article className="overview-kpi">
                        <span>تخصيصات الدورة</span>
                        <strong>{cycleAssignments.length}</strong>
                        <small>عدد الحقول المخصصة</small>
                      </article>
                    </div>
                    {cycleAssignments.length > 0 ? (
                      <div className="table-wrap">
                        <table className="table-stackable">
                          <thead>
                            <tr>
                              <th>الحقل</th>
                              <th>المزرعة</th>
                              <th>المساحة المخصصة</th>
                              <th>الفترة</th>
                            </tr>
                          </thead>
                          <tbody>
                            {cycleAssignments.map((a) => {
                              const field = fieldById.get(a.field_id);
                              const farm = field ? farmById.get(field.farm_id) : undefined;
                              return (
                                <tr key={a.id}>
                                  <td data-label="الحقل">{field?.identifier ?? '—'}</td>
                                  <td data-label="المزرعة">{farm?.name ?? '—'}</td>
                                  <td data-label="المساحة المخصصة">
                                    {a.assigned_area_quantity} {AREA_UNIT_LABEL[a.assigned_area_unit]}
                                  </td>
                                  <td data-label="الفترة">
                                    {d(a.planned_start_date)} → {d(a.planned_end_date)}
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    ) : null}
                    <details>
                      <summary>تأكيد انتقال حالة</summary>
                      <CycleTransitionForm
                        organizationId={organizationId}
                        projectId={projectId}
                        cycle={c}
                      />
                    </details>
                  </article>
                );
              })}
            </div>
            <details>
              <summary>إنشاء دورة محصول جديدة</summary>
              <CropCycleForm organizationId={organizationId} projectId={projectId} />
            </details>
          </>
        )}
      </section>

      <section className="card stack scroll-target" id="assignments">
        <h2>تخصيص الحقول للدورات</h2>
        <p className="muted">
          يضمن النظام أن وحدة المساحة المخصصة تطابق وحدة الحقل، وأن مجموع المساحات في أي فترة متداخلة لا يتجاوز سعة الحقل.
        </p>
        <AssignmentForm
          organizationId={organizationId}
          projectId={projectId}
          cycles={cycles}
          fields={fields}
        />
      </section>

      <section className="card stack scroll-target" id="activities">
        <h2>أنشطة الحقل</h2>
        <p className="muted">
          سجل تشغيلي لما حدث في الحقل على تخصيص دورة-حقل قائم. لا يغيّر حالة الدورة ولا ينشئ مخزونًا أو قيدًا.
        </p>
        {activities.length === 0 ? (
          <div className="card empty">
            <h3>لا توجد أنشطة مسجّلة</h3>
            <p className="muted">بعد تخصيص حقل لدورة، سجّل الري أو التسميد أو المعاينة أو أي نشاط معتمد.</p>
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>التاريخ</th>
                  <th>النوع</th>
                  <th>الدورة</th>
                  <th>الحقل</th>
                  <th>الكمية</th>
                  <th>ملاحظات</th>
                </tr>
              </thead>
              <tbody>
                {activities.map((a) => {
                  const cycle = cycleById.get(a.crop_cycle_id);
                  const field = fieldById.get(a.field_id);
                  return (
                    <tr key={a.id}>
                      <td data-label="التاريخ">{d(a.activity_date)}</td>
                      <td data-label="النوع">{formatFieldActivityType(a.activity_type)}</td>
                      <td data-label="الدورة">{cycle ? `${cycle.crop} · ${cycle.season_reference}` : '—'}</td>
                      <td data-label="الحقل">{field?.identifier ?? '—'}</td>
                      <td data-label="الكمية">{a.quantity ? `${a.quantity} ${a.unit ?? ''}`.trim() : '—'}</td>
                      <td data-label="ملاحظات">
                        {a.notes ?? '—'}
                        {a.evidence_reference ? <div className="muted">دليل: {a.evidence_reference}</div> : null}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <FieldActivityForm
          organizationId={organizationId}
          projectId={projectId}
          assignments={assignments}
          cycles={cycles}
          fields={fields}
        />
      </section>

      <section className="card stack scroll-target" id="inputs">
        <h2>المدخلات والتطبيقات</h2>
        <p className="muted">
          تعريف المدخلات الزراعية (تقاوي، سماد، مبيد/كيماوي)، وتشغيلاتها القابلة للتتبع،
          وتسجيل تطبيقها الفعلي على نشاط حقل قائم.
        </p>
        <p className="muted">
          هذه الشريحة تُثبت الهوية والتتبّع والكمية والمساحة والصلاحية واتساق المشروع والتخصيص.
          لا يوجد رصيد مخزون للمدخلات ولا تحقق من توفر كمياتها؛ رصيد المخزون أدناه يخص محصول الحصاد فقط.
          التسجيل هنا لا ينشئ التزامًا أو دفعة أو قيدًا محاسبيًا ولا يغيّر حالة دورة المحصول.
        </p>

        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>المدخلات المعرّفة</span>
            <strong>{inputItems.length}</strong>
            <small>تقاوي وسماد ومبيدات</small>
          </article>
          <article className="overview-kpi">
            <span>التشغيلات</span>
            <strong>{inputLots.length}</strong>
            <small>سجلات تتبّع، وليست مخزونًا</small>
          </article>
          <article className="overview-kpi">
            <span>التطبيقات المسجّلة</span>
            <strong>{inputApplications.length}</strong>
            <small>وقائع تشغيلية غير قابلة للتعديل</small>
          </article>
          <article className="overview-kpi">
            <span>تشغيلات منتهية</span>
            <strong>{inputLots.filter((l) => l.expiry_status === 'EXPIRED').length}</strong>
            <small>لا تُقبل في تطبيق جديد</small>
          </article>
        </div>

        <h3 id="input-applications">أحدث التطبيقات</h3>
        {inputApplications.length === 0 ? (
          <div className="card empty">
            <h4>لا توجد تطبيقات مدخلات بعد</h4>
            <p className="muted">
              عرّف مدخلًا، ثم سجّل تشغيلة له، ثم اربط التطبيق بنشاط زراعة أو تسميد أو رش قائم.
            </p>
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="muted">
                تطبيقات المدخلات مرتبة من الأحدث. المعدل قيمة مشتقة للعرض (الكمية ÷ المساحة المعالجة) ولا تُخزَّن.
              </caption>
              <thead>
                <tr>
                  <th scope="col">التاريخ</th>
                  <th scope="col">المدخل</th>
                  <th scope="col">التشغيلة</th>
                  <th scope="col">النشاط</th>
                  <th scope="col">الدورة</th>
                  <th scope="col">الحقل</th>
                  <th scope="col">الكمية</th>
                  <th scope="col">المساحة المعالجة</th>
                  <th scope="col">المعدل</th>
                  <th scope="col">الصلاحية</th>
                  <th scope="col">ملاحظات</th>
                </tr>
              </thead>
              <tbody>
                {inputApplications.map((a) => (
                  <tr key={a.id}>
                    <td data-label="التاريخ">{d(a.application_date)}</td>
                    <td data-label="المدخل">
                      {a.input_item_name}
                      <div className="muted">{formatInputCategory(a.input_category)}</div>
                    </td>
                    <td data-label="التشغيلة">
                      {a.lot_reference}
                      {a.expires_on ? <div className="muted">تنتهي {d(a.expires_on)}</div> : null}
                    </td>
                    <td data-label="النشاط">{formatFieldActivityType(a.activity_type)}</td>
                    <td data-label="الدورة">{`${a.crop} · ${a.season_reference}`}</td>
                    <td data-label="الحقل">{a.field_identifier}</td>
                    <td data-label="الكمية">{formatInputQuantity(a.quantity, a.unit)}</td>
                    <td data-label="المساحة المعالجة">{`${a.applied_area_quantity} ${formatAreaUnit(a.applied_area_unit)}`}</td>
                    <td data-label="المعدل">{`${a.application_rate} ${a.unit}/${formatAreaUnit(a.applied_area_unit)}`}</td>
                    <td data-label="الصلاحية">
                      <span className="status">{formatLotExpiryStatus(a.lot_expiry_status)}</span>
                    </td>
                    <td data-label="ملاحظات">
                      {a.notes ?? '—'}
                      {a.safety_note ? <div className="muted">سلامة: {a.safety_note}</div> : null}
                      {a.evidence_reference ? <div className="muted">دليل: {a.evidence_reference}</div> : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <details open={inputApplications.length === 0 && inputItems.length > 0}>
          <summary>تسجيل تطبيق مدخل</summary>
          <InputApplicationForm
            organizationId={organizationId}
            projectId={projectId}
            activities={activities}
            assignments={assignments}
            cycles={cycles}
            fields={fields}
            items={inputItems}
            lots={inputLots}
          />
        </details>

        <h3 id="input-items">المدخلات المعرّفة</h3>
        {inputItems.length === 0 ? (
          <div className="card empty">
            <h4>لا توجد مدخلات معرّفة</h4>
            <p className="muted">ابدأ بتعريف مدخل واحد بفئته ووحدة تطبيقه.</p>
            <InputItemForm organizationId={organizationId} projectId={projectId} />
          </div>
        ) : (
          <>
            <div className="table-wrap">
              <table className="table-stackable">
                <thead>
                  <tr>
                    <th scope="col">الفئة</th>
                    <th scope="col">الاسم</th>
                    <th scope="col">وحدة التطبيق</th>
                    <th scope="col">المرجع</th>
                    <th scope="col">المُصنِّع</th>
                    <th scope="col">التشغيلات</th>
                  </tr>
                </thead>
                <tbody>
                  {inputItems.map((i) => (
                    <tr key={i.id}>
                      <td data-label="الفئة">{formatInputCategory(i.category)}</td>
                      <td data-label="الاسم">
                        {i.name}
                        {i.notes ? <div className="muted">{i.notes}</div> : null}
                      </td>
                      <td data-label="وحدة التطبيق">{i.application_unit}</td>
                      <td data-label="المرجع">{i.internal_reference ?? '—'}</td>
                      <td data-label="المُصنِّع">{i.manufacturer ?? '—'}</td>
                      <td data-label="التشغيلات">{inputLots.filter((l) => l.input_item_id === i.id).length}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <details>
              <summary>تعريف مدخل آخر</summary>
              <InputItemForm organizationId={organizationId} projectId={projectId} />
            </details>
          </>
        )}

        <h3 id="input-lots">التشغيلات</h3>
        {inputLots.length === 0 ? (
          <p className="muted">لا توجد تشغيلات بعد. التشغيلة سجل تتبّع للمدخل، وليست رصيد مخزون.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th scope="col">المدخل</th>
                  <th scope="col">مرجع التشغيلة</th>
                  <th scope="col">الوحدة</th>
                  <th scope="col">التصنيع</th>
                  <th scope="col">الانتهاء</th>
                  <th scope="col">الحالة</th>
                  <th scope="col">المورد / الدليل</th>
                </tr>
              </thead>
              <tbody>
                {inputLots.map((l) => (
                  <tr key={l.id}>
                    <td data-label="المدخل">
                      {l.input_item_name}
                      <div className="muted">{formatInputCategory(l.input_category)}</div>
                    </td>
                    <td data-label="مرجع التشغيلة">{l.lot_reference}</td>
                    <td data-label="الوحدة">{l.unit}</td>
                    <td data-label="التصنيع">{d(l.manufactured_on)}</td>
                    <td data-label="الانتهاء">{d(l.expires_on)}</td>
                    <td data-label="الحالة">
                      <span className="status">{formatLotExpiryStatus(l.expiry_status)}</span>
                    </td>
                    <td data-label="المورد / الدليل">
                      {l.supplier_reference ?? '—'}
                      {l.evidence_reference ? <div className="muted">دليل: {l.evidence_reference}</div> : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {inputItems.length > 0 ? (
          <details>
            <summary>تسجيل تشغيلة</summary>
            <InputLotForm
              organizationId={organizationId}
              projectId={projectId}
              items={inputItems}
            />
          </details>
        ) : null}
      </section>

      <section className="card stack scroll-target" id="harvest">
        <h2>الحصاد والمخزون</h2>
        <p className="muted">
          أحداث الحصاد، تشغيلات المحصول الناتجة، مواقع التخزين، وحركات المخزون المتراكمة.
          الرصيد الحالي لكل تشغيلة/موقع يُشتق من حركات المخزون ولا يُخزَّن أو يُدخَل يدويًا.
        </p>
        <p className="muted">
          هذه الشريحة تتعقب كمية محصول الحصاد التشغيلية. صرف البيع يخصم الكمية عبر حركة موثقة أدناه،
          لكن لا تُخمن قيمة للمخزون أو تكلفة بضاعة، ولا يوجد رصيد مخزون للمدخلات الزراعية هنا.
        </p>

        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>أحداث الحصاد</span>
            <strong>{harvestEvents.length}</strong>
            <small>وقائع حصاد فعلية مسجّلة</small>
          </article>
          <article className="overview-kpi">
            <span>تشغيلات الحصاد</span>
            <strong>{harvestLots.length}</strong>
            <small>محصول قابل للتتبع</small>
          </article>
          <article className="overview-kpi">
            <span>مواقع التخزين</span>
            <strong>{storages.length}</strong>
            <small>مواقع استلام محصول</small>
          </article>
          <article className="overview-kpi">
            <span>حركات المخزون</span>
            <strong>{inventoryMovements.length}</strong>
            <small>سجل متراكم غير قابل للتعديل</small>
          </article>
        </div>

        <h3 id="harvest-events">أحداث الحصاد</h3>
        {harvestEvents.length === 0 ? (
          <div className="card empty">
            <h4>لا توجد أحداث حصاد بعد</h4>
            <p className="muted">
              سجّل أول حدث حصاد لدورة في حالة &quot;قيد الحصاد&quot; مع موقع تخزين لاستلام المحصول.
            </p>
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th scope="col">التاريخ</th>
                  <th scope="col">الدورة</th>
                  <th scope="col">الحقل</th>
                  <th className="num" scope="col">الإجمالي</th>
                  <th scope="col">الصافي</th>
                  <th scope="col">الفاقد</th>
                  <th scope="col">الدرجة</th>
                  <th scope="col">التشغيلة</th>
                  <th scope="col">موقع الاستلام</th>
                </tr>
              </thead>
              <tbody>
                {harvestEvents.map((e) => (
                  <tr key={e.id}>
                    <td data-label="التاريخ">{d(e.harvest_date)}</td>
                    <td data-label="الدورة">{`${e.crop} · ${e.season_reference}`}</td>
                    <td data-label="الحقل">{e.field_identifier}</td>
                    <td className="num" data-label="الإجمالي">{formatHarvestQuantity(e.gross_quantity, e.quantity_unit)}</td>
                    <td data-label="الصافي">{formatHarvestQuantity(e.net_quantity, e.quantity_unit)}</td>
                    <td data-label="الفاقد">{formatHarvestQuantity(e.harvest_loss, e.quantity_unit)}</td>
                    <td data-label="الدرجة">{e.grade ?? '—'}</td>
                    <td data-label="التشغيلة">{e.lot_reference}</td>
                    <td data-label="موقع الاستلام">{e.destination_storage_name ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <details open={harvestEvents.length === 0 && storages.length > 0}>
          <summary>تسجيل حدث حصاد</summary>
          <HarvestEventForm
            organizationId={organizationId}
            projectId={projectId}
            cycles={cycles}
            assignments={assignments}
            fields={fields}
            storages={storages}
          />
        </details>

        <h3 id="harvest-lots">تشغيلات الحصاد</h3>
        {harvestLots.length === 0 ? (
          <p className="muted">لا توجد تشغيلات حصاد بعد. كل حدث حصاد ينشئ تشغيلة واحدة تلقائيًا.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th scope="col">مرجع التشغيلة</th>
                  <th scope="col">الدورة</th>
                  <th scope="col">الحقل</th>
                  <th scope="col">تاريخ الحصاد</th>
                  <th scope="col">الكمية الأولية</th>
                  <th className="num" scope="col">الرصيد الحالي الكلي</th>
                  <th scope="col">الدرجة</th>
                </tr>
              </thead>
              <tbody>
                {harvestLots.map((l) => (
                  <tr key={l.id}>
                    <td data-label="مرجع التشغيلة">{l.lot_reference}</td>
                    <td data-label="الدورة">{`${l.crop} · ${l.season_reference}`}</td>
                    <td data-label="الحقل">{l.field_identifier}</td>
                    <td data-label="تاريخ الحصاد">{d(l.harvest_date)}</td>
                    <td data-label="الكمية الأولية">{formatHarvestQuantity(l.initial_quantity, l.quantity_unit)}</td>
                    <td className="num" data-label="الرصيد الحالي الكلي">{formatHarvestQuantity(l.current_total_balance, l.quantity_unit)}</td>
                    <td data-label="الدرجة">{l.grade ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <h3 id="inventory-by-location">المخزون حسب الموقع</h3>
        {inventoryByLocation.length === 0 ? (
          <p className="muted">لا توجد أرصدة مخزون حصاد بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th scope="col">التشغيلة</th>
                  <th scope="col">موقع التخزين</th>
                  <th className="num" scope="col">الرصيد الحالي</th>
                  <th scope="col">آخر حركة</th>
                </tr>
              </thead>
              <tbody>
                {inventoryByLocation.map((e) => (
                  <tr key={`${e.harvest_lot_id}-${e.storage_id}`}>
                    <td data-label="التشغيلة">{e.lot_reference}</td>
                    <td data-label="موقع التخزين">{e.storage_name}</td>
                    <td className="num" data-label="الرصيد الحالي">{formatHarvestQuantity(e.current_balance, e.quantity_unit)}</td>
                    <td data-label="آخر حركة">{d(e.last_movement_date)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <h3 id="movement-history">سجل حركات المخزون</h3>
        {inventoryMovements.length === 0 ? (
          <p className="muted">لا توجد حركات مخزون بعد. الحركات سجل متراكم غير قابل للتعديل.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th scope="col">التاريخ</th>
                  <th scope="col">النوع</th>
                  <th scope="col">من</th>
                  <th scope="col">إلى</th>
                  <th scope="col">الكمية</th>
                  <th scope="col">السبب</th>
                </tr>
              </thead>
              <tbody>
                {inventoryMovements.map((m) => (
                  <tr key={m.id}>
                    <td data-label="التاريخ">{d(m.movement_date)}</td>
                    <td data-label="النوع">{formatHarvestMovementType(m.movement_type)}</td>
                    <td data-label="من">{m.from_storage_name ?? '—'}</td>
                    <td data-label="إلى">{m.to_storage_name ?? '—'}</td>
                    <td data-label="الكمية">{formatHarvestQuantity(m.quantity, m.unit)}</td>
                    <td data-label="السبب">
                      {m.reason ?? '—'}
                      {m.evidence_reference ? <div className="muted">دليل: {m.evidence_reference}</div> : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <h3 id="storage-locations">مواقع التخزين</h3>
        {storages.length === 0 ? (
          <div className="card empty">
            <h4>لا توجد مواقع تخزين</h4>
            <p className="muted">سجّل موقع تخزين لاستلام محصول الحصاد فيه.</p>
            <StorageLocationForm organizationId={organizationId} projectId={projectId} />
          </div>
        ) : (
          <>
            <div className="table-wrap">
              <table className="table-stackable">
                <thead>
                  <tr>
                    <th scope="col">الاسم</th>
                    <th scope="col">المرجع</th>
                    <th scope="col">ملاحظات</th>
                  </tr>
                </thead>
                <tbody>
                  {storages.map((s) => (
                    <tr key={s.id}>
                      <td data-label="الاسم">{s.name}</td>
                      <td data-label="المرجع">{s.internal_reference ?? '—'}</td>
                      <td data-label="ملاحظات">{s.notes ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <details>
              <summary>إضافة موقع تخزين</summary>
              <StorageLocationForm organizationId={organizationId} projectId={projectId} />
            </details>
          </>
        )}

        <h3 id="transfer-inventory">نقل المخزون</h3>
        <p className="muted">
          اختر تشغيلة وموقعها الحالي والوجهة والكمية. النقل يغيّر الموقع فقط ولا ينشئ كمية.
        </p>
        <TransferHarvestInventoryForm
          organizationId={organizationId}
          projectId={projectId}
          lots={harvestLots}
          inventory={inventoryByLocation}
          storages={storages}
        />

        <h3 id="adjust-inventory">تعديل / تالف</h3>
        <p className="muted">
          تعديل زيادة أو نقص أو تسجيل تالف بسبب واضح. لا يمكن أن يجعل الرصيد سالبًا.
        </p>
        <HarvestInventoryAdjustmentForm
          organizationId={organizationId}
          projectId={projectId}
          lots={harvestLots}
          inventory={inventoryByLocation}
        />
      </section>

      <section className="card stack scroll-target" id="sales">
        <div className="section-heading">
          <div><h2>المبيعات والتحصيل</h2><p className="muted">البيع والتسليم والإيراد والتحصيل وقائع مستقلة. النقد المحصل ليس هو الإيراد.</p></div>
          <span className="status">{sales.length} عملية بيع</span>
        </div>
        {sales.length === 0 ? (
          <div className="card empty stack"><h3>لا توجد مبيعات بعد</h3><p className="muted">اختر مشتريًا ورصيد تشغيلة حصاد متاحًا لإنشاء مسودة.</p><AgricultureSaleForm organizationId={organizationId} projectId={projectId} currency={currency} parties={parties} inventory={inventoryByLocation} /></div>
        ) : (
          <>
            <div className="stack">
              {sales.map((sale) => {
                const lines = saleLines.filter((line) => line.sale_id === sale.sale_id);
                const collections = saleCollections.filter((collection) => collection.sale_id === sale.sale_id);
                return (
                  <article className="card stack" key={sale.sale_id}>
                    <header className="topline"><div><h3>{sale.sale_reference} · {sale.buyer_name}</h3><p className="muted">{d(sale.sale_date)} · {sale.line_count} سطر</p></div><span className="status">{formatAgricultureSaleState(sale.state)}</span></header>
                    {(sale.agreement_reference || sale.evidence_reference || sale.control_transfer_evidence_reference) ? <p className="muted">{sale.agreement_reference ? `العقد/الطلب: ${sale.agreement_reference}` : ''}{sale.evidence_reference ? ` · دليل الاتفاق: ${sale.evidence_reference}` : ''}{sale.control_transfer_evidence_reference ? ` · دليل التسليم: ${sale.control_transfer_evidence_reference}` : ''}</p> : null}
                    <dl className="facts">
                      <div><dt>القيمة المتفق عليها</dt><dd>{formatMinorUnits(sale.agreed_total_minor_units, sale.currency)}</dd></div>
                      <div><dt>الإيراد المعترف به</dt><dd>{formatMinorUnits(sale.recognized_revenue_minor_units, sale.currency)}</dd></div>
                      <div><dt>النقد المحصل</dt><dd>{formatMinorUnits(sale.collected_minor_units, sale.currency)}</dd></div>
                      <div><dt>الذمة المتبقية</dt><dd>{formatMinorUnits(sale.outstanding_receivable_minor_units, sale.currency)}</dd></div>
                      <div><dt>الكمية</dt><dd>{sale.aggregate_quantity ? `${sale.aggregate_quantity} ${sale.quantity_unit}` : 'وحدات متعددة — راجع السطور'}</dd></div>
                      <div><dt>تاريخ التسليم</dt><dd>{d(sale.control_transfer_date)}</dd></div>
                    </dl>
                    <div className="table-wrap"><table className="table-stackable"><thead><tr><th>التشغيلة</th><th>موقع المصدر</th><th>الكمية</th><th className="num">سعر الوحدة</th><th className="num">قيمة السطر</th><th>الصرف</th></tr></thead><tbody>{lines.map((line) => <tr key={line.sale_line_id}><td data-label="التشغيلة">{line.lot_reference}</td><td data-label="موقع المصدر">{line.source_storage_name}</td><td data-label="الكمية">{formatHarvestQuantity(line.quantity, line.unit)}</td><td className="num" data-label="سعر الوحدة">{formatMinorUnits(line.unit_price_minor_units, sale.currency)}</td><td className="num" data-label="قيمة السطر">{formatMinorUnits(line.line_amount_minor_units, sale.currency)}</td><td data-label="الصرف">{line.sale_issue_movement_id ? `تم ${d(line.dispatch_date)}` : 'لم يتم'}</td></tr>)}</tbody></table></div>
                    {sale.state === 'DRAFT' && canPostSales ? <ApproveAgricultureSaleForm organizationId={organizationId} projectId={projectId} saleId={sale.sale_id} /> : null}
                    {sale.state === 'APPROVED' && canPostSales ? <RecognizeAgricultureSaleForm organizationId={organizationId} projectId={projectId} saleId={sale.sale_id} /> : null}
                    {!canPostSales && (sale.state === 'DRAFT' || sale.state === 'APPROVED') ? <p className="muted">الاعتماد والتسليم/الترحيل المالي يتطلبان صلاحية مالك المنظمة.</p> : null}
                    {sale.recognition_id ? <p className="muted">الإيراد والذمة موثقان في القيد المشترك. لا توجد تكلفة بضاعة/مخزون مخمّنة لأن سياسة قيمة الحصاد غير معتمدة.</p> : <p className="muted">المسودة/الاعتماد لا يثبتان إيرادًا أو ذمة ولا يصرفان مخزونًا.</p>}
                    {collections.length > 0 ? <div><h4>التحصيلات</h4><ul>{collections.map((collection) => <li key={collection.collection_id}>{d(collection.collection_date)} · {formatMinorUnits(collection.amount_minor_units, collection.currency)} · {collection.cash_account_name} · دليل: {collection.evidence_reference}</li>)}</ul></div> : null}
                    {canPostSales ? <AgricultureSaleCollectionForm organizationId={organizationId} projectId={projectId} sale={sale} cashAccounts={cashAccounts} /> : null}
                  </article>
                );
              })}
            </div>
            <details><summary>إنشاء مسودة بيع جديدة</summary><AgricultureSaleForm organizationId={organizationId} projectId={projectId} currency={currency} parties={parties} inventory={inventoryByLocation} /></details>
          </>
        )}
        <div className="card stack">
          <h3>تتبّع تشغيلة الحصاد إلى البيع</h3>
          <p className="muted">خطوة واحدة للأمام من التشغيلة إلى موقع الصرف والمشتري والتسليم وقيد الإيراد.</p>
          <div className="table-wrap"><table className="table-stackable"><thead><tr><th>التشغيلة</th><th>البيع</th><th>المشتري</th><th>المصدر</th><th>الكمية المباعة</th><th className="num">الإيراد</th></tr></thead><tbody>{lotSaleTraceability.map((trace, index) => <tr key={`${trace.harvest_lot_id}-${trace.sale_line_id ?? index}`}><td data-label="التشغيلة">{trace.lot_reference}</td><td data-label="البيع">{trace.sale_reference ?? 'لم تُبع'}</td><td data-label="المشتري">{trace.buyer_name ?? '—'}</td><td data-label="المصدر">{trace.source_storage_name ?? '—'}</td><td data-label="الكمية المباعة">{trace.sold_quantity ? formatHarvestQuantity(trace.sold_quantity, trace.quantity_unit) : '—'}</td><td className="num" data-label="الإيراد">{trace.revenue_journal_batch_id ? 'معترف به' : '—'}</td></tr>)}</tbody></table></div>
        </div>
      </section>

      <section className="card stack scroll-target" id="results-closeout">
        <div className="section-heading">
          <div>
            <h2>النتائج والإغلاق</h2>
            <p className="muted">نتيجة تشغيلية قابلة للتتبع من الحصاد والبيع والقيد المالي المعتمد — وليست رصيدًا قابلًا للتعديل.</p>
          </div>
          <span className="status">{cycleResults.length} دورة</span>
        </div>
        <div className="card stack">
          <h3>حدود النتيجة</h3>
          <p className="muted">الإيراد المعترف به يختلف عن النقد المحصل. مقابل شراء الأرض منفصل عن تكلفة تشغيل الموسم. المخزون المتبقي كمية فعلية فقط؛ قيمته غير متاحة وغير معترف بها وفق السياسة الحالية، ولا نحسب تكلفة بضاعة مباعة تخمينية.</p>
          <p className="muted">تشغيلات المدخلات للتتبّع فقط: تطبيق المدخل لا يدّعي التحقق من رصيد مخزون متاح. الشراء والاستلام ومخزون المدخلات مؤجل إلى نطاق ERP زراعي لاحق.</p>
        </div>
        {cycleResults.length === 0 ? (
          <div className="card empty"><h3>لا توجد نتائج دورات بعد</h3><p className="muted">أنشئ دورة محصول وخصص لها حقلًا لتظهر قاعدة النتيجة هنا.</p></div>
        ) : (
          <div className="stack">
            {cycleResults.map((result) => (
              <CropCycleResultCard
                key={result.crop_cycle_id}
                organizationId={organizationId}
                projectId={projectId}
                result={result}
                issues={cycleIssues.filter((issue) => issue.crop_cycle_id === result.crop_cycle_id)}
                assignments={assignments}
                fields={fields}
                costSources={costSources}
                canClose={canPostSales}
              />
            ))}
          </div>
        )}
      </section>

      <section className="card stack scroll-target" id="timeline">
        <h2>سجل دورة الحياة</h2>
        {timeline.length === 0 ? (
          <p className="muted">لا توجد انتقالات دورة حياة بعد.</p>
        ) : (
          <div className="timeline stack">
            {timeline.map((entry) => (
              <div className="timeline-row" key={entry.id}>
                <div>
                  <strong>
                    {entry.previous_state ? `${CYCLE_STATE_LABEL[entry.previous_state] ?? entry.previous_state} → ` : ''}
                    {CYCLE_STATE_LABEL[entry.new_state] ?? entry.new_state}
                  </strong>
                  <p>{entry.reason}</p>
                  {entry.evidence_reference ? <p className="muted">دليل: {entry.evidence_reference}</p> : null}
                </div>
                <time dateTime={entry.changed_at}>{formatDate(entry.changed_at)}</time>
              </div>
            ))}
          </div>
        )}
      </section>

      <p className="muted">
        <Link className="back-link" href={`/projects/${projectId}`}>→ العودة إلى مساحة المشروع</Link>
      </p>
    </section>
  );
}

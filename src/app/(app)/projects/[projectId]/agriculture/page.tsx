import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import {
  getCropAssignments,
  getCropCycles,
  getCropCycleTimeline,
  getFarms,
  getFieldActivities,
  getFields,
} from '@/features/agriculture/queries';
import {
  AREA_UNIT_LABEL,
  CYCLE_STATE_LABEL,
  formatAreaUnit,
  formatDate,
  formatFieldActivityType,
  formatQuantity,
} from '@/features/agriculture/labels';
import {
  AssignmentForm,
  CropCycleForm,
  CycleTransitionForm,
  FarmForm,
  FieldActivityForm,
  FieldForm,
  ProfileForm,
} from './forms';

export const dynamic = 'force-dynamic';

function d(value: string | null | undefined) {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
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

  const [membership, farms, fields, cycles, assignments, timeline, activities] = await Promise.all([
    getCurrentMembership(organizationId),
    getFarms(projectId),
    getFields(projectId),
    getCropCycles(projectId),
    getCropAssignments(projectId),
    getCropCycleTimeline(projectId),
    getFieldActivities(projectId),
  ]);

  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="عضويتك الحالية لا تسمح بقراءة عمليات الزراعة لهذا المشروع." />;
  }

  const farmById = new Map(farms.map((f) => [f.id, f]));
  const fieldById = new Map(fields.map((f) => [f.id, f]));
  const cycleById = new Map(cycles.map((c) => [c.id, c]));

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
              <table>
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
                      <td>{f.name}</td>
                      <td>{f.internal_reference ?? '—'}</td>
                      <td>{f.operating_location ?? '—'}</td>
                      <td>{f.timezone}</td>
                      <td>{fields.filter((fld) => fld.farm_id === f.id).length}</td>
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
              <table>
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
                      <td>{farmById.get(f.farm_id)?.name ?? '—'}</td>
                      <td>{f.identifier}</td>
                      <td>{f.area_quantity}</td>
                      <td>{formatAreaUnit(f.area_unit)}</td>
                      <td>
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
                        <table>
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
                                  <td>{field?.identifier ?? '—'}</td>
                                  <td>{farm?.name ?? '—'}</td>
                                  <td>
                                    {a.assigned_area_quantity} {AREA_UNIT_LABEL[a.assigned_area_unit]}
                                  </td>
                                  <td>
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
            <table>
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
                      <td>{d(a.activity_date)}</td>
                      <td>{formatFieldActivityType(a.activity_type)}</td>
                      <td>{cycle ? `${cycle.crop} · ${cycle.season_reference}` : '—'}</td>
                      <td>{field?.identifier ?? '—'}</td>
                      <td>{a.quantity ? `${a.quantity} ${a.unit ?? ''}`.trim() : '—'}</td>
                      <td>
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
        <Link href={`/projects/${projectId}`}>← العودة إلى مساحة المشروع</Link>
      </p>
    </section>
  );
}

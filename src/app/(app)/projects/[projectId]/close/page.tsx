import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  getAccountingPeriods,
  getCloseRunGates,
  getCloseRunExceptions,
  getCloseRunSnapshots,
  getCloseRuns,
  getCorrectionRequests,
  gateLabelAr,
  gateResultLabelAr,
  type AccountingPeriod,
  type CloseRun,
  type CloseRunException,
  type CloseRunGate,
  type CloseRunSnapshot,
  type CorrectionRequest,
} from '@/features/close/queries';
import { formatMinorUnits } from '@/shared/money';
import {
  ApproveCloseForm,
  ApproveCorrectionForm,
  ApproveExceptionForm,
  ExecuteCorrectionForm,
  PrepareCloseForm,
  ReopenForm,
  RequestCorrectionForm,
  RequestExceptionForm,
} from './forms';

export const dynamic = 'force-dynamic';

function date(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
}
function dateTime(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString('ar-EG') : '—';
}

function snapshotTotals(snapshot: CloseRunSnapshot) {
  const t = snapshot.totals;
  const currency = t.currency ?? 'EGP';
  const lines: Array<[string, string]> = [];
  if (t.cash_minor_units !== undefined) lines.push(['الرصيد النقدي', formatMinorUnits(t.cash_minor_units, currency)]);
  if (t.committed_capital_minor_units !== undefined) lines.push(['رأس المال الملتزم', formatMinorUnits(t.committed_capital_minor_units, currency)]);
  if (t.called_minor_units !== undefined) lines.push(['المطلوب', formatMinorUnits(t.called_minor_units, currency)]);
  if (t.contributed_minor_units !== undefined) lines.push(['المساهم', formatMinorUnits(t.contributed_minor_units, currency)]);
  if (t.recognized_revenue_minor_units !== undefined) lines.push(['إيراد البيع المعترف به', formatMinorUnits(t.recognized_revenue_minor_units, currency)]);
  if (t.carrying_cost_derecognized_minor_units !== undefined) lines.push(['تكلفة دفترية مُلغاة', formatMinorUnits(t.carrying_cost_derecognized_minor_units, currency)]);
  if (t.selling_costs_minor_units !== undefined) lines.push(['تكاليف بيع مرحلة', formatMinorUnits(t.selling_costs_minor_units, currency)]);
  if (t.realized_result_minor_units !== undefined) lines.push(['النتيجة المحققة', formatMinorUnits(t.realized_result_minor_units, currency)]);
  if (t.collected_cash_minor_units !== undefined) lines.push(['المحصل نقدًا', formatMinorUnits(t.collected_cash_minor_units, currency)]);
  if (t.outstanding_receivable_minor_units !== undefined) lines.push(['ذمم مدينة متبقية', formatMinorUnits(t.outstanding_receivable_minor_units, currency)]);
  return lines;
}

export default async function ClosePage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, periods, runs, snapshots, corrections] = await Promise.all([
    getCurrentMembership(organizationId),
    getAccountingPeriods(projectId),
    getCloseRuns(projectId),
    getCloseRunSnapshots(projectId),
    getCorrectionRequests(projectId),
  ]);
  if (!membership) {
    return (
      <section className="card">
        <h1>غير مصرح</h1>
        <p className="error">عضويتك الحالية لا تسمح بقراءة الإغلاق المالي لهذا المشروع.</p>
        <Link className="button" href={`/projects/${projectId}`}>العودة للمشروع</Link>
      </section>
    );
  }
  const isOwner = membership.role === 'OWNER';

  // Group runs by period and load their gates/exceptions on demand.
  const runsByPeriod = new Map<string, CloseRun[]>();
  for (const run of runs) {
    const list = runsByPeriod.get(run.period_id) ?? [];
    list.push(run);
    runsByPeriod.set(run.period_id, list);
  }
  const gateLists = new Map<string, CloseRunGate[]>();
  const exceptionLists = new Map<string, CloseRunException[]>();
  for (const run of runs) {
    gateLists.set(run.close_run_id, await getCloseRunGates(run.close_run_id));
    exceptionLists.set(run.close_run_id, await getCloseRunExceptions(run.close_run_id));
  }

  const openPeriods = periods.filter((p) => p.status === 'OPEN');
  const closedPeriods = periods.filter((p) => p.status === 'CLOSED');

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← مساحة المشروع</Link>
          <h1>الإغلاق المالي والتصحيح</h1>
          <p className="muted">{project.name} · {project.reporting_currency}</p>
        </div>
        <nav className="context-nav" aria-label="تنقل الإغلاق">
          <a href="#periods">الفترات</a>
          <a href="#close">الإغلاق</a>
          <a href="#snapshots">اللقطات</a>
          <a href="#corrections">التصحيح</a>
        </nav>
      </header>

      <section id="periods" className="card stack scroll-target">
        <h2>الفترات المحاسبية</h2>
        {periods.length === 0 && (
          <p className="muted">لا توجد فترات محاسبية بعد. أنشئ فترة OPEN لتبدأ.</p>
        )}
        {openPeriods.length > 0 && (
          <div className="stack">
            <h3>فترات مفتوحة</h3>
            {openPeriods.map((period) => (
              <PeriodCard
                key={period.period_id}
                period={period}
                isOwner={isOwner}
                runs={runsByPeriod.get(period.period_id) ?? []}
                gates={gateLists}
                exceptions={exceptionLists}
              />
            ))}
          </div>
        )}
        {closedPeriods.length > 0 && (
          <div className="stack">
            <h3>فترات مغلقة</h3>
            {closedPeriods.map((period) => (
              <ClosedPeriodCard
                key={period.period_id}
                period={period}
                isOwner={isOwner}
                runs={runsByPeriod.get(period.period_id) ?? []}
                gates={gateLists}
                exceptions={exceptionLists}
              />
            ))}
          </div>
        )}
        <details>
          <summary>إنشاء فترة محاسبية جديدة (OWNER فقط)</summary>
          <form action={async () => { 'use server'; }} className="stack">
            <p className="muted">إنشاء فترة جديدة يتم من خلال أمر خادم مخصص. راجع `s6_create_accounting_period` أو استخدم نموذج التحضير أدناه على فترة موجودة.</p>
          </form>
        </details>
      </section>

      <section id="snapshots" className="card stack scroll-target">
        <h2>اللقطات المجمدة</h2>
        {snapshots.length === 0 && (
          <p className="muted">لا توجد لقطات معتمدة بعد.</p>
        )}
        {snapshots.map((snapshot) => (
          <article key={snapshot.snapshot_id} className="card stack">
            <div className="topline">
              <div>
                <h3>إصدار الإغلاق {snapshot.close_version}</h3>
                <p className="muted">محتوى مجمد · {dateTime(snapshot.captured_at)}</p>
                <p><strong>التوقيع:</strong> <code>{snapshot.content_hash.slice(0, 16)}…</code></p>
              </div>
              <span className="status">غير قابل للتعديل</span>
            </div>
            <dl className="facts">
              <div><dt>اعتمد بواسطة</dt><dd>{snapshot.approved_by ?? '—'}</dd></div>
              <div><dt>تاريخ الاعتماد</dt><dd>{dateTime(snapshot.approved_at)}</dd></div>
              <div><dt>تاريخ القطع</dt><dd>{date(snapshot.source_cutoff_date)}</dd></div>
            </dl>
            <table>
              <thead><tr><th>البند</th><th>القيمة</th></tr></thead>
              <tbody>
                {snapshotTotals(snapshot).map(([label, value]) => (
                  <tr key={label}><td>{label}</td><td>{value}</td></tr>
                ))}
              </tbody>
            </table>
          </article>
        ))}
      </section>

      <section id="corrections" className="card stack scroll-target">
        <h2>طلبات التصحيح</h2>
        {corrections.length === 0 && (
          <p className="muted">لا توجد طلبات تصحيح.</p>
        )}
        {corrections.map((correction) => (
          <CorrectionCard
            key={correction.correction_id}
            correction={correction}
            periods={periods}
            isOwner={isOwner}
          />
        ))}
      </section>
    </section>
  );
}

function PeriodCard({
  period, isOwner, runs, gates, exceptions,
}: {
  period: AccountingPeriod; isOwner: boolean;
  runs: CloseRun[]; gates: Map<string, CloseRunGate[]>; exceptions: Map<string, CloseRunException[]>;
}) {
  const prepared = runs.find((r) => r.status === 'PREPARED');
  const approved = runs.find((r) => r.status === 'APPROVED');
  const organizationId = period.organization_id;
  const projectId = period.project_id;
  return (
    <article className="card stack">
      <div className="topline">
        <div>
          <h3>الفترة {period.version}</h3>
          <p className="muted">{date(period.start_date)} → {date(period.end_date)} · {period.reporting_currency}</p>
          {period.supersedes_period_id && (
            <p className="muted">تعيد فتح الفترة {period.supersedes_period_id.slice(0, 8)}…</p>
          )}
        </div>
        <span className="status">مفتوحة</span>
      </div>
      {!prepared && !approved && (
        <PrepareCloseForm
          organizationId={organizationId}
          projectId={projectId}
          periodId={period.period_id}
          disabled={!isOwner}
        />
      )}
      {prepared && (
        <PreparedRunCard
          run={prepared}
          gates={gates.get(prepared.close_run_id) ?? []}
          exceptions={exceptions.get(prepared.close_run_id) ?? []}
          organizationId={organizationId}
          projectId={projectId}
          isOwner={isOwner}
        />
      )}
      {approved && (
        <p className="muted">أُغلقت هذه الفترة بإصدار {approved.version} في {dateTime(approved.approved_at)}.</p>
      )}
    </article>
  );
}

function ClosedPeriodCard({
  period, isOwner, runs, gates, exceptions,
}: {
  period: AccountingPeriod; isOwner: boolean;
  runs: CloseRun[]; gates: Map<string, CloseRunGate[]>; exceptions: Map<string, CloseRunException[]>;
}) {
  const approved = runs.find((r) => r.status === 'APPROVED');
  const organizationId = period.organization_id;
  const projectId = period.project_id;
  return (
    <article className="card stack">
      <div className="topline">
        <div>
          <h3>الفترة {period.version}</h3>
          <p className="muted">{date(period.start_date)} → {date(period.end_date)} · {period.reporting_currency}</p>
        </div>
        <span className="status">مغلقة</span>
      </div>
      {approved && (
        <p>
          <strong>أُغلقت بواسطة:</strong> {approved.approved_by ?? '—'} ·{' '}
          <strong>التاريخ:</strong> {dateTime(approved.approved_at)} ·{' '}
          <strong>الإصدار:</strong> {approved.version} ·{' '}
          <strong>التوقيع:</strong> <code>{approved.snapshot_content_hash?.slice(0, 16) ?? '—'}…</code>
        </p>
      )}
      {isOwner && (
        <details>
          <summary>إعادة فتح كنسخة جديدة</summary>
          <ReopenForm
            organizationId={organizationId}
            projectId={projectId}
            periodId={period.period_id}
          />
        </details>
      )}
    </article>
  );
}

function PreparedRunCard({
  run, gates, exceptions, organizationId, projectId, isOwner,
}: {
  run: CloseRun; gates: CloseRunGate[]; exceptions: CloseRunException[];
  organizationId: string; projectId: string; isOwner: boolean;
}) {
  const failing = gates.filter((g) => g.result === 'FAIL');
  const canApprove = failing.length === 0;
  return (
    <div className="stack">
      <p>
        <strong>إصدار الإغلاق:</strong> {run.version} ·{' '}
        <strong>تاريخ القطع:</strong> {date(run.source_cutoff_date)} ·{' '}
        <strong>بوابات:</strong> {run.passing_gates} اجتياز / {run.failing_gates} فشل / {run.exception_gates} استثناء معتمد / {run.not_applicable_gates} لا ينطبق
      </p>
      <table>
        <thead><tr><th>البوابة</th><th>النتيجة</th><th>التفاصيل</th><th>إجراء</th></tr></thead>
        <tbody>
          {gates.map((gate) => (
            <tr key={gate.gate_id}>
              <td>{gateLabelAr(gate.gate_code)}</td>
              <td><span className="status">{gateResultLabelAr(gate.result)}</span></td>
              <td>{gate.detail}</td>
              <td>
                {gate.result === 'FAIL' && isOwner && (
                  <RequestExceptionForm
                    organizationId={organizationId}
                    projectId={projectId}
                    closeRunId={run.close_run_id}
                    gateCode={gate.gate_code}
                  />
                )}
                {gate.result === 'APPROVED_EXCEPTION' && gate.exception_id && isOwner && (
                  <ApproveExceptionForm
                    organizationId={organizationId}
                    projectId={projectId}
                    exceptionId={gate.exception_id}
                  />
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {exceptions.length > 0 && (
        <details>
          <summary>الاستثناءات ({exceptions.length})</summary>
          <ul>
            {exceptions.map((exc) => (
              <li key={exc.exception_id}>
                <strong>{gateLabelAr(exc.gate_code)}</strong>: {exc.reason} ({exc.status}) — مرجع: {exc.evidence_reference}
              </li>
            ))}
          </ul>
        </details>
      )}
      {canApprove && isOwner && (
        <ApproveCloseForm
          organizationId={organizationId}
          projectId={projectId}
          closeRunId={run.close_run_id}
        />
      )}
      {!canApprove && (
        <p className="muted">لا يمكن الاعتماد حتى يتم اعتماد استثناء لكل بوابة فاشلة.</p>
      )}
    </div>
  );
}

function CorrectionCard({
  correction, periods, isOwner,
}: { correction: CorrectionRequest; periods: AccountingPeriod[]; isOwner: boolean }) {
  const source = periods.find((p) => p.period_id === correction.source_period_id);
  const target = periods.find((p) => p.period_id === correction.correction_period_id);
  return (
    <article className="card stack">
      <div className="topline">
        <div>
          <h3>طلب تصحيح {correction.correction_id.slice(0, 8)}…</h3>
          <p className="muted">دفعة: {correction.target_batch_id.slice(0, 8)}… · نوع: {correction.target_source_type} · تاريخ: {date(correction.target_transaction_date)}</p>
          <p><strong>السبب:</strong> {correction.reason}</p>
          <p><strong>الدليل:</strong> {correction.evidence_reference}</p>
        </div>
        <span className="status">{correction.status}</span>
      </div>
      <dl className="facts">
        <div><dt>الفترة المصدر</dt><dd>إصدار {source?.version ?? '—'} ({source?.status ?? '—'})</dd></div>
        <div><dt>فترة التصحيح</dt><dd>إصدار {target?.version ?? '—'} ({target?.status ?? '—'})</dd></div>
        <div><dt>طلب بواسطة</dt><dd>{correction.requested_by}</dd></div>
        <div><dt>تاريخ الطلب</dt><dd>{dateTime(correction.requested_at)}</dd></div>
        {correction.reviewed_by && <div><dt>راجع بواسطة</dt><dd>{correction.reviewed_by}</dd></div>}
        {correction.reviewed_at && <div><dt>تاريخ المراجعة</dt><dd>{dateTime(correction.reviewed_at)}</dd></div>}
        {correction.reversal_batch_id && (
          <div><dt>دفعة العكس</dt><dd><code>{correction.reversal_batch_id.slice(0, 8)}…</code></dd></div>
        )}
      </dl>
      {correction.status === 'REQUESTED' && isOwner && (
        <ApproveCorrectionForm
          organizationId={correction.organization_id}
          projectId={correction.project_id}
          correctionRequestId={correction.correction_id}
        />
      )}
      {correction.status === 'APPROVED' && isOwner && target && (
        <ExecuteCorrectionForm
          organizationId={correction.organization_id}
          projectId={correction.project_id}
          correctionRequestId={correction.correction_id}
        />
      )}
    </article>
  );
}

import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getCashAccountPositions } from '@/features/finance/queries';
import { getActiveVersion, getCommitments, getParticipants } from '@/features/funding/queries';
import { getAccountingPeriods, getCloseRunSnapshots } from '@/features/close/queries';
import {
  getAllocationLines,
  getAllocationRuleSets,
  getAllocationRuns,
  getDistributionCapacity,
  getDistributions,
  getPartnerCapitalStatement,
} from '@/features/allocation/queries';
import { formatMinorUnits } from '@/shared/money';
import {
  ApproveAllocationForm,
  ApproveDistributionForm,
  ConfigureRulesForm,
  PayDistributionForm,
  PrepareAllocationForm,
  PrepareDistributionForm,
} from './forms';

export const dynamic = 'force-dynamic';

function dt(value: string | null | undefined) {
  return value ? new Date(value).toLocaleString('ar-EG') : '—';
}

function d(value: string | null | undefined) {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
}

function statusAr(value: string) {
  const map: Record<string, string> = {
    PREPARED: 'مُحضّر', APPROVED: 'معتمد', PARTIALLY_PAID: 'مدفوع جزئيًا', PAID: 'مدفوع',
  };
  return map[value] ?? value;
}

export default async function InvestorsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, activeVersion, participants, snapshots, periods, ruleSets, runs, distributions, capacity, statement, cashAccounts] = await Promise.all([
    getCurrentMembership(organizationId),
    getActiveVersion(projectId),
    getParticipants(projectId),
    getCloseRunSnapshots(projectId),
    getAccountingPeriods(projectId),
    getAllocationRuleSets(projectId),
    getAllocationRuns(projectId),
    getDistributions(projectId),
    getDistributionCapacity(projectId),
    getPartnerCapitalStatement(projectId),
    getCashAccountPositions(projectId),
  ]);

  if (!membership) {
    return <section className="card"><h1>غير مصرح</h1><p className="error">عضويتك لا تسمح بقراءة بيانات المستثمرين والتوزيعات لهذا المشروع.</p><Link className="button" href={`/projects/${projectId}`}>العودة للمشروع</Link></section>;
  }

  const isOwner = membership.role === 'OWNER';
  const commitments = activeVersion ? await getCommitments(activeVersion.id) : [];
  const commitmentByParticipant = new Map(commitments.map((row) => [row.participant_id, row]));
  const ruleParticipants = participants.flatMap((participant) => {
    const commitment = commitmentByParticipant.get(participant.id);
    return commitment ? [{
      partyId: participant.party_id,
      legalName: participant.parties.legal_name,
      commitmentMinorUnits: commitment.commitment_minor_units,
    }] : [];
  });
  const commonDenominator = ruleParticipants.reduce((total, row) => total + BigInt(row.commitmentMinorUnits), 0n).toString();
  const activeRuleSet = activeVersion ? ruleSets.find((row) => row.governing_version_id === activeVersion.id) ?? null : null;
  const approvedSnapshots = snapshots.filter((snapshot) => snapshot.close_status === 'APPROVED');
  const runLines = await getAllocationLines(runs.map((run) => run.allocation_run_id));
  const linesByRun = new Map<string, typeof runLines>();
  for (const line of runLines) {
    const rows = linesByRun.get(line.run_id) ?? [];
    rows.push(line);
    linesByRun.set(line.run_id, rows);
  }
  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const postingDate = openPeriod?.start_date ?? '';
  const approvedRuns = runs.filter((run) => run.status === 'APPROVED' && !run.is_reversed);
  const latestApprovedRun = approvedRuns[0] ?? null;
  const distributable = capacity?.distributable_cash_minor_units ?? '0';

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← مساحة المشروع</Link>
          <h1>المستثمرون والتخصيص والتوزيعات</h1>
          <p className="muted">{project.name} · {project.reporting_currency}</p>
        </div>
        <nav className="context-nav" aria-label="تنقل المستثمرين">
          <a href="#rules">القواعد</a><a href="#allocation">التخصيص</a><a href="#capacity">النقدية</a><a href="#distributions">التوزيعات</a><a href="#statement">رأس المال</a>
        </nav>
      </header>

      <section id="rules" className="card stack scroll-target">
        <div><h2>قواعد التخصيص الحاكمة</h2><p className="muted">القواعد ترتبط بنسخة الاتفاقية الحاكمة وتُثبت مرة واحدة. تغيير الاقتصاديات يتطلب نسخة اتفاقية جديدة، لا تعديل التاريخ.</p></div>
        {!activeVersion && <p className="error">لا توجد نسخة اتفاقية ACTIVE. فعّل النسخة الحاكمة من الشروط والتمويل أولًا.</p>}
        {activeVersion && activeRuleSet && (
          <div className="summary-grid">
            <article><span className="muted">نسخة الاتفاقية</span><strong>v{activeVersion.version_no}</strong></article>
            <article><span className="muted">السياسة</span><strong>{activeRuleSet.policy === 'PRO_RATA' ? 'Pro Rata' : 'حصص ثابتة'}</strong></article>
            <article><span className="muted">المستثمرون</span><strong>{activeRuleSet.participant_count}</strong></article>
            <article><span className="muted">بصمة القاعدة</span><code>{activeRuleSet.content_hash.slice(0, 12)}…</code></article>
          </div>
        )}
        {activeVersion && !activeRuleSet && (
          <ConfigureRulesForm organizationId={organizationId} projectId={projectId} governingVersionId={activeVersion.id}
            participants={ruleParticipants} commonDenominator={commonDenominator} currency={project.reporting_currency} disabled={!isOwner} />
        )}
        {!isOwner && <p className="muted">تثبيت القواعد والاعتمادات المالية متاح لمالك المنظمة فقط.</p>}
      </section>

      <section id="allocation" className="card stack scroll-target">
        <div><h2>تخصيص النتيجة المحققة</h2><p className="muted">المبلغ لا يُكتب يدويًا. PostgreSQL يشتقه من الـledger كما كان لحظة لقطة S6 المعتمدة، ثم يوزعه بـlargest remainder دون كسور مالية.</p></div>
        {approvedSnapshots.length === 0 && <p className="muted">لا توجد لقطة إغلاق S6 معتمدة جاهزة للتخصيص.</p>}
        {activeVersion && activeRuleSet && approvedSnapshots.map((snapshot) => {
          const existing = runs.find((run) => run.close_snapshot_id === snapshot.snapshot_id);
          return (
            <article className="subcard stack" key={snapshot.snapshot_id}>
              <div className="split"><div><strong>لقطة الفترة {snapshot.period_id.slice(0, 8)}…</strong><p className="muted">التقطت {dt(snapshot.captured_at)} · hash {snapshot.content_hash.slice(0, 12)}…</p></div>
                {!existing && <PrepareAllocationForm organizationId={organizationId} projectId={projectId} snapshotId={snapshot.snapshot_id} governingVersionId={activeVersion.id} disabled={!isOwner} />}
              </div>
              {existing && <p>الحالة: <strong>{statusAr(existing.status)}</strong> · المصدر {formatMinorUnits(existing.source_amount_minor_units, existing.reporting_currency)}</p>}
            </article>
          );
        })}

        {runs.map((run) => {
          const lines = linesByRun.get(run.allocation_run_id) ?? [];
          return (
            <article className="subcard stack" key={run.allocation_run_id}>
              <div className="split"><div><h3>{statusAr(run.status)} · {formatMinorUnits(run.source_amount_minor_units, run.reporting_currency)}</h3><p className="muted">Snapshot {run.snapshot_content_hash.slice(0, 12)}… · {run.algorithm_version} · أُعد {dt(run.prepared_at)}</p></div>
                {run.status === 'PREPARED' && <ApproveAllocationForm organizationId={organizationId} projectId={projectId} allocationRunId={run.allocation_run_id} postingDate={postingDate} disabled={!isOwner || !openPeriod} />}
              </div>
              <div className="table-wrap"><table><thead><tr><th>المستثمر</th><th>الوزن</th><th>الحصة</th><th>التقريب</th></tr></thead><tbody>
                {lines.map((line) => <tr key={line.allocation_line_id}><td>{line.legal_name}</td><td>{line.weight_numerator}/{line.weight_denominator}</td><td>{formatMinorUnits(line.allocated_minor_units, line.currency)}</td><td>{line.rounding_award_minor_units ? '+1 minor unit' : '—'}</td></tr>)}
              </tbody></table></div>
              {run.status === 'APPROVED' && lines.filter((line) => BigInt(line.allocated_minor_units) > 0n).map((line) => (
                <PrepareDistributionForm key={`dist-${line.allocation_line_id}`} organizationId={organizationId} projectId={projectId} allocationRunId={run.allocation_run_id} participantPartyId={line.participant_party_id} currency={line.currency} legalName={line.legal_name} disabled={!isOwner} />
              ))}
            </article>
          );
        })}
      </section>

      <section id="capacity" className="card stack scroll-target">
        <div><h2>جسر النقدية القابلة للتوزيع</h2><p className="muted">التوزيع لا يعتمد على رصيد dashboard. السقف الحالي محافظ: النقدية − الموردين المستحقين − التوزيعات المستحقة القائمة.</p></div>
        {capacity ? <div className="summary-grid">
          <article><span className="muted">النقدية</span><strong>{formatMinorUnits(capacity.cash_minor_units, capacity.currency)}</strong></article>
          <article><span className="muted">موردون مستحقون</span><strong>{formatMinorUnits(capacity.supplier_payable_minor_units, capacity.currency)}</strong></article>
          <article><span className="muted">توزيعات مستحقة</span><strong>{formatMinorUnits(capacity.distribution_payable_minor_units, capacity.currency)}</strong></article>
          <article><span className="muted">نقدية قابلة للتوزيع</span><strong>{formatMinorUnits(distributable, capacity.currency)}</strong></article>
        </div> : <p className="muted">لا توجد حركة مالية تكفي لبناء الجسر حتى الآن.</p>}
      </section>

      <section id="distributions" className="card stack scroll-target">
        <div><h2>التوزيعات المستحقة والدفع</h2><p className="muted">الاعتماد يُنشئ Distribution Payable أولًا. الدفع خطوة مستقلة لاحقة تُخفض المستحق والنقدية.</p></div>
        {distributions.length === 0 && <p className="muted">لا توجد توزيعات محضرة بعد.</p>}
        {distributions.map((distribution) => (
          <article className="subcard stack" key={distribution.distribution_id}>
            <div className="split"><div><h3>{distribution.legal_name} · {formatMinorUnits(distribution.requested_amount_minor_units, distribution.currency)}</h3><p className="muted">{statusAr(distribution.settlement_status)} · دليل: {distribution.evidence_reference}</p></div><strong>متبقي {formatMinorUnits(distribution.outstanding_minor_units, distribution.currency)}</strong></div>
            {distribution.status === 'PREPARED' && <ApproveDistributionForm organizationId={organizationId} projectId={projectId} distributionId={distribution.distribution_id} postingDate={postingDate} disabled={!isOwner || !openPeriod} />}
            {distribution.status === 'APPROVED' && BigInt(distribution.outstanding_minor_units) > 0n && <PayDistributionForm organizationId={organizationId} projectId={projectId} distributionId={distribution.distribution_id} currency={distribution.currency} outstandingMajorHint="0.00" postingDate={postingDate} cashAccounts={cashAccounts} disabled={!isOwner || !openPeriod} />}
            <p className="muted">اعتمد: {d(distribution.approval_posting_date)} · مدفوع: {formatMinorUnits(distribution.paid_minor_units, distribution.currency)}</p>
          </article>
        ))}
      </section>

      <section id="statement" className="card stack scroll-target">
        <div><h2>كشف رأس مال المستثمرين</h2><p className="muted">Opening + Contributions + Allocated Income − Allocated Loss − Approved Distributions = Closing. المدفوع ظاهر منفصلًا عن الاعتماد.</p></div>
        {statement.length === 0 ? <p className="muted">لا توجد حركة رأس مال قابلة للعرض بعد.</p> : <div className="table-wrap"><table><thead><tr><th>المستثمر</th><th>مساهمات</th><th>دخل مخصص</th><th>خسارة مخصصة</th><th>توزيعات معتمدة</th><th>مدفوع</th><th>إقفال رأس المال</th></tr></thead><tbody>
          {statement.map((row) => <tr key={row.participant_party_id}><td>{row.legal_name}</td><td>{formatMinorUnits(row.contributions_minor_units,row.currency)}</td><td>{formatMinorUnits(row.allocated_income_minor_units,row.currency)}</td><td>{formatMinorUnits(row.allocated_loss_minor_units,row.currency)}</td><td>{formatMinorUnits(row.approved_distributions_minor_units,row.currency)}</td><td>{formatMinorUnits(row.paid_distributions_minor_units,row.currency)}</td><td><strong>{formatMinorUnits(row.closing_capital_minor_units,row.currency)}</strong></td></tr>)}
        </tbody></table></div>}
      </section>

      {!openPeriod && latestApprovedRun && <section className="card"><p className="error">لا توجد فترة محاسبية OPEN. يمكنك قراءة التاريخ، لكن أي اعتماد أو دفع جديد متوقف حتى فتح فترة صحيحة.</p></section>}
    </section>
  );
}

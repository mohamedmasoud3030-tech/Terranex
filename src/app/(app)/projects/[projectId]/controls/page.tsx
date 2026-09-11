import { ROLE_LABEL, recordStatusLabel, roleLabel } from '@/features/projects/labels';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  getMembershipAccess,
  getPilotAcceptanceReport,
  getReconciliationCheckpoints,
} from '@/features/pilot/queries';
import { WorkspaceChrome, ForbiddenCard, memberDisplayLabel } from '@/features/workspace/chrome';

export const dynamic = 'force-dynamic';

const UAT_AR: Record<string, string> = {
  NOT_STARTED: 'لم يبدأ',
  PENDING: 'قيد التنفيذ — لم يُقبل بعد',
  ACCEPTED: 'مقبول بدليل بشري',
  REJECTED: 'مرفوض',
};

function Gate({
  label,
  satisfied,
  note,
}: {
  label: string;
  satisfied: boolean;
  note?: string;
}) {
  return (
    <div className={`gate ${satisfied ? 'pass satisfied-row' : 'fail not-row'}`}>
      <div>
        <strong>{label}</strong>
        {note ? <div className="muted hint-sm">{note}</div> : null}
      </div>
      <div className="flex-center-xs">
        <span>{satisfied ? 'محقق' : 'غير محقق'}</span>
        <span className={satisfied ? 'gate-dot satisfied' : 'gate-dot not'} aria-hidden />
      </div>
    </div>
  );
}

export default async function ControlsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, report, checkpoints, members] = await Promise.all([
    getCurrentMembership(organizationId),
    getPilotAcceptanceReport(projectId),
    getReconciliationCheckpoints(projectId),
    getMembershipAccess(organizationId),
  ]);

  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="عضويتك الحالية لا تسمح بقراءة لوحة الرقابة والجاهزية لهذا المشروع." />;
  }

  const isOwner = membership.role === 'OWNER';
  const signedCheckpoints = checkpoints.filter((checkpoint) => checkpoint.status === 'SIGNED_OFF').length;
  const zeroVarianceSigned = checkpoints.filter(
    (checkpoint) => checkpoint.status === 'SIGNED_OFF' && checkpoint.is_zero_variance,
  ).length;
  const financialIntegrityOk = (report?.unbalanced_journal_batches ?? 0) === 0;

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="controls"
        title="الرقابة والجاهزية"
        subtitle={`${project.name} · ${project.reporting_currency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
        lifecycleState={project.lifecycle_state}
      />

      <section className="card stack" aria-labelledby="controls-s1">
        <h2 id="controls-s1">دوري في المشروع</h2>
        <p>
          <span className={isOwner ? 'role-badge owner' : 'role-badge'}>
            {isOwner ? 'مالك المنظمة (OWNER)' : 'عضو (MEMBER)'}
          </span>
        </p>
        <p className="muted">
          {isOwner
            ? 'أنت مالك المنظمة: يمكنك تنفيذ الموافقات الحصرية للمالك (اعتماد الفترات، استيراد مفتوح، استثناءات مطابقة، إلغاء وصول). تبقى آليات التخصيص والتوزيع محجوبة حتى تُعتمد سياسة الشركة المستهدفة.'
            : 'أنت عضو: يمكنك تنفيذ الإجراءات التشغيلية العادية، لكن لا يمكنك تنفيذ الموافقات الحصرية للمالك. العزل بين المنظمات محفوظ عبر أذونات الصفوف.'}
        </p>
      </section>

      <section className="card stack" aria-labelledby="controls-s2">
        <h2 id="controls-s2">الجاهزية التقنية</h2>
        <p className="muted">
          تُشتق من وقائع مسجّلة داخل قاعدة البيانات عبر قراءات رسمية. نجاح هذه البوابات لا يعني أبدًا قبولًا بشريًا.
        </p>
        <div className="panel-grid">
          <div className="panel">
            <h3>السلامة المالية</h3>
            <Gate label="قيود متوازنة" satisfied={financialIntegrityOk} note={`قيود غير متوازنة: ${report?.unbalanced_journal_batches ?? 0}`} />
            <Gate label="سطور بنكية مطابقة" satisfied={(report?.unreconciled_bank_statement_lines ?? 0) === 0} note={`غير مطابقة: ${report?.unreconciled_bank_statement_lines ?? 0}`} />
          </div>
          <div className="panel">
            <h3>قدرة الاستيراد والمطابقة</h3>
            <Gate label="استيراد افتتاحي مُرحَّل" satisfied={(report?.posted_opening_imports ?? 0) > 0} note={`استيرادات مرحلة: ${report?.posted_opening_imports ?? 0}`} />
            <Gate label="مجاميع رقابة مطابقة" satisfied={report?.opening_control_totals_match === true} note={report?.opening_control_totals_match == null ? 'لم تُسجَّل' : report.opening_control_totals_match ? 'مطابقة' : 'غير مطابقة'} />
            <Gate label="مطابقة صفرية الفروق" satisfied={(report?.reconciliation_non_zero_variances ?? 0) === 0 && signedCheckpoints > 0} note={`${signedCheckpoints} نقطة موقّعة · ${zeroVarianceSigned} صفرية الفرق`} />
            <Gate label="لا استثناءات حرجة مفتوحة" satisfied={(report?.unresolved_critical_exceptions ?? 0) === 0} note={`حرجة: ${report?.unresolved_critical_exceptions ?? 0}`} />
          </div>
          <div className="panel">
            <h3>البروفات الفنية</h3>
            <Gate label="بروفة الدورة الكاملة" satisfied={report?.end_to_end_result === 'PASS'} note={report?.end_to_end_result ?? 'لم تُنفَّذ'} />
            <Gate label="بروفة النسخ والاستعادة" satisfied={report?.backup_restore_result === 'PASS'} note={report?.backup_restore_result ?? 'لم تُنفَّذ'} />
            <Gate label="بروفة إلغاء الوصول" satisfied={report?.access_revocation_result === 'PASS'} note={report?.access_revocation_result ?? 'لم تُنفَّذ'} />
          </div>
        </div>
      </section>

      <section className="card stack" aria-labelledby="controls-s3">
        <h2 id="controls-s3">أدلة العالم الحقيقي</h2>
        <div className="banner" role="note">
          البيانات التجريبية (مثل DEMO-RE-2026-001) بيانات اصطناعية للمعاينة والتدريب والتحقق. لا تُحتسب أبدًا
          كدليل عميل حقيقي ولا تُغلق أي بوابة مرحلَة ثانية أو ثالثة. لا تتحقق هذه البوابات إلا بدليل مصدري حقيقي
          وموقّع من بيانات عميل فعلية.
        </div>
        <p className="muted">
          لا يمكن لقاعدة بيانات واحدة أن تثبت «مصدرية» البيانات؛ هذه البوابات تتطلب دليلًا خارجيًا موقّعًا.
          في هذه المرحلة تبقى جميعها غير محققة للعرض التجريبي — وهو الموقف الصحيح.
        </p>
        <div className="panel-grid">
          <div className="panel">
            <h3>بيانات حقيقية</h3>
            <Gate label="استلام بيانات مصدر حقيقية" satisfied={false} note="بيانات العميل الفعلية غير واردة بعد" />
            <Gate label="مجاميع رقابة موقّعة من المصدر" satisfied={false} note="تتطلب توقيعًا خارجيًا على مجاميع المصدر" />
            <Gate label="استيراد افتتاحي حقيقي" satisfied={false} note="استيراد بيانات عميل حقيقية" />
            <Gate label="مطابقة افتتاحية صفرية الفروق" satisfied={false} note="إعادة إنتاج مجاميع المصدر بلا فروق غير مفسرة" />
          </div>
          <div className="panel">
            <h3>تشغيل وقبول</h3>
            <Gate label="دورة حياة حقيقية في بيئة مرحلَة" satisfied={false} note="تشغيل وقائع عميل فعلية في بيئة تجريبية" />
            <Gate label="قبول بشري (UAT)" satisfied={report?.human_uat_status === 'ACCEPTED'} note={`الحالة: ${UAT_AR[report?.human_uat_status ?? 'NOT_STARTED'] ?? 'لم يبدأ'}`} />
            <Gate label="قبول المشتري" satisfied={false} note="موافقة العميل على نتائج التشغيل التجريبي" />
            <Gate label="أسابيع تشغيل مدفوعة" satisfied={false} note="أسبوع تشغيل تجريبي مدفوع واحد على الأقل" />
          </div>
        </div>
      </section>

      <section className="card stack" aria-labelledby="controls-s4">
        <h2 id="controls-s4">أعضاء المنظمة والوصول</h2>
        {members.length === 0 ? (
          <p className="muted">لا توجد عضوية إضافية معروضة (متاح للمالك).</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: العضو · الدور · الحالة</caption>
              <thead><tr><th scope="col">العضو</th><th scope="col">الدور</th><th scope="col">الحالة</th></tr></thead>
              <tbody>
                {members.map((member) => (
                  <tr key={member.membership_id}>
                    <td data-label="العضو">{member.user_id}</td>
                    <td data-label="الدور">{roleLabel(member.role)}</td>
                    <td data-label="الحالة">{recordStatusLabel(member.status)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">
          إدارة الوصول وإلغاؤه من <Link href={`/projects/${projectId}/pilot`}>الاستيراد والمطابقة → الوصول</Link>.
          رقابة الصفوف (RLS) مفروضة على مستوى المنظمة؛ لا يمكن لأي عضو قراءة سجلات منظمة أخرى.
        </p>
      </section>
    </section>
  );
}

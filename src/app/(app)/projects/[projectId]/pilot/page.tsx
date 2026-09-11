import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCashAccountPositions, getCurrentMembership } from '@/features/finance/queries';
import { getParties } from '@/features/funding/queries';
import { getAccountingPeriods } from '@/features/close/queries';
import {
  getMembershipAccess,
  getOpeningImportRows,
  getOpeningImports,
  getOpeningMappingCodes,
  getPilotAcceptanceReport,
  getPilotRehearsals,
  getReconciliationCheckpoints,
  getReconciliationExceptions,
  getUatTasks,
  type OpeningImport,
  type OpeningImportRow,
} from '@/features/pilot/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceChrome, ForbiddenCard, memberDisplayLabel } from '@/features/workspace/chrome';
import { InPageTabs } from '@/shared/ui';
import {
  AcceptUatTaskForm,
  ApproveOpeningImportForm,
  RecordCheckpointForm,
  RecordUatExecutionForm,
  RegisterUatTaskForm,
  RejectOpeningImportForm,
  RejectUatTaskForm,
  ResolveExceptionForm,
  ReviewOpeningImportForm,
  SetMembershipStatusForm,
  SignOffCheckpointForm,
  StageOpeningImportForm,
  ValidateOpeningImportForm,
} from './forms';

export const dynamic = 'force-dynamic';

function dt(value: string | null | undefined) {
  return value ? new Date(value).toLocaleString('ar-EG') : '—';
}

function d(value: string | null | undefined) {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
}

const IMPORT_STATUS_AR: Record<string, string> = {
  DRAFT: 'مسودة',
  VALIDATED: 'تم التحقق',
  READY_FOR_APPROVAL: 'بانتظار الاعتماد',
  APPROVED: 'معتمد',
  POSTED: 'مُرحَّل',
  REJECTED: 'مرفوض',
  FAILED: 'فشل',
};

const ROW_STATUS_AR: Record<string, string> = { ACCEPTED: 'مقبول', REJECTED: 'مرفوض' };

const REJECT_REASON_AR: Record<string, string> = {
  UNKNOWN_MAPPING_CODE: 'ترميز غير معروف',
  PARTY_REQUIRED: 'الطرف مطلوب',
  PARTY_NOT_ALLOWED: 'الطرف غير مسموح لهذا الترميز',
  INVALID_AMOUNT: 'مبلغ غير صالح',
  BOTH_SIDES_SET: 'مدين ودائن معًا',
  NO_AMOUNT: 'لا يوجد مبلغ',
  PARTY_NOT_IN_ORGANIZATION: 'الطرف خارج المنظمة',
  CASH_ACCOUNT_REQUIRED: 'الحساب النقدي مطلوب',
  CASH_ACCOUNT_OUT_OF_SCOPE: 'الحساب النقدي خارج نطاق المشروع',
  SIDE_CONTRADICTS_MAPPING: 'الاتجاه يخالف طبيعة الترميز',
  DUPLICATE_ROW_IN_FILE: 'سطر مكرر داخل الملف',
  DESCRIPTION_INVALID: 'وصف غير صالح',
};

const CHECKPOINT_AR: Record<string, string> = {
  PROJECT_CASH: 'نقدية المشروع',
  SUPPLIER_OBLIGATION_POSITION: 'مركز التزامات الموردين',
  CUSTOMER_RECEIVABLE_POSITION: 'مركز ذمم العملاء',
  REALIZED_RESULT: 'النتيجة المحققة',
  CONTRIBUTED_CAPITAL: 'رأس المال المساهم به',
  PARTNER_CAPITAL: 'رأس مال الشركاء',
  DISTRIBUTION_PAYABLE: 'توزيعات مستحقة الدفع',
  DISTRIBUTION_PAID: 'توزيعات مدفوعة',
  INVESTOR_STATEMENT_TOTAL: 'إجمالي كشف المستثمرين',
};

const SEVERITY_AR: Record<string, string> = {
  LOW: 'منخفضة', MEDIUM: 'متوسطة', HIGH: 'مرتفعة', CRITICAL: 'حرجة',
};

const UAT_STATUS_AR: Record<string, string> = {
  PENDING: 'بانتظار التنفيذ',
  EXECUTED: 'نُفِّذت — بانتظار قبول العميل',
  ACCEPTED: 'مقبولة من العميل',
  REJECTED: 'مرفوضة من العميل',
};

const HUMAN_UAT_AR: Record<string, string> = {
  NOT_STARTED: 'لم يبدأ',
  PENDING: 'قيد التنفيذ — لم يُقبل بعد',
  ACCEPTED: 'مقبول بدليل بشري',
  REJECTED: 'مرفوض',
};

const REHEARSAL_AR: Record<string, string> = {
  END_TO_END_CYCLE: 'بروفة الدورة الكاملة',
  BACKUP_RESTORE: 'بروفة النسخ والاستعادة',
  ACCESS_REVOCATION: 'بروفة إلغاء الوصول',
};

const ROW_FILTERS = ['all', 'rejected', 'accepted'] as const;
type RowFilter = (typeof ROW_FILTERS)[number];

const ROW_FILTER_AR: Record<RowFilter, string> = {
  all: 'كل السطور', rejected: 'المرفوضة فقط', accepted: 'المقبولة فقط',
};

function isTerminal(status: OpeningImport['status']) {
  return status === 'POSTED' || status === 'REJECTED' || status === 'FAILED';
}

/**
 * Approval readiness is re-derived by PostgreSQL on every command — including
 * the maker/checker rule, which the browser cannot be trusted to evaluate. The
 * page only decides whether it is honest to offer the button at all.
 */
function canOfferApproval(row: OpeningImport) {
  return row.status === 'READY_FOR_APPROVAL' && row.control_totals_match && row.rejected_row_count === 0;
}

export default async function PilotPage({
  params, searchParams,
}: {
  params: Promise<{ projectId: string }>;
  searchParams: Promise<{ rows?: string }>;
}) {
  const { projectId } = await params;
  const { rows: rowsParam } = await searchParams;
  const rowFilter: RowFilter = ROW_FILTERS.includes(rowsParam as RowFilter) ? (rowsParam as RowFilter) : 'all';

  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, imports, mappingCodes, checkpoints, exceptions, uatTasks, rehearsals, report, parties, cashAccounts, periods] =
    await Promise.all([
      getCurrentMembership(organizationId),
      getOpeningImports(projectId),
      getOpeningMappingCodes(),
      getReconciliationCheckpoints(projectId),
      getReconciliationExceptions(projectId),
      getUatTasks(projectId),
      getPilotRehearsals(projectId),
      getPilotAcceptanceReport(projectId),
      getParties(organizationId),
      getCashAccountPositions(projectId),
      getAccountingPeriods(projectId),
    ]);

  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="عضويتك لا تسمح بقراءة لوحة التشغيل التجريبي لهذا المشروع. قد تكون عضويتك أُلغيت." />;
  }

  const isOwner = membership.role === 'OWNER';
  const members = isOwner ? await getMembershipAccess(organizationId) : [];
  const currency = project.reporting_currency;
  const money = (value: string | null | undefined) => formatMinorUnits(value ?? '0', currency);

  const activeImport = imports.find((row) => !isTerminal(row.status)) ?? null;
  const allRows: OpeningImportRow[] = await getOpeningImportRows(imports.map((row) => row.import_id));
  const filteredRows = rowFilter === 'all' ? allRows : allRows.filter((row) => row.status === rowFilter.toUpperCase());
  const rejectedRowCount = allRows.filter((row) => row.status === 'REJECTED').length;

  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const defaultPostingDate = openPeriod?.start_date ?? '';
  const today = new Date().toISOString().slice(0, 10);

  const openExceptions = exceptions.filter((row) => row.status === 'OPEN');
  const criticalOpenExceptions = openExceptions.filter((row) => row.severity === 'CRITICAL');
  const pendingApprovals = [
    ...imports.filter((row) => row.status === 'READY_FOR_APPROVAL').map((row) => ({
      kind: 'الاستيراد الافتتاحي', label: row.source_file_name, since: row.reviewed_at ?? row.prepared_at, href: '#import',
    })),
    ...checkpoints.filter((row) => row.status !== 'SIGNED_OFF').map((row) => ({
      kind: 'اعتماد نقطة مطابقة', label: CHECKPOINT_AR[row.checkpoint_code] ?? row.checkpoint_code, since: row.prepared_at, href: '#reconciliation',
    })),
    ...uatTasks.filter((row) => row.status === 'EXECUTED').map((row) => ({
      kind: 'قبول اختبار العميل', label: row.task_code, since: row.executed_at ?? row.created_at, href: '#uat',
    })),
  ];

  const checkpointOptions = Object.entries(CHECKPOINT_AR).map(([code, label]) => ({ code, label }));
  const mappingOptions = mappingCodes.map((mapping) => ({
    code: mapping.code,
    label: mapping.label_ar,
    naturalSide: mapping.natural_side,
    requiresParty: mapping.requires_party,
    requiresCashAccount: mapping.requires_cash_account,
  }));

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="opening"
        title="الاستيراد والمطابقة"
        subtitle={`${project.name} · ${currency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
        lifecycleState={project.lifecycle_state}
      />
      <InPageTabs
        label="تنقل التشغيل التجريبي"
        items={[
          { href: '#readiness', label: 'الجاهزية' },
          { href: '#approvals', label: 'بانتظار الاعتماد' },
          { href: '#import', label: 'الاستيراد الافتتاحي' },
          { href: '#rows', label: 'سطور الملف' },
          { href: '#reconciliation', label: 'المطابقة' },
          { href: '#exceptions', label: 'الاستثناءات' },
          { href: '#uat', label: 'اختبار القبول' },
          { href: '#rehearsals', label: 'البروفات' },
          { href: '#access', label: 'الوصول' },
        ]}
      />

      {criticalOpenExceptions.length > 0 && (
        <p className="error" role="alert">
          يوجد {criticalOpenExceptions.length} استثناء مطابقة حرج غير معالج. لا يُعد المشروع جاهزًا للتشغيل التجريبي قبل إغلاقه.
        </p>
      )}

      <section id="readiness" className="card stack scroll-target">
        <div>
          <h2>تقرير الجاهزية التقنية</h2>
          <p className="muted">
            كل رقم هنا مشتق داخل قاعدة البيانات من وقائع مسجّلة، لا من إدخال يدوي. الجاهزية التقنية وقبول العميل
            حقلان منفصلان تمامًا: نجاح بروفة آلية لا يُترجم أبدًا إلى قبول عميل.
          </p>
        </div>
        {!report ? (
          <p className="empty">لا يوجد تقرير جاهزية بعد. سجّل أول استيراد افتتاحي أو نقطة مطابقة لهذا المشروع.</p>
        ) : (
          <>
            <div className="metric-grid">
              <article className="metric"><span className="muted">استيرادات افتتاحية مُرحَّلة</span><strong>{report.posted_opening_imports}</strong></article>
              <article className="metric"><span className="muted">سطور مرفوضة</span><strong>{report.opening_import_rejected_rows}</strong></article>
              <article className="metric">
                <span className="muted">مجاميع الرقابة</span>
                <strong>{report.opening_control_totals_match === null ? '—' : report.opening_control_totals_match ? 'مطابقة' : 'غير مطابقة'}</strong>
              </article>
              <article className="metric"><span className="muted">نقاط مطابقة</span><strong>{report.reconciliation_checkpoints}</strong></article>
              <article className="metric"><span className="muted">فروق غير صفرية</span><strong>{report.reconciliation_non_zero_variances}</strong></article>
              <article className="metric"><span className="muted">أكبر فرق مطلق</span><strong>{money(report.reconciliation_max_abs_variance_minor_units)}</strong></article>
              <article className="metric"><span className="muted">استثناءات غير معالجة</span><strong>{report.unresolved_exceptions}</strong></article>
              <article className="metric"><span className="muted">منها حرجة</span><strong>{report.unresolved_critical_exceptions}</strong></article>
              <article className="metric"><span className="muted">سطور بنكية غير مطابقة</span><strong>{report.unreconciled_bank_statement_lines}</strong></article>
              <article className="metric"><span className="muted">دفعات قيود غير متوازنة</span><strong>{report.unbalanced_journal_batches}</strong></article>
            </div>
            <div className="metric-grid">
              <article className="metric"><span className="muted">بروفة الدورة الكاملة</span><strong>{report.end_to_end_result ?? 'لم تُنفَّذ'}</strong></article>
              <article className="metric"><span className="muted">بروفة النسخ والاستعادة</span><strong>{report.backup_restore_result ?? 'لم تُنفَّذ'}</strong></article>
              <article className="metric"><span className="muted">بروفة إلغاء الوصول</span><strong>{report.access_revocation_result ?? 'لم تُنفَّذ'}</strong></article>
            </div>
            <div className="result-highlight">
              <span className="muted">قبول العميل البشري</span>
              <strong>{HUMAN_UAT_AR[report.human_uat_status] ?? report.human_uat_status}</strong>
              <p className="muted">
                {report.uat_accepted_tasks} مقبولة · {report.uat_rejected_tasks} مرفوضة · {report.uat_total_tasks} إجمالي المهام.
                هذه الحالة تُشتق من قبول بشري موثق فقط.
              </p>
            </div>
          </>
        )}
      </section>

      <section id="approvals" className="card stack scroll-target">
        <h2>بانتظار الاعتماد</h2>
        {pendingApprovals.length === 0 ? (
          <p className="empty">لا توجد عناصر تنتظر اعتمادًا.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead><tr><th>النوع</th><th>العنصر</th><th>منذ</th><th></th></tr></thead>
              <tbody>
                {pendingApprovals.map((item) => (
                  <tr key={`${item.kind}-${item.label}-${item.since}`}>
                    <td data-label="النوع">{item.kind}</td>
                    <td data-label="العنصر">{item.label}</td>
                    <td data-label="منذ">{dt(item.since)}</td>
                    <td data-label=""><a href={item.href}>انتقال</a></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section id="import" className="card stack scroll-target">
        <div>
          <h2>الاستيراد الافتتاحي المضبوط</h2>
          <p className="muted">
            مسار واحد فقط: مسودة ← تحقق ← ترشيح للاعتماد ← اعتماد وترحيل. مُعِدّ الملف لا يعتمده.
            الترحيل ينتج قيدًا متوازنًا عبر سجل الحسابات الدلالية القائم؛ لا تُكتب أرصدة مباشرة أبدًا،
            والتصحيح بعد الترحيل يكون بالعكس المرتبط لا بالتعديل.
          </p>
        </div>

        {imports.length === 0 ? (
          <p className="empty">لم يُسجَّل أي استيراد افتتاحي لهذا المشروع بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>الملف</th><th>الحالة</th><th>البصمة</th><th>سطور مقبولة/مرفوضة</th>
                  <th>مدين محسوب</th><th>دائن محسوب</th><th>فرق المدين</th><th>فرق الدائن</th>
                  <th>أعدّه</th><th>اعتمده</th><th>تاريخ الترحيل</th><th>القيد</th>
                </tr>
              </thead>
              <tbody>
                {imports.map((row) => (
                  <tr key={row.import_id}>
                    <td data-label="الملف">{row.source_file_name}</td>
                    <td data-label="الحالة">
                      <span className="status">{IMPORT_STATUS_AR[row.status] ?? row.status}</span>
                      {row.is_reversed && <span className="muted"> · معكوس</span>}
                    </td>
                    <td data-label="البصمة"><code>{row.source_file_checksum.slice(0, 12)}…</code></td>
                    <td data-label="سطور مقبولة/مرفوضة">{row.accepted_row_count} / {row.rejected_row_count}</td>
                    <td data-label="مدين محسوب">{money(row.computed_debit_total_minor_units)}</td>
                    <td data-label="دائن محسوب">{money(row.computed_credit_total_minor_units)}</td>
                    <td data-label="فرق المدين" className={BigInt(row.debit_variance_minor_units) === 0n ? undefined : 'error'}>{money(row.debit_variance_minor_units)}</td>
                    <td data-label="فرق الدائن" className={BigInt(row.credit_variance_minor_units) === 0n ? undefined : 'error'}>{money(row.credit_variance_minor_units)}</td>
                    <td data-label="أعدّه">مُعِدّ مسجّل</td>
                    <td data-label="اعتمده">{row.approved_by ? 'مالك معتمد' : '—'}</td>
                    <td data-label="تاريخ الترحيل">{d(row.posting_date)}</td>
                    <td data-label="القيد">{row.journal_batch_id ? <Link href={`/projects/${projectId}/cash`}>عرض المصدر</Link> : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {activeImport && (
          <div className="facts">
            <h3>الاستيراد الجاري: {activeImport.source_file_name}</h3>
            <p className="muted">
              إصدار القالب {activeImport.schema_version} · بصمة المحتوى <code>{activeImport.content_hash.slice(0, 12)}…</code>
              {activeImport.snapshot_content_hash && <> · بصمة اللقطة المعتمدة <code>{activeImport.snapshot_content_hash.slice(0, 12)}…</code></>}
            </p>
            {activeImport.failure_reason && <p className="error" role="alert">{activeImport.failure_reason}</p>}
            {activeImport.rejected_row_count > 0 && (
              <p className="error" role="alert">
                {activeImport.rejected_row_count} سطر مرفوض. لا يمكن الاعتماد قبل تصحيح المصدر وإعادة الاستيراد.
              </p>
            )}
            {!activeImport.control_totals_match && activeImport.status !== 'DRAFT' && (
              <p className="error" role="alert">مجاميع الرقابة المعلنة لا تطابق المحسوب داخل النظام.</p>
            )}
            <ul>
              {Object.entries(activeImport.mapping_summary ?? {}).map(([code, summary]) => (
                <li key={code}>
                  {mappingCodes.find((mapping) => mapping.code === code)?.label_ar ?? code}: {summary.accepted_rows} سطر ·
                  مدين {money(summary.debit_minor_units)} · دائن {money(summary.credit_minor_units)}
                </li>
              ))}
            </ul>
          </div>
        )}

        {!isOwner && <p className="muted">أوامر الاستيراد الافتتاحي متاحة لمالك المنظمة فقط.</p>}

        {isOwner && activeImport?.status === 'DRAFT' && (
          <ValidateOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
        )}
        {isOwner && activeImport?.status === 'VALIDATED' && (
          <ReviewOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
        )}
        {isOwner && activeImport?.status === 'READY_FOR_APPROVAL' && (
          canOfferApproval(activeImport) ? (
            <ApproveOpeningImportForm
              organizationId={organizationId} projectId={projectId}
              importId={activeImport.import_id}
              postingDate={defaultPostingDate || today}
            />
          ) : (
            <p className="error" role="alert">
              لا يمكن الاعتماد قبل خلو الاستيراد من السطور المرفوضة وتطابق مجاميع الرقابة. صحّح المصدر وأعد الاستيراد.
            </p>
          )
        )}
        {isOwner && activeImport && !isTerminal(activeImport.status) && (
          <RejectOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
        )}
        {isOwner && !activeImport && (
          <StageOpeningImportForm
            organizationId={organizationId}
            projectId={projectId}
            mappingCodes={mappingOptions}
            parties={parties.map((party) => ({ id: party.id, legalName: party.legal_name }))}
            cashAccounts={cashAccounts.map((account) => ({ id: account.cash_account_id, name: account.name }))}
          />
        )}
      </section>

      <section id="rows" className="card stack scroll-target">
        <div className="section-heading">
          <h2>سطور الملف ونتيجة كل سطر</h2>
          <p className="muted">{rejectedRowCount} سطر مرفوض من {allRows.length} سطر مُقدَّم.</p>
        </div>
        <nav className="context-nav" aria-label="تصفية السطور">
          {ROW_FILTERS.map((filter) => (
            <Link
              key={filter}
              href={`/projects/${projectId}/pilot?rows=${filter}#rows`}
              aria-current={filter === rowFilter ? 'page' : undefined}
            >
              {ROW_FILTER_AR[filter]}
            </Link>
          ))}
        </nav>
        {allRows.length === 0 ? (
          <p className="empty">لا توجد سطور استيراد بعد.</p>
        ) : filteredRows.length === 0 ? (
          <p className="empty">
            لا توجد سطور مطابقة للتصفية «{ROW_FILTER_AR[rowFilter]}».{' '}
            <Link href={`/projects/${projectId}/pilot?rows=all#rows`}>عرض كل السطور</Link>
          </p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>#</th><th>الترميز</th><th>الطرف</th><th>مدين</th><th>دائن</th><th>الوصف</th><th className="num">النتيجة</th><th>سبب الرفض</th></tr>
              </thead>
              <tbody>
                {filteredRows.map((row) => (
                  <tr key={row.row_id}>
                    <td data-label="#">{row.row_number}</td>
                    <td data-label="الترميز">{row.mapping_label ?? row.mapping_code}</td>
                    <td data-label="الطرف">{row.party_legal_name ?? '—'}</td>
                    <td data-label="مدين">{money(row.debit_minor_units)}</td>
                    <td data-label="دائن">{money(row.credit_minor_units)}</td>
                    <td data-label="الوصف">{row.description}</td>
                    <td className="num" data-label="النتيجة"><span className="status">{ROW_STATUS_AR[row.status] ?? row.status}</span></td>
                    <td data-label="سبب الرفض" className={row.reject_reason ? 'error' : undefined}>
                      {row.reject_reason ? REJECT_REASON_AR[row.reject_reason] ?? row.reject_reason : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section id="reconciliation" className="card stack scroll-target">
        <div>
          <h2>نقاط المطابقة مع الأدلة الخارجية</h2>
          <p className="muted">
            القيمة الخارجية دليل يُسجَّل كما هو؛ القيمة المعتمدة يشتقها PostgreSQL من القيود المرحّلة.
            الفرق عدد صحيح تام، والصفر يُعلن صراحة. لا يوجد دفتر ثانٍ.
          </p>
        </div>
        {checkpoints.length === 0 ? (
          <p className="empty">لم تُسجَّل نقاط مطابقة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr>
                  <th>النقطة</th><th>حتى تاريخ</th><th>خارجي</th><th>Terranex</th><th>الفرق</th>
                  <th>الحالة</th><th>استثناءات مفتوحة</th><th>سجّلها</th><th>اعتمدها</th><th>الدليل</th><th></th>
                </tr>
              </thead>
              <tbody>
                {checkpoints.map((row) => (
                  <tr key={row.checkpoint_id}>
                    <td data-label="النقطة">{CHECKPOINT_AR[row.checkpoint_code] ?? row.checkpoint_code}</td>
                    <td data-label="حتى تاريخ">{d(row.as_of_date)}</td>
                    <td data-label="خارجي">{money(row.external_value_minor_units)}</td>
                    <td data-label="Terranex">{money(row.terranex_value_minor_units)}</td>
                    <td data-label="الفرق" className={row.is_zero_variance ? undefined : 'error'}>
                      {row.is_zero_variance ? 'صفر — مطابقة تامة' : money(row.variance_minor_units)}
                    </td>
                    <td data-label="الحالة"><span className="status">{row.status === 'SIGNED_OFF' ? 'معتمدة' : row.status === 'MATCHED' ? 'مطابقة' : 'فرق'}</span></td>
                    <td data-label="استثناءات مفتوحة">{row.open_exception_count}{row.max_open_severity ? ` · ${SEVERITY_AR[row.max_open_severity]}` : ''}</td>
                    <td data-label="سجّلها">مُعِدّ مسجّل</td>
                    <td data-label="اعتمدها">{row.signed_off_by ? 'مالك معتمد' : '—'}</td>
                    <td data-label="الدليل">{row.external_evidence_reference}</td>
                    <td data-label="">
                      {isOwner && row.status !== 'SIGNED_OFF' && row.open_exception_count === 0 && (
                        <SignOffCheckpointForm organizationId={organizationId} projectId={projectId} checkpointId={row.checkpoint_id} />
                      )}
                      {row.status === 'SIGNED_OFF' && <span className="muted">مثبتة في {dt(row.signed_off_at)}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {isOwner ? (
          <RecordCheckpointForm
            organizationId={organizationId}
            projectId={projectId}
            checkpointCodes={checkpointOptions}
            members={members.map((member) => ({ userId: member.user_id, role: member.role, status: member.status }))}
            asOfDate={today}
          />
        ) : (
          <p className="muted">تسجيل نقاط المطابقة واعتمادها متاح لمالك المنظمة فقط.</p>
        )}
      </section>

      <section id="exceptions" className="card stack scroll-target">
        <h2>استثناءات الفروق</h2>
        {exceptions.length === 0 ? (
          <p className="empty">لا توجد استثناءات مطابقة.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>النقطة</th><th>حتى تاريخ</th><th>الفرق</th><th>الخطورة</th><th>المالك</th><th>الحالة</th><th>البيان</th><th>المعالجة</th><th></th></tr>
              </thead>
              <tbody>
                {exceptions.map((row) => (
                  <tr key={row.exception_id}>
                    <td data-label="النقطة">{CHECKPOINT_AR[row.checkpoint_code] ?? row.checkpoint_code}</td>
                    <td data-label="حتى تاريخ">{d(row.as_of_date)}</td>
                    <td data-label="الفرق" className="error">{money(row.variance_minor_units)}</td>
                    <td data-label="الخطورة">{SEVERITY_AR[row.severity] ?? row.severity}</td>
                    <td data-label="المالك">{row.owner_user_id.slice(0, 8)}…</td>
                    <td data-label="الحالة"><span className="status">{row.status === 'OPEN' ? 'مفتوح' : 'مُعالج'}</span></td>
                    <td data-label="البيان">{row.detail}</td>
                    <td data-label="المعالجة">{row.resolution ? `${row.resolution} · ${row.resolution_evidence_reference ?? ''}` : '—'}</td>
                    <td data-label="">
                      {isOwner && row.status === 'OPEN' && (
                        <ResolveExceptionForm organizationId={organizationId} projectId={projectId} exceptionId={row.exception_id} />
                      )}
                      {row.status === 'RESOLVED' && <span className="muted">أُغلق في {dt(row.resolved_at)}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section id="uat" className="card stack scroll-target">
        <div>
          <h2>اختبار قبول العميل</h2>
          <p className="muted">
            التنفيذ والقبول فعلان منفصلان بشخصين مختلفين. المهمة تبقى «بانتظار» ما لم يوجد دليل بشري حقيقي؛
            لا شيء في النظام يحوّل نجاحًا آليًا إلى قبول عميل.
          </p>
        </div>
        {uatTasks.length === 0 ? (
          <p className="empty">لم تُسجَّل مهام اختبار قبول بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead>
                <tr><th>الرمز</th><th>العنوان</th><th className="num">النتيجة المتوقعة</th><th>الحالة</th><th>نفّذها</th><th>راجعها</th><th>الدليل</th><th>ملاحظات</th><th></th></tr>
              </thead>
              <tbody>
                {uatTasks.map((row) => (
                  <tr key={row.task_id}>
                    <td data-label="الرمز">{row.task_code}</td>
                    <td data-label="العنوان">{row.title}</td>
                    <td className="num" data-label="النتيجة المتوقعة">{row.expected_outcome}</td>
                    <td data-label="الحالة"><span className="status">{UAT_STATUS_AR[row.status] ?? row.status}</span></td>
                    <td data-label="نفّذها">{row.executed_by ? `${row.executed_by.slice(0, 8)}… · ${dt(row.executed_at)}` : '—'}</td>
                    <td data-label="راجعها">{row.reviewed_by ? `${row.reviewed_by.slice(0, 8)}… · ${dt(row.reviewed_at)}` : '—'}</td>
                    <td data-label="الدليل">{row.acceptance_evidence_reference ?? row.execution_evidence_reference ?? '—'}</td>
                    <td data-label="ملاحظات" className={row.rejection_reason ? 'error' : undefined}>{row.rejection_reason ?? row.notes ?? '—'}</td>
                    <td data-label="">
                      {isOwner && row.status === 'PENDING' && (
                        <RecordUatExecutionForm organizationId={organizationId} projectId={projectId} taskId={row.task_id} />
                      )}
                      {isOwner && row.status === 'EXECUTED' && (
                        <>
                          <AcceptUatTaskForm organizationId={organizationId} projectId={projectId} taskId={row.task_id} />
                          <RejectUatTaskForm organizationId={organizationId} projectId={projectId} taskId={row.task_id} />
                        </>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {isOwner ? (
          <RegisterUatTaskForm organizationId={organizationId} projectId={projectId} />
        ) : (
          <p className="muted">إدارة مهام اختبار القبول متاحة لمالك المنظمة فقط.</p>
        )}
      </section>

      <section id="rehearsals" className="card stack scroll-target">
        <div>
          <h2>البروفات التقنية</h2>
          <p className="muted">بروفات مُنفَّذة على بيانات اختبار حتمية داخل خط التحقق. ليست تشغيلًا حقيقيًا ولا قبول عميل.</p>
        </div>
        {rehearsals.length === 0 ? (
          <p className="empty">لم تُسجَّل بروفات لهذا المشروع.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead><tr><th>البروفة</th><th className="num">النتيجة</th><th>البيان</th><th>نفّذها</th><th>التاريخ</th></tr></thead>
              <tbody>
                {rehearsals.map((row) => (
                  <tr key={row.rehearsal_id}>
                    <td data-label="البروفة">{REHEARSAL_AR[row.rehearsal_code] ?? row.rehearsal_code}</td>
                    <td data-label="النتيجة" className={row.result === 'PASS' ? undefined : 'error'}>{row.result}</td>
                    <td data-label="البيان">{row.detail}</td>
                    <td data-label="نفّذها">{row.executed_by.slice(0, 8)}…</td>
                    <td data-label="التاريخ">{dt(row.executed_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section id="access" className="card stack scroll-target">
        <div>
          <h2>الوصول والاسترداد</h2>
          <p className="muted">
            إلغاء العضوية يسري فورًا على مستوى قاعدة البيانات: العضو المُلغى يفقد القراءة والأوامر معًا،
            ولا يمكن ترك المنظمة بلا مالك نشط واحد على الأقل.
          </p>
        </div>
        {!isOwner ? (
          <p className="muted">إدارة الوصول متاحة لمالك المنظمة فقط.</p>
        ) : members.length === 0 ? (
          <p className="empty">لا توجد عضويات في هذه المنظمة.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <thead><tr><th>المستخدم</th><th>الدور</th><th>الحالة</th><th>الوصول</th><th>منذ</th><th></th></tr></thead>
              <tbody>
                {members.map((member) => (
                  <tr key={member.membership_id}>
                    <td data-label="المستخدم">{memberDisplayLabel(member.role, members.indexOf(member))}</td>
                    <td data-label="الدور">{member.role === 'OWNER' ? 'مالك' : 'عضو'}</td>
                    <td data-label="الحالة"><span className="status">{member.status === 'ACTIVE' ? 'نشط' : 'مُلغى'}</span></td>
                    <td data-label="الوصول" className={member.has_access ? undefined : 'error'}>{member.has_access ? 'ممنوح' : 'محجوب'}</td>
                    <td data-label="منذ">{dt(member.created_at)}</td>
                    <td data-label="">
                      <SetMembershipStatusForm
                        organizationId={organizationId}
                        projectId={projectId}
                        userId={member.user_id}
                        nextStatus={member.status === 'ACTIVE' ? 'INACTIVE' : 'ACTIVE'}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </section>
  );
}

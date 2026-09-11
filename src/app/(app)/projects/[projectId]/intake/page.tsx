import { recordStatusLabel } from '@/features/projects/labels';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { ReactNode } from 'react';
import { getOrganizations } from '@/features/organizations/queries';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getCashAccountPositions, getStatementLines, getUnpostedContributions } from '@/features/finance/queries';
import {
  getActiveVersion,
  getCapitalCallLines,
  getCapitalCalls,
  getCommitments,
  getContributions,
  getParticipants,
  getParties,
  getVersions,
} from '@/features/funding/queries';
import { getAccountingPeriods } from '@/features/close/queries';
import {
  getBudgets,
  getParcels,
  getPropertyWorkspaces,
  getRealEstateProfile,
} from '@/features/real-estate/queries';
import {
  getOpeningImportRows,
  getOpeningImports,
  getOpeningMappingCodes,
  getPilotAcceptanceReport,
  getReconciliationCheckpoints,
  getReconciliationExceptions,
  type OpeningImport,
} from '@/features/pilot/queries';
import {
  buildIntakeSnapshot,
  evaluateIntakeReadiness,
  getIntakeApplicability,
  getIntakeDeclaration,
  getIntakeEvidenceItems,
  getIntakeModellingGaps,
} from '@/features/intake/queries';
import type { ConditionalSectionCode } from '@/features/intake/schema';
import type { IntakeSection, SectionStatus } from '@/features/intake/readiness';
import { formatMinorUnits } from '@/shared/money';
import { newCommandNonce } from '@/shared/idempotency';
import { CreatePartyForm, AddParticipantForm, AgreementDraftForm, ActivateVersionButton } from '../terms/forms';
import { CapitalCallForm, ContributionForm } from '../funding/forms';
import { CashAccountForm, BankImportForm } from '../cash/forms';
import { ProfileForm, AssetForm, ParcelForm, AcquisitionForm, BudgetForm, ApprovalButton } from '../operations/forms';
import {
  ApproveOpeningImportForm,
  RejectOpeningImportForm,
  ReviewOpeningImportForm,
  StageOpeningImportForm,
  ValidateOpeningImportForm,
} from '../pilot/forms';
import { CreateAccountingPeriodForm } from '../close/forms';
import {
  AcceptModellingGapForm,
  ControlTotalsForm,
  EvidenceItemForm,
  FreezeDateForm,
  ModellingGapForm,
  SectionApplicabilityForm,
  SetupReferencesForm,
} from './forms';

export const dynamic = 'force-dynamic';

const STATUS_AR: Record<SectionStatus, string> = {
  COMPLETE: 'مكتمل',
  MISSING: 'ناقص إلزامي',
  CONDITIONAL_OPEN: 'اختياري — بانتظار قرار',
  NOT_APPLICABLE: 'لا ينطبق',
  BLOCKED: 'موقوف',
  IN_PROGRESS: 'جارٍ',
  FAILED: 'فشل',
};

const GROUP_HREF: Record<string, string> = {
  PROJECT_SETUP: '#setup',
  INVESTORS_AND_TERMS: '#investors',
  CAPITAL_HISTORY: '#capital',
  BANK_AND_CASH: '#cash',
  PROPERTY: '#property',
  OPENING_POSITION: '#opening',
  VALIDATION_AND_RECONCILIATION: '#validation',
};

function isTerminal(status: OpeningImport['status']) {
  return status === 'POSTED' || status === 'REJECTED' || status === 'FAILED';
}

function Badge({ status }: { status: SectionStatus }) {
  return <span className={`status intake-badge intake-badge-${status.toLowerCase()}`}>{STATUS_AR[status]}</span>;
}

function SectionCard({ item, children }: { item: IntakeSection; children?: React.ReactNode }) {
  return (
    <article id={item.code} className="card stack scroll-target">
      <div className="topline">
        <div>
          <h3>{item.titleAr}</h3>
          <p className="muted">{item.summaryAr}</p>
        </div>
        <Badge status={item.status} />
      </div>
      {item.blockingReasons.length > 0 && (
        <ul className="error" role="alert">
          {item.blockingReasons.map((reason) => <li key={reason}>{reason}</li>)}
        </ul>
      )}
      {item.warnings.map((warning) => <p key={warning} className="muted">{warning}</p>)}
      {children}
    </article>
  );
}

export default async function IntakePage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [
    membership,
    organizations,
    parties,
    participants,
    activeVersion,
    versions,
    calls,
    contributions,
    cashAccounts,
    statementLines,
    unpostedContributions,
    periods,
    profile,
    assets,
    parcels,
    budgets,
    imports,
    mappingCodes,
    checkpoints,
    exceptions,
    report,
    declaration,
    applicability,
    gaps,
    evidenceItems,
  ] = await Promise.all([
    getCurrentMembership(organizationId),
    getOrganizations(),
    getParties(organizationId),
    getParticipants(projectId),
    getActiveVersion(projectId),
    getVersions(projectId),
    getCapitalCalls(projectId),
    getContributions(projectId),
    getCashAccountPositions(projectId),
    getStatementLines(projectId),
    getUnpostedContributions(projectId),
    getAccountingPeriods(projectId),
    getRealEstateProfile(projectId),
    getPropertyWorkspaces(projectId),
    getParcels(projectId),
    getBudgets(projectId),
    getOpeningImports(projectId),
    getOpeningMappingCodes(),
    getReconciliationCheckpoints(projectId),
    getReconciliationExceptions(projectId),
    getPilotAcceptanceReport(projectId),
    getIntakeDeclaration(projectId),
    getIntakeApplicability(projectId),
    getIntakeModellingGaps(projectId),
    getIntakeEvidenceItems(projectId),
  ]);

  if (!membership) {
    return (
      <section className="card">
        <h1>غير مصرح</h1>
        <p className="error">عضويتك لا تسمح بقراءة مسار إدخال هذا المشروع.</p>
        <Link className="button" href={`/projects/${projectId}`}>العودة للمشروع</Link>
      </section>
    );
  }

  const isOwner = membership.role === 'OWNER';
  const commitments = activeVersion ? await getCommitments(activeVersion.id) : [];
  const callLines = await getCapitalCallLines(calls.map((call) => call.id));
  const draftVersions = versions.filter((version) => version.status === 'DRAFT');
  const issuedCalls = calls.filter((call) => call.status === 'ISSUED');
  const openPeriod = periods.find((period) => period.status === 'OPEN') ?? null;
  const freezeDate = declaration?.freeze_date ?? null;
  const openPeriodCoversFreeze = Boolean(
    freezeDate && openPeriod && openPeriod.start_date <= freezeDate && openPeriod.end_date >= freezeDate,
  );
  const activeImport = imports.find((row) => !isTerminal(row.status)) ?? null;
  const latestImport = activeImport ?? imports[0] ?? null;
  const importRows = latestImport ? await getOpeningImportRows([latestImport.import_id]) : [];
  const openingCodes = [...new Set(importRows.filter((row) => row.status === 'ACCEPTED').map((row) => row.mapping_code))];
  const approvedBudgets = budgets.filter((budget) => budget.status === 'APPROVED');
  const acquiredAssets = assets.filter((asset) => Boolean(asset.acquisition_id));
  const eligibleParties = parties.filter((party) => !participants.some((participant) => participant.party_id === party.id));
  const money = (value: string | null | undefined) => formatMinorUnits(value ?? '0', project.reporting_currency);

  const snapshot = buildIntakeSnapshot({
    organizationName: organizations.find((org) => org.id === organizationId)?.name ?? null,
    projectName: project.name,
    sector: project.sector,
    reportingCurrency: project.reporting_currency,
    declaration,
    applicability,
    gaps,
    evidenceItems,
    investorCount: participants.length,
    activeAgreement: Boolean(activeVersion),
    agreementEffectiveDate: activeVersion?.effective_date ?? null,
    commitmentCount: commitments.length,
    issuedCallCount: issuedCalls.length,
    contributionCount: contributions.length,
    contributionCashAttributedCount: contributions.length - unpostedContributions.length,
    cashAccountCount: cashAccounts.length,
    bankStatementLineCount: statementLines.length,
    openPeriodExists: Boolean(openPeriod),
    openPeriodCoversFreeze,
    realEstateProfile: Boolean(profile),
    realEstateStrategy: profile?.strategy ?? null,
    assetCount: assets.length,
    parcelCount: parcels.length,
    acquisitionCount: acquiredAssets.length,
    approvedBudgetCount: approvedBudgets.length,
    openingImportStatus: latestImport?.status ?? null,
    openingRejectedRowCount: latestImport?.rejected_row_count ?? 0,
    openingControlTotalsMatch: latestImport?.control_totals_match ?? null,
    openingIsReversed: latestImport?.is_reversed ?? false,
    openingMappingCodes: openingCodes,
    openingDebitVariance: latestImport?.debit_variance_minor_units ?? null,
    openingCreditVariance: latestImport?.credit_variance_minor_units ?? null,
    matchedZeroVarianceCheckpoints: checkpoints.filter((row) => row.is_zero_variance).length,
    nonZeroVarianceCheckpoints: checkpoints.filter((row) => !row.is_zero_variance).length,
    openCriticalExceptions: exceptions.filter((row) => row.status === 'OPEN' && row.severity === 'CRITICAL').length,
  });
  // Organization name is not on the project row; treat presence of the project as DS-01 complete.
  snapshot.organizationName = 'منظمة المشروع';

  const readiness = evaluateIntakeReadiness(snapshot);
  const byCode = new Map(readiness.sections.map((item) => [item.code, item]));
  const next = readiness.nextSection ? byCode.get(readiness.nextSection) : null;
  const applicabilityByCode = new Map(applicability.map((row) => [row.section_code, row]));

  const mappingOptions = mappingCodes.map((mapping) => ({
    code: mapping.code,
    label: mapping.label_ar,
    naturalSide: mapping.natural_side,
    requiresParty: mapping.requires_party,
    requiresCashAccount: mapping.requires_cash_account,
  }));

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="back-link" href={`/projects/${projectId}`}>→ مساحة المشروع</Link>
          <h1>إدخال المشروع الحقيقي</h1>
          <p className="muted">{project.name} · {project.reporting_currency} · مسار موجّه بالعربية، دون نموذج قاعدة بيانات.</p>
        </div>
        <nav className="tab-strip tab-strip-inpage stepper" aria-label="أقسام الإدخال">
          {readiness.groups.map((group, index) => (
            <a
              key={group.id}
              href={GROUP_HREF[group.id]}
              aria-current={group.next ? 'step' : undefined}
              className={group.complete === group.total ? 'tab done' : group.next ? 'tab current' : 'tab'}
            >
              <span className="step-index" aria-hidden="true">{index + 1}</span>
              {group.titleAr}
              <span className="muted"> {group.complete}/{group.total}</span>
            </a>
          ))}
        </nav>
      </header>

      <section className="card stack" id="result" aria-labelledby="result-title">
        <div className="topline">
          <div>
            <h2 id="result-title">نتيجة الجاهزية</h2>
            <p>{readiness.verdictAr}</p>
          </div>
          <span className="status">{readiness.phase2Passed ? 'المرحلة 2 ناجحة' : 'المرحلة 2 غير مكتملة'}</span>
        </div>
        <p className="error" role="status">{readiness.phase2ReasonAr}</p>
        {next && (
          <p>
            الخطوة التالية: <a href={`#${next.code}`}><strong>{next.titleAr}</strong></a>
          </p>
        )}
        {readiness.mandatoryMissing.length > 0 && (
          <p className="muted">أقسام إلزامية ناقصة: {readiness.mandatoryMissing.map((code) => byCode.get(code)?.titleAr).join(' · ')}</p>
        )}
        {readiness.failures.length > 0 && (
          <p className="error" role="alert">إخفاقات ظاهرة: {readiness.failures.map((code) => byCode.get(code)?.titleAr).join(' · ')}</p>
        )}
        {report && (
          <div className="metric-grid">
            <article className="metric"><span className="muted">استيرادات مرحّلة</span><strong>{report.posted_opening_imports}</strong></article>
            <article className="metric"><span className="muted">سطور مرفوضة</span><strong>{report.opening_import_rejected_rows}</strong></article>
            <article className="metric"><span className="muted">فروق غير صفرية</span><strong>{report.reconciliation_non_zero_variances}</strong></article>
            <article className="metric"><span className="muted">استثناءات مفتوحة</span><strong>{report.unresolved_exceptions}</strong></article>
          </div>
        )}
        {!isOwner && <p className="muted">أوامر الإدخال المادية متاحة لمالك المنظمة فقط.</p>}
      </section>

      <section id="setup" className="stack scroll-target" aria-labelledby="setup-title">
        <div className="section-heading">
          <div>
            <h2 id="setup-title">إعداد المشروع</h2>
            <p className="muted">المنظمة والمشروع وتاريخ التجميد. عملة المشروع: جنيه مصري (EGP). القطاع يُحدد عند الإنشاء: عقارات أو زراعة أو ثروة حيوانية.</p>
          </div>
        </div>
        <SectionCard item={byCode.get('DS01_ORGANIZATION')!}>
          <SetupReferencesForm
            organizationId={organizationId}
            projectId={projectId}
            agreementTitle={declaration?.agreement_title_or_reference ?? undefined}
            organizationEvidence={declaration?.organization_evidence_reference ?? undefined}
            projectEvidence={declaration?.project_evidence_reference ?? undefined}
            disabled={!isOwner}
          />
        </SectionCard>
        <SectionCard item={byCode.get('DS02_PROJECT')!}>
          <p className="muted">الاسم: {project.name}{project.internal_reference ? ` · ${project.internal_reference}` : ''}</p>
          {project.description && <p>{project.description}</p>}
        </SectionCard>
        <SectionCard item={byCode.get('FREEZE_DATE')!}>
          {declaration?.freeze_date ? (
            <p>مثبّت في {declaration.freeze_date} · دليل {declaration.freeze_evidence_reference}</p>
          ) : (
            <FreezeDateForm organizationId={organizationId} projectId={projectId} disabled={!isOwner} />
          )}
        </SectionCard>
      </section>

      <section id="investors" className="stack scroll-target" aria-labelledby="investors-title">
        <div className="section-heading">
          <div>
            <h2 id="investors-title">المستثمرون والشروط</h2>
            <p className="muted">طرف واحد لكل شخص أو جهة. الالتزام ليس ملكية، والملكية ليست مساهمة.</p>
          </div>
        </div>
        <SectionCard item={byCode.get('DS03_PARTIES')!}>
          {participants.length > 0 && (
            <ul>
              {participants.map((participant) => (
                <li key={participant.id}>{participant.parties.legal_name} — مستثمر</li>
              ))}
            </ul>
          )}
          {!activeVersion && (
            <>
              <details className="stack">
                <summary>إضافة طرف جديد</summary>
                <CreatePartyForm organizationId={organizationId} projectId={projectId} />
              </details>
              {eligibleParties.length > 0 && (
                <details className="stack" open={participants.length === 0}>
                  <summary>إضافة طرف قائم كمستثمر</summary>
                  <AddParticipantForm organizationId={organizationId} projectId={projectId} parties={eligibleParties} />
                </details>
              )}
            </>
          )}
        </SectionCard>
        <SectionCard item={byCode.get('DS04_AGREEMENT')!}>
          {activeVersion ? (
            <>
              <p>نسخة {activeVersion.version_no} مفعّلة من {activeVersion.effective_date}.</p>
              {!declaration?.agreement_title_or_reference && (
                <p className="muted">أضف عنوان الاتفاقية من قسم الإعداد أعلاه.</p>
              )}
              <p className="muted">
                حقائق الاتفاقية مثبتة. سياسة الملكية والتخصيص وتوزيع الربح لم تُقرّ بعد من المالك المفوَّض — «غير محددة بسياسة معتمدة»، ولا تُطلب لإكمال الجاهزية.
              </p>
            </>
          ) : participants.length === 0 ? (
            <p className="muted">أضف مستثمرًا قبل مسودة الاتفاقية.</p>
          ) : (
            <AgreementDraftForm
              organizationId={organizationId}
              projectId={projectId}
              participants={participants}
              currency={project.reporting_currency}
            />
          )}
        </SectionCard>
        <SectionCard item={byCode.get('DS05_COMMITMENTS')!}>
          {commitments.length === 0 ? (
            <p className="muted">الالتزامات تُحفظ داخل مسودة الاتفاقية ثم تُجمَّد عند التفعيل.</p>
          ) : (
            <div className="table-wrap">
              <table className="table-stackable">
              <caption className="sr-only">جدول: المستثمر · الالتزام</caption>
                <thead><tr><th scope="col">المستثمر</th><th scope="col" className="num">الالتزام</th></tr></thead>
                <tbody>
                  {commitments.map((commitment) => {
                    const name = participants.find((participant) => participant.id === commitment.participant_id)?.parties.legal_name;
                    return (
                      <tr key={commitment.id}>
                        <td data-label="المستثمر">{name ?? '—'}</td>
                        <td className="num" data-label="الالتزام">{formatMinorUnits(commitment.commitment_minor_units, commitment.currency)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </SectionCard>
      </section>

      <section id="capital" className="stack scroll-target" aria-labelledby="capital-title">
        <div className="section-heading">
          <div>
            <h2 id="capital-title">تاريخ رأس المال</h2>
            <p className="muted">اختياري إن لم توجد طلبات أو مساهمات قبل التجميد. مسار واحد لكل أثر نقدي.</p>
          </div>
        </div>
        <SectionCard item={byCode.get('DS06_HISTORICAL_CALLS')!}>
          {activeVersion && (
            <>
              <CapitalCallForm
                organizationId={organizationId}
                projectId={projectId}
                versionId={activeVersion.id}
                currency={project.reporting_currency}
                participants={participants}
                commitments={commitments}
              />
              <ApplicabilityBlock
                organizationId={organizationId}
                projectId={projectId}
                code="HISTORICAL_CALLS"
                current={applicabilityByCode.get('HISTORICAL_CALLS')}
                disabled={!isOwner}
              />
            </>
          )}
        </SectionCard>
        <SectionCard item={byCode.get('DS07_HISTORICAL_CONTRIBUTIONS')!}>
          {activeVersion && (
            <>
              <ContributionForm
                organizationId={organizationId}
                projectId={projectId}
                versionId={activeVersion.id}
                currency={project.reporting_currency}
                calls={calls}
                lines={callLines}
                participants={participants}
              />
              <p className="muted">
                إن كان الأثر النقدي جزءًا من رصيد البنك الافتتاحي فلا تُسند المساهمة نقديًا هنا.
                المسار البديل: رأس مال مساهم افتتاحي + نقدية افتتاحية.
              </p>
              <ApplicabilityBlock
                organizationId={organizationId}
                projectId={projectId}
                code="HISTORICAL_CONTRIBUTIONS"
                current={applicabilityByCode.get('HISTORICAL_CONTRIBUTIONS')}
                disabled={!isOwner}
              />
            </>
          )}
        </SectionCard>
      </section>

      <section id="cash" className="stack scroll-target" aria-labelledby="cash-title">
        <div className="section-heading">
          <div>
            <h2 id="cash-title">البنك والنقدية</h2>
            <p className="muted">الرصيد الدفتري يُشتق من القيود فقط. رقم الحساب البنكي دليل خارجي.</p>
          </div>
        </div>
        <SectionCard item={byCode.get('DS08_CASH_ACCOUNTS')!}>
          {cashAccounts.length > 0 && (
            <ul>
              {cashAccounts.map((account) => (
                <li key={account.cash_account_id}>
                  {account.name} — {formatMinorUnits(account.balance_minor_units, account.currency)}
                </li>
              ))}
            </ul>
          )}
          <CashAccountForm
            organizationId={organizationId}
            projectId={projectId}
            currency={project.reporting_currency}
            commandNonce={newCommandNonce()}
          />
        </SectionCard>
        <SectionCard item={byCode.get('DS16_BANK_STATEMENTS')!}>
          {cashAccounts.length > 0 && (
            <BankImportForm
              organizationId={organizationId}
              projectId={projectId}
              cashAccounts={cashAccounts}
              commandNonce={newCommandNonce()}
            />
          )}
          <ApplicabilityBlock
            organizationId={organizationId}
            projectId={projectId}
            code="BANK_STATEMENTS"
            current={applicabilityByCode.get('BANK_STATEMENTS')}
            disabled={!isOwner}
          />
        </SectionCard>
        <SectionCard item={byCode.get('ACCOUNTING_PERIOD')!}>
          {openPeriod ? (
            <p>فترة مفتوحة {openPeriod.start_date} → {openPeriod.end_date}.</p>
          ) : (
            <CreateAccountingPeriodForm
              organizationId={organizationId}
              projectId={projectId}
              startDate={freezeDate ?? undefined}
              endDate={undefined}
              disabled={!isOwner}
            />
          )}
        </SectionCard>
      </section>

      <section id="property" className="stack scroll-target" aria-labelledby="property-title">
        <div className="section-heading">
          <div>
            <h2 id="property-title">العقار</h2>
            <p className="muted">الاستراتيجية والأصل والقطعة منفصلة عن العقد والدفع.</p>
          </div>
        </div>
        {project.sector !== 'REAL_ESTATE' ? (
          <section className="card">
            <p>هذا المشروع قطاعه {project.sector === 'AGRICULTURE' ? 'زراعة' : 'ثروة حيوانية'}، وتُدار حقائقه التشغيلية من مساحة القطاع الخاصة بالمشروع، وليست ضمن نموذج الإدخال العقاري.</p>
            <Link className="button" href={`/projects/${projectId}/${project.sector === 'AGRICULTURE' ? 'agriculture' : 'livestock'}`}>فتح مساحة القطاع</Link>
          </section>
        ) : (
          <>
        <SectionCard item={byCode.get('DS11_PROPERTY')!}>
          {!profile && <ProfileForm organizationId={organizationId} projectId={projectId} />}
          <AssetForm organizationId={organizationId} projectId={projectId} />
          {assets.length > 0 && <ParcelForm organizationId={organizationId} projectId={projectId} assets={assets} />}
        </SectionCard>
        <SectionCard item={byCode.get('DS12_ACQUISITION')!}>
          {assets.length > 0 && (
            <AcquisitionForm
              organizationId={organizationId}
              projectId={projectId}
              currency={project.reporting_currency}
              assets={assets}
              parties={parties}
              obligations={[]}
            />
          )}
          <ApplicabilityBlock
            organizationId={organizationId}
            projectId={projectId}
            code="ACQUISITION_BASIS"
            current={applicabilityByCode.get('ACQUISITION_BASIS')}
            disabled={!isOwner}
          />
        </SectionCard>
        <SectionCard item={byCode.get('DS13_DEVELOPMENT')!}>
          {assets.length > 0 && (
            <>
              <BudgetForm
                organizationId={organizationId}
                projectId={projectId}
                currency={project.reporting_currency}
                assets={assets}
                parcels={parcels}
                phases={[]}
              />
              {budgets.filter((budget) => budget.status === 'PROPOSED').map((budget) => (
                <ApprovalButton
                  key={budget.budget_version_id}
                  kind="budget"
                  organizationId={organizationId}
                  projectId={projectId}
                  subjectId={budget.budget_version_id}
                />
              ))}
            </>
          )}
          <ApplicabilityBlock
            organizationId={organizationId}
            projectId={projectId}
            code="DEVELOPMENT_BASELINE"
            current={applicabilityByCode.get('DEVELOPMENT_BASELINE')}
            disabled={!isOwner}
          />
        </SectionCard>
          </>
        )}
      </section>

      <section id="opening" className="stack scroll-target" aria-labelledby="opening-title">
        <div className="section-heading">
          <div>
            <h2 id="opening-title">المركز الافتتاحي</h2>
            <p className="muted">ستة ترميزات فقط. أي رصيد لا يناسبها فجوة نمذجة، لا اجتهاد.</p>
          </div>
        </div>
        <SectionCard item={byCode.get('CONTROL_TOTALS')!}>
          {declaration?.declared_debit_total_minor_units ? (
            <p>
              مدين {money(declaration.declared_debit_total_minor_units)} =
              دائن {money(declaration.declared_credit_total_minor_units)} ·
              دليل {declaration.control_totals_evidence_reference}
            </p>
          ) : (
            <ControlTotalsForm organizationId={organizationId} projectId={projectId} disabled={!isOwner} />
          )}
        </SectionCard>
        <SectionCard item={byCode.get('DS09_OPENING_BALANCES')!}>
          {latestImport && (
            <p>
              {latestImport.source_file_name} · {recordStatusLabel(latestImport.status)} ·
              مقبول {latestImport.accepted_row_count} / مرفوض {latestImport.rejected_row_count} ·
              فرق المدين {money(latestImport.debit_variance_minor_units)} ·
              فرق الدائن {money(latestImport.credit_variance_minor_units)}
            </p>
          )}
          {isOwner && activeImport?.status === 'DRAFT' && (
            <ValidateOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
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
          <details>
            <summary>رصيد لا يناسب أي ترميز معتمد</summary>
            <ModellingGapForm organizationId={organizationId} projectId={projectId} disabled={!isOwner} />
          </details>
          {gaps.length > 0 && (
            <div className="table-wrap">
              <table className="table-stackable"><caption className="sr-only">جدول: المصدر · الوصف · المبلغ · الحالة</caption>
                <thead><tr><th scope="col">المصدر</th><th scope="col">الوصف</th><th scope="col" className="num">المبلغ</th><th scope="col">الحالة</th><th scope="col"></th></tr></thead>
                <tbody>
                  {gaps.map((gap) => (
                    <tr key={gap.gap_id}>
                      <td data-label="المصدر">{gap.source_reference}</td>
                      <td data-label="الوصف">{gap.description}<br /><span className="muted">{gap.why_unmappable}</span></td>
                      <td className="num" data-label="المبلغ">{gap.amount_minor_units ? money(gap.amount_minor_units) : '—'}</td>
                      <td data-label="الحالة">{gap.status === 'OPEN' ? 'مفتوحة' : 'مقبولة تجاريًا'}</td>
                      <td data-label="">
                        {gap.status === 'OPEN' && isOwner && (
                          <AcceptModellingGapForm organizationId={organizationId} projectId={projectId} gapId={gap.gap_id} />
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </SectionCard>
        <SectionCard item={byCode.get('DS10_UNPAID_SUPPLIERS')!}>
          <p className="muted">يُمثَّل داخل الاستيراد بترميز مستحق الموردين مع الطرف والمبلغ ومرجع الفاتورة في الوصف.</p>
          <ApplicabilityBlock organizationId={organizationId} projectId={projectId} code="UNPAID_SUPPLIERS" current={applicabilityByCode.get('UNPAID_SUPPLIERS')} disabled={!isOwner} />
        </SectionCard>
        <SectionCard item={byCode.get('DS14_SALES')!}>
          <p className="muted">المبيعات المكتملة قبل التجميد لا تُعاد. المتبقي فقط: ذمم عملاء أو نقدية افتتاحية.</p>
          <ApplicabilityBlock organizationId={organizationId} projectId={projectId} code="SALES_DISPOSITIONS" current={applicabilityByCode.get('SALES_DISPOSITIONS')} disabled={!isOwner} />
        </SectionCard>
        <SectionCard item={byCode.get('DS15_DISTRIBUTIONS')!}>
          <p className="muted">غير المدفوع المعتمد فقط يدخل كمستحق توزيع افتتاحي.</p>
          <ApplicabilityBlock organizationId={organizationId} projectId={projectId} code="HISTORICAL_DISTRIBUTIONS" current={applicabilityByCode.get('HISTORICAL_DISTRIBUTIONS')} disabled={!isOwner} />
        </SectionCard>
      </section>

      <section id="validation" className="stack scroll-target" aria-labelledby="validation-title">
        <div className="section-heading">
          <div>
            <h2 id="validation-title">التحقق والمطابقة</h2>
            <p className="muted">مسودة → تحقق → ترشيح → اعتماد وترحيل → مطابقة بفرق صفر. المعدّ لا يعتمد.</p>
          </div>
        </div>
        <SectionCard item={byCode.get('OPENING_VALIDATION')!}>
          {isOwner && activeImport?.status === 'DRAFT' && (
            <ValidateOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
          )}
        </SectionCard>
        <SectionCard item={byCode.get('OPENING_APPROVAL')!}>
          {isOwner && activeImport?.status === 'VALIDATED' && (
            <ReviewOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
          )}
          {isOwner && activeImport?.status === 'READY_FOR_APPROVAL' && activeImport.control_totals_match && activeImport.rejected_row_count === 0 && (
            <ApproveOpeningImportForm
              organizationId={organizationId}
              projectId={projectId}
              importId={activeImport.import_id}
              postingDate={openPeriod?.start_date ?? freezeDate ?? ''}
            />
          )}
          {isOwner && activeImport && !isTerminal(activeImport.status) && (
            <RejectOpeningImportForm organizationId={organizationId} projectId={projectId} importId={activeImport.import_id} />
          )}
        </SectionCard>
        <SectionCard item={byCode.get('OPENING_POSTING')!}>
          {latestImport?.status === 'POSTED' && !latestImport.is_reversed ? (
            <p>قيد مُرحَّل في {latestImport.posting_date}. التصحيح بعكس مرتبط فقط.</p>
          ) : (
            <p className="muted">لا يُكتب رصيد مباشرة أبدًا.</p>
          )}
        </SectionCard>
        <SectionCard item={byCode.get('OPENING_RECONCILIATION')!}>
          {checkpoints.length === 0 ? (
            <p className="muted">بعد الترحيل، سجّل نقاط المطابقة من <Link href={`/projects/${projectId}/pilot#reconciliation`}>لوحة التشغيل التجريبي</Link>.</p>
          ) : (
            <ul>
              {checkpoints.map((row) => (
                <li key={row.checkpoint_id}>
                  {row.checkpoint_code}: {row.is_zero_variance ? 'صفر — مطابقة تامة' : money(row.variance_minor_units)}
                </li>
              ))}
            </ul>
          )}
        </SectionCard>
        <SectionCard item={byCode.get('DS17_EVIDENCE')!}>
          {evidenceItems.length > 0 && (
            <div className="table-wrap">
              <table className="table-stackable">
              <caption className="sr-only">جدول: المعرّف · الحقيقة · موقع العميل</caption>
                <thead><tr><th scope="col">المعرّف</th><th scope="col">الحقيقة</th><th scope="col">موقع العميل</th></tr></thead>
                <tbody>
                  {evidenceItems.map((item) => (
                    <tr key={item.evidence_item_id}>
                      <td data-label="المعرّف">{item.evidence_identifier}</td>
                      <td data-label="الحقيقة">{item.linked_fact}</td>
                      <td data-label="موقع العميل">{item.customer_storage_location}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <EvidenceItemForm organizationId={organizationId} projectId={projectId} disabled={!isOwner} />
        </SectionCard>
        <SectionCard item={byCode.get('READINESS_RESULT')!}>
          <p>النظام جاهز لاستقبال بيانات المشروع الحقيقي عبر هذا المسار. المرحلة 2 لن تُعلَن من هنا.</p>
        </SectionCard>
      </section>
    </section>
  );
}

function ApplicabilityBlock({
  organizationId, projectId, code, current, disabled,
}: {
  organizationId: string;
  projectId: string;
  code: ConditionalSectionCode;
  current?: { applicable: boolean; reason: string };
  disabled?: boolean;
}) {
  return (
    <details>
      <summary>{current ? (current.applicable ? 'مصرّح: ينطبق' : `مصرّح: لا ينطبق — ${current.reason}`) : 'تصريح: ينطبق أو لا ينطبق'}</summary>
      <SectionApplicabilityForm
        organizationId={organizationId}
        projectId={projectId}
        sectionCode={code}
        disabled={disabled}
      />
    </details>
  );
}

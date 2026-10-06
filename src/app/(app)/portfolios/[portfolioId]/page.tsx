import Link from 'next/link';
import { notFound } from 'next/navigation';
import { SECTOR_LABEL, formatDate } from '@/features/agriculture/labels';
import { formatMinorUnits } from '@/shared/money';
import { getOrganizations } from '@/features/organizations/queries';
import {
  getAssignableProjects,
  getOrganizationMembers,
  getPortfolio,
  getPortfolioMemberships,
  getPortfolioStatusHistory,
  getPortfolios,
} from '@/features/portfolios/queries';
import { getPortfolioRollup } from '@/features/control/queries';
import {
  PORTFOLIO_STATUS_BADGE_CLASS,
  PORTFOLIO_STATUS_LABEL,
} from '@/features/portfolios/labels';
import type { PortfolioStatus } from '@/features/portfolios/schema';
import { memberDisplayLabel } from '@/features/workspace/chrome';
import { sectorLandingHref } from '@/features/workspace/nav';
import { isSectorKey } from '@/features/workspace/sectors';
import { Figure, SectorChip, Section, Stat, StatGrid } from '@/shared/ui';
import { newCommandNonce } from '@/shared/idempotency';
import {
  AssignProjectForm,
  MetadataForm,
  MoveProjectForm,
  RemoveProjectForm,
  TransitionForm,
} from '../forms';

export const dynamic = 'force-dynamic';

function StatusBadge({ status }: Readonly<{ status: PortfolioStatus }>) {
  return (
    <span className={PORTFOLIO_STATUS_BADGE_CLASS[status]}>
      {PORTFOLIO_STATUS_LABEL[status]}
    </span>
  );
}

export default async function PortfolioDetailPage({
  params,
}: {
  params: Promise<{ portfolioId: string }>;
}) {
  const { portfolioId } = await params;
  const portfolio = await getPortfolio(portfolioId);
  if (!portfolio) notFound();

  const orgs = await getOrganizations();
  const org = orgs.find((o) => o.id === portfolio.organization_id) ?? orgs[0];

  const [members, memberships, assignableProjects, allPortfolios, statusHistory, rollup] =
    await Promise.all([
      getOrganizationMembers(portfolio.organization_id),
      getPortfolioMemberships(portfolioId),
      getAssignableProjects(portfolio.organization_id),
      getPortfolios(portfolio.organization_id),
      getPortfolioStatusHistory(portfolioId),
      getPortfolioRollup(portfolioId),
    ]);

  const memberOptions = members.map((m, index) => ({
    user_id: m.user_id,
    label: memberDisplayLabel(m.role, index),
  }));
  const managerLabel = (() => {
    if (!portfolio.responsible_manager_id) return null;
    const index = members.findIndex((m) => m.user_id === portfolio.responsible_manager_id);
    if (index === -1) return 'عضو سابق';
    return memberDisplayLabel(members[index].role, index);
  })();

  const activeMemberships = memberships.filter((m) => m.removed_at === null);
  const pastMemberships = memberships.filter((m) => m.removed_at !== null);
  const moveTargets = allPortfolios.filter(
    (p) => p.id !== portfolioId && p.status === 'ACTIVE',
  );
  const isReadOnly = portfolio.status === 'ARCHIVED';

  return (
    <section className="stack-lg">
      <header className="project-context card page-header">
        <div className="page-header-main">
          <Link className="back-link" href="/portfolios">→ المحافظ الاستثمارية</Link>
          <div className="page-title-row">
            <h1>{portfolio.name}</h1>
            <StatusBadge status={portfolio.status} />
          </div>
          <p className="muted page-description">
            {org?.name} · محفظة إدارية للمشاريع المستقلة
            {portfolio.description ? ` · ${portfolio.description}` : ''}
          </p>
        </div>
      </header>

      {/* Management context before financials: who owns this, and how many
          independent projects it currently frames. */}
      <StatGrid label="بيانات إدارة المحفظة">
        <Stat label="المشاريع المُسندة حاليًا" value={activeMemberships.length} hint="كل مشروع مستقل بدفتره" />
        <Stat label="الحالة" value={PORTFOLIO_STATUS_LABEL[portfolio.status]} hint={isReadOnly ? 'للقراءة فقط' : 'قابلة للتعديل'} />
        <Stat label="المدير المسؤول" value={managerLabel ?? 'غير محدد'} hint="من بيانات العضوية الحالية" />
        <Stat label="آخر تحديث" value={formatDate(portfolio.updated_at)} hint={`أُنشئت ${formatDate(portfolio.created_at)}`} />
      </StatGrid>

      <Section
        title="التجميع المالي للمحفظة"
        description="مجموع حقائق المشاريع المستقلة فقط — المحفظة ليست دفتر أستاذ ثانٍ، ولا تُجمع الأرقام أبدًا عبر عملات مختلفة."
      >
        {rollup.length === 0 ? (
          <p className="muted">لا توجد مشاريع مرتبطة حاليًا بهذه المحفظة.</p>
        ) : (
          <>
            {/* The four figures an owner actually decides on, per currency.
                Everything else stays one disclosure away. */}
            {rollup.map((row) => (
              <div key={row.currency} className="stack">
                <p className="eyebrow">عملة {row.currency} · {row.project_count} مشروع</p>
                <div className="overview-kpis">
                  <Figure basis="النقدية" value={formatMinorUnits(row.cash_balance_minor_units, row.currency)} />
                  <Figure
                    basis="مستحقات مفتوحة"
                    value={formatMinorUnits(row.payable_open_minor_units, row.currency)}
                    negative={row.overdue_obligations > 0}
                    asOf={`${row.overdue_obligations} متأخرة · ${row.disputed_obligations} متنازع عليها`}
                  />
                  <Figure basis="النتيجة المحققة" value={formatMinorUnits(row.realized_result_minor_units, row.currency)} />
                  <Figure
                    basis="استثناءات مفتوحة"
                    value={row.open_exception_count}
                    negative={row.open_exception_count > 0}
                    asOf={row.open_exception_count > 0 ? 'تحتاج معالجة' : 'لا استثناءات مسجلة'}
                  />
                </div>
              </div>
            ))}

            <Section
              headingLevel={3}
              collapsible
              title="التفصيل الكامل لكل عملة"
              description="حجز الضمان، الالتزامات المفتوحة، FAC، تركّز النقدية، وحالة التحويل"
            >
              <div className="table-wrap">
                <table className="table-stackable">
                  <caption className="sr-only">
                    التجميع المالي للمحفظة لكل عملة: المشاريع والنقدية والمستحقات والمدفوع وحجز الضمان والنتيجة المحققة والالتزامات المفتوحة
                  </caption>
                  <thead>
                    <tr>
                      <th scope="col">العملة</th>
                      <th scope="col" className="num">المشاريع</th>
                      <th scope="col" className="num">النقدية</th>
                      <th scope="col" className="num">مستحقات مفتوحة</th>
                      <th scope="col" className="num">المدفوع</th>
                      <th scope="col" className="num">حجز ضمان</th>
                      <th scope="col" className="num">النتيجة المحققة</th>
                      <th scope="col" className="num">التزامات PO مفتوحة</th>
                      <th scope="col" className="num">FAC</th>
                      <th scope="col" className="num">نزاعات / متأخرات</th>
                      <th scope="col" className="num">استثناءات مفتوحة</th>
                      <th scope="col" className="num">تركّز النقدية</th>
                      <th scope="col">حالة التحويل</th>
                      <th scope="col" className="num">النقدية بعملة التقارير</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rollup.map((row) => (
                      <tr key={row.currency}>
                        <td data-label="العملة">{row.currency}</td>
                        <td className="num" data-label="المشاريع">{row.project_count}</td>
                        <td className="num" data-label="النقدية">{formatMinorUnits(row.cash_balance_minor_units, row.currency)}</td>
                        <td className="num" data-label="مستحقات مفتوحة">{formatMinorUnits(row.payable_open_minor_units, row.currency)}</td>
                        <td className="num" data-label="المدفوع">{formatMinorUnits(row.paid_minor_units, row.currency)}</td>
                        <td className="num" data-label="حجز ضمان">{formatMinorUnits(row.retention_held_minor_units, row.currency)}</td>
                        <td className="num" data-label="النتيجة المحققة">{formatMinorUnits(row.realized_result_minor_units, row.currency)}</td>
                        <td className="num" data-label="التزامات PO مفتوحة">{formatMinorUnits(row.open_commitment_minor_units, row.currency)}</td>
                        <td className="num" data-label="FAC">{formatMinorUnits(row.fac_minor_units, row.currency)}</td>
                        <td className="num" data-label="نزاعات / متأخرات">{row.disputed_obligations} / {row.overdue_obligations}</td>
                        <td className="num" data-label="استثناءات مفتوحة">{row.open_exception_count}</td>
                        <td className="num" data-label="تركّز النقدية">{row.cash_concentration_ratio ?? '—'}</td>
                        <td data-label="حالة التحويل">{row.fx_status}</td>
                        <td className="num" data-label="النقدية بعملة التقارير">
                          {row.converted_cash_balance_minor_units && row.org_reporting_currency
                            ? formatMinorUnits(row.converted_cash_balance_minor_units, row.org_reporting_currency)
                            : '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </Section>
          </>
        )}
        {rollup.some((row) => row.sector_exposure) ? (
          <Section
            headingLevel={3}
            collapsible
            title="التعرض القطاعي"
            description="توزيع المشاريع والنقدية على القطاعات، داخل كل عملة على حدة"
          >
            <ul className="stack">
              {rollup.flatMap((row) =>
                Object.entries(row.sector_exposure ?? {}).map(([sector, stats]) => (
                  <li key={`${row.currency}-${sector}`} className="badge-row">
                    {isSectorKey(sector) ? (
                      <SectorChip sector={sector} label={SECTOR_LABEL[sector] ?? sector} />
                    ) : (
                      <span className="status">{sector}</span>
                    )}
                    <span className="muted">{stats.project_count} مشروع</span>
                    <span>نقدية {formatMinorUnits(stats.cash_balance_minor_units, row.currency)}</span>
                  </li>
                )),
              )}
            </ul>
          </Section>
        ) : null}
      </Section>

      <section className="panel-grid">
        <div className="panel">
          <h3>دورة حياة المحفظة</h3>
          {portfolio.status === 'DRAFT' ? (
            <>
              <p className="muted">
                التنشيط يجعل المحفظة جاهزة لإسناد المشاريع. لا ينشئ التنشيط أي حقوق
                ملكية أو رأس مال أو قيود محاسبية.
              </p>
              <TransitionForm
                organizationId={portfolio.organization_id}
                portfolioId={portfolioId}
                commandNonce={newCommandNonce()}
                expectedStatus="DRAFT"
                newStatus="ACTIVE"
                buttonLabel="تنشيط المحفظة"
              />
              <TransitionForm
                organizationId={portfolio.organization_id}
                portfolioId={portfolioId}
                commandNonce={newCommandNonce()}
                expectedStatus="DRAFT"
                newStatus="ARCHIVED"
                buttonLabel="أرشفة المسودة"
              />
            </>
          ) : null}
          {portfolio.status === 'ACTIVE' ? (
            <>
              <p className="muted">
                الأرشفة تحفظ المحفظة للقراءة فقط. لا تُغلق الأرشفة أي مشروع مُسند ولا
                تعدّل بياناته.
              </p>
              <TransitionForm
                organizationId={portfolio.organization_id}
                portfolioId={portfolioId}
                commandNonce={newCommandNonce()}
                expectedStatus="ACTIVE"
                newStatus="ARCHIVED"
                buttonLabel="أرشفة المحفظة"
              />
            </>
          ) : null}
          {portfolio.status === 'ARCHIVED' ? (
            <p className="muted">
              المحفظة مؤرشفة وللقراءة فقط. لا يمكن تعديل بياناتها أو إسناد مشاريع إليها.
            </p>
          ) : null}
        </div>

        {!isReadOnly ? (
          <div className="panel">
            <h3>تعديل البيانات الإدارية</h3>
            <MetadataForm
              organizationId={portfolio.organization_id}
              portfolioId={portfolioId}
              commandNonce={newCommandNonce()}
              initialName={portfolio.name}
              initialDescription={portfolio.description ?? ''}
              initialManagerId={portfolio.responsible_manager_id}
              members={memberOptions}
            />
          </div>
        ) : null}
      </section>

      <Section
        title="المشاريع المُسندة"
        description="كل مشروع يحتفظ بهويته وقطاعه وقيوده ودورة حياته. الإسناد يحدد المحفظة الإدارية الأم فقط، ولا ينقل ملكية أو أموالًا أو نتائج بين المشاريع."
      >

        {activeMemberships.length === 0 ? (
          <p className="muted empty">لا توجد مشاريع مُسندة إلى هذه المحفظة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">المشاريع المُسندة إلى المحفظة مع القطاع والمرجع الداخلي وتاريخ الإسناد</caption>
              <thead>
                <tr>
                  <th scope="col">المشروع</th>
                  <th scope="col">القطاع</th>
                  <th scope="col">المرجع الداخلي</th>
                  <th scope="col">تاريخ الإسناد</th>
                  <th scope="col">إجراءات</th>
                </tr>
              </thead>
              <tbody>
                {activeMemberships.map((m) => (
                  <tr key={m.id}>
                    <td data-label="المشروع">
                      <Link href={sectorLandingHref(m.project_sector, m.investment_project_id)}>
                        <strong>{m.project_name}</strong>
                      </Link>
                    </td>
                    <td data-label="القطاع">
                      {isSectorKey(m.project_sector) ? (
                        <SectorChip sector={m.project_sector} label={SECTOR_LABEL[m.project_sector] ?? m.project_sector} />
                      ) : (
                        <span className="status">{m.project_sector}</span>
                      )}
                    </td>
                    <td data-label="المرجع الداخلي">{m.project_internal_reference ? <code>{m.project_internal_reference}</code> : '—'}</td>
                    <td data-label="تاريخ الإسناد">{formatDate(m.assigned_at)}</td>
                    <td data-label="إجراءات">
                      <div className="stack-xs">
                        <RemoveProjectForm
                          organizationId={portfolio.organization_id}
                          portfolioId={portfolioId}
                          projectId={m.investment_project_id}
                          commandNonce={newCommandNonce()}
                        />
                        <MoveProjectForm
                          organizationId={portfolio.organization_id}
                          projectId={m.investment_project_id}
                          commandNonce={newCommandNonce()}
                          targetPortfolios={moveTargets}
                        />
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {portfolio.status === 'ACTIVE' ? (
          <div className="panel">
            <h3>إسناد مشروع إلى المحفظة</h3>
            <AssignProjectForm
              organizationId={portfolio.organization_id}
              portfolioId={portfolioId}
              commandNonce={newCommandNonce()}
              projects={assignableProjects.map((p) => ({
                id: p.id,
                label: `${p.name}${p.internal_reference ? ` (${p.internal_reference})` : ''}`,
              }))}
            />
          </div>
        ) : (
          <p className="muted">
            {portfolio.status === 'DRAFT'
              ? 'فعّل المحفظة أولًا لتتمكن من إسناد المشاريع إليها.'
              : 'لا يمكن إسناد مشاريع إلى محفظة مؤرشفة.'}
          </p>
        )}
      </Section>

      {pastMemberships.length > 0 ? (
        <Section collapsible title="سجل الإسنادات السابقة" description="العضوية محفوظة كتاريخ إلحاقي ولا تُحذف أبدًا">
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">الإسنادات السابقة: المشروع وتاريخ الإسناد وتاريخ الإزالة والسبب</caption>
              <thead>
                <tr>
                  <th scope="col">المشروع</th>
                  <th scope="col">أُسند في</th>
                  <th scope="col">أُزيل في</th>
                  <th scope="col">سبب الإزالة</th>
                </tr>
              </thead>
              <tbody>
                {pastMemberships.map((m) => (
                  <tr key={m.id}>
                    <td data-label="المشروع">{m.project_name}</td>
                    <td data-label="أُسند في">{formatDate(m.assigned_at)}</td>
                    <td data-label="أُزيل في">{formatDate(m.removed_at)}</td>
                    <td data-label="سبب الإزالة">{m.removal_reason ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      ) : null}

      <Section collapsible title="سجل حالات المحفظة" description="كل تغيير حالة محفوظ مع سببه وتاريخه">
        {statusHistory.length === 0 ? (
          <p className="muted empty">لا يوجد سجل حالات بعد.</p>
        ) : (
          <div className="milestones">
            {statusHistory.map((h) => (
              <div className="timeline-row" key={h.id}>
                <div>
                  <strong>
                    {h.previous_status
                      ? `${PORTFOLIO_STATUS_LABEL[h.previous_status]} → ${PORTFOLIO_STATUS_LABEL[h.new_status]}`
                      : `الحالة الابتدائية: ${PORTFOLIO_STATUS_LABEL[h.new_status]}`}
                  </strong>
                  {h.reason ? <p className="muted">{h.reason}</p> : null}
                </div>
                <time>{formatDate(h.changed_at)}</time>
              </div>
            ))}
          </div>
        )}
      </Section>
    </section>
  );
}

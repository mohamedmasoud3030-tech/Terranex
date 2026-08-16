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
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="muted" href="/portfolios">← المحافظ الاستثمارية</Link>
          <h1>{portfolio.name}</h1>
          <p className="muted">
            {org?.name} · محفظة إدارية للمشاريع المستقلة
          </p>
        </div>
        <div className="topline">
          <StatusBadge status={portfolio.status} />
        </div>
      </header>

      {portfolio.description ? (
        <section className="card stack">
          <h2>الغرض الإداري</h2>
          <p>{portfolio.description}</p>
        </section>
      ) : null}

      <section className="card stack">
        <div className="section-heading">
          <h2>التجميع المالي للمحفظة</h2>
          <p className="muted">
            مجموع حقائق المشاريع المستقلة فقط — المحفظة ليست دفتر أستاذ ثانٍ،
            ولا تُجمع الأرقام أبدًا عبر عملات مختلفة.
          </p>
        </div>
        {rollup.length === 0 ? (
          <p className="muted">لا توجد مشاريع مرتبطة حاليًا بهذه المحفظة.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>العملة</th>
                  <th>المشاريع</th>
                  <th>النقدية</th>
                  <th>ذمم مفتوحة</th>
                  <th>مستحقات مفتوحة</th>
                  <th>المدفوع</th>
                  <th>حجز ضمان</th>
                  <th>نزاعات</th>
                  <th>متأخرات</th>
                  <th>حالة التحويل</th>
                  <th>النقدية بعملة التقارير</th>
                </tr>
              </thead>
              <tbody>
                {rollup.map((row) => (
                  <tr key={row.currency}>
                    <td>{row.currency}</td>
                    <td>{row.project_count}</td>
                    <td>{formatMinorUnits(row.cash_balance_minor_units, row.currency)}</td>
                    <td>{formatMinorUnits(row.receivable_open_minor_units, row.currency)}</td>
                    <td>{formatMinorUnits(row.payable_open_minor_units, row.currency)}</td>
                    <td>{formatMinorUnits(row.paid_minor_units, row.currency)}</td>
                    <td>{formatMinorUnits(row.retention_held_minor_units, row.currency)}</td>
                    <td>{row.disputed_obligations}</td>
                    <td>{row.overdue_obligations}</td>
                    <td>{row.fx_status}</td>
                    <td>
                      {row.converted_cash_balance_minor_units && row.org_reporting_currency
                        ? formatMinorUnits(row.converted_cash_balance_minor_units, row.org_reporting_currency)
                        : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="card stack">
        <div className="section-heading">
          <h2>بيانات الإدارة</h2>
        </div>
        <dl className="facts">
          <div>
            <dt>الحالة</dt>
            <dd><StatusBadge status={portfolio.status} /></dd>
          </div>
          <div>
            <dt>المدير المسؤول</dt>
            <dd>{managerLabel ?? 'غير محدد'}</dd>
          </div>
          <div>
            <dt>تاريخ الإنشاء</dt>
            <dd>{formatDate(portfolio.created_at)}</dd>
          </div>
          <div>
            <dt>آخر تحديث</dt>
            <dd>{formatDate(portfolio.updated_at)}</dd>
          </div>
        </dl>
      </section>

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

      <section className="card stack">
        <div className="section-heading">
          <h2>المشاريع المُسندة</h2>
        </div>
        <p className="muted">
          كل مشروع يحتفظ بهويته وقطاعه وقيوده ودورة حياته. الإسناد يحدد المحفظة
          الإدارية الأم فقط، ولا ينقل ملكية أو أموالًا أو نتائج بين المشاريع.
        </p>

        {activeMemberships.length === 0 ? (
          <p className="muted empty">لا توجد مشاريع مُسندة إلى هذه المحفظة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>المشروع</th>
                  <th>القطاع</th>
                  <th>المرجع الداخلي</th>
                  <th>تاريخ الإسناد</th>
                  <th>إجراءات</th>
                </tr>
              </thead>
              <tbody>
                {activeMemberships.map((m) => (
                  <tr key={m.id}>
                    <td>
                      <Link href={sectorLandingHref(m.project_sector, m.investment_project_id)}>
                        <strong>{m.project_name}</strong>
                      </Link>
                    </td>
                    <td>{SECTOR_LABEL[m.project_sector as keyof typeof SECTOR_LABEL] ?? m.project_sector}</td>
                    <td>{m.project_internal_reference || '—'}</td>
                    <td>{formatDate(m.assigned_at)}</td>
                    <td>
                      <div className="stack" style={{ gap: 8 }}>
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
          <div className="panel" style={{ marginTop: 12 }}>
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
      </section>

      {pastMemberships.length > 0 ? (
        <section className="card stack">
          <h2>سجل الإسنادات السابقة</h2>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>المشروع</th>
                  <th>أُسند في</th>
                  <th>أُزيل في</th>
                  <th>سبب الإزالة</th>
                </tr>
              </thead>
              <tbody>
                {pastMemberships.map((m) => (
                  <tr key={m.id}>
                    <td>{m.project_name}</td>
                    <td>{formatDate(m.assigned_at)}</td>
                    <td>{formatDate(m.removed_at)}</td>
                    <td>{m.removal_reason ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      <section className="card stack">
        <h2>سجل حالات المحفظة</h2>
        {statusHistory.length === 0 ? (
          <p className="muted empty">لا يوجد سجل حالات بعد.</p>
        ) : (
          <div className="milestones">
            {statusHistory.map((h) => (
              <div className="timeline-row" key={h.id}>
                <div>
                  <strong>
                    {h.previous_status
                      ? `${PORTFOLIO_STATUS_LABEL[h.previous_status]} ← ${PORTFOLIO_STATUS_LABEL[h.new_status]}`
                      : `الحالة الابتدائية: ${PORTFOLIO_STATUS_LABEL[h.new_status]}`}
                  </strong>
                  {h.reason ? <p className="muted">{h.reason}</p> : null}
                </div>
                <time>{formatDate(h.changed_at)}</time>
              </div>
            ))}
          </div>
        )}
      </section>
    </section>
  );
}

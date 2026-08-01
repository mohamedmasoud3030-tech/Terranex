import { FileText, HandCoins, Pencil, ReceiptText, Trash2, Users } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import { formatEgp } from '../../core/lib/profitability';
import type {
  Distribution,
  DistributionAllocation,
  Document,
  EquityChangeEvent,
  Obligation,
  Partner,
  PartnerLedgerEntry,
  PartnerLedgerEntryType,
  Project,
  ProjectPartner,
  Transaction,
} from '../../core/types/domain';
import { queryObligationAging } from '../finance/obligationQueries';
import {
  calculatePartnerLedgerSummary,
  decorateLedgerEntries,
  getPartnerDistributionPosition,
} from '../ownership/model';
import { partnerHandoff, type PortfolioHandoff } from './contracts';

export function PartnerWorkspaceView({
  partner,
  projects,
  projectPartners,
  transactions,
  obligations,
  documents,
  equityChangeEvents = [],
  partnerLedgerEntries = [],
  distributions = [],
  distributionAllocations = [],
  locale,
  embedded = false,
  onEdit,
  onDelete,
  onOpenProject,
  onManualLedgerEntry,
  onHandoff,
}: {
  partner: Partner;
  projects: Project[];
  projectPartners: ProjectPartner[];
  transactions: Transaction[];
  obligations: Obligation[];
  documents: Document[];
  equityChangeEvents?: EquityChangeEvent[];
  partnerLedgerEntries?: PartnerLedgerEntry[];
  distributions?: Distribution[];
  distributionAllocations?: DistributionAllocation[];
  locale: 'ar' | 'en';
  embedded?: boolean;
  onEdit?: () => void;
  onDelete?: () => void;
  onOpenProject?: (project: Project) => void;
  onManualLedgerEntry?: () => void;
  onHandoff?: (handoff: PortfolioHandoff) => void;
}) {
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const links = projectPartners.filter((link) => link.partner_id === partner.id);
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const partnerTransactions = transactions.filter((transaction) => transaction.partner_id === partner.id);
  const partnerObligations = obligations.filter((obligation) => obligation.partner_id === partner.id);
  const partnerDocuments = documents.filter((document) => document.partner_id === partner.id);
  const [ledgerProject, setLedgerProject] = useState<string | 'all'>('all');
  const [ledgerType, setLedgerType] = useState<PartnerLedgerEntryType | 'all'>('all');
  const [ledgerStatus, setLedgerStatus] = useState<'all' | 'active' | 'reversal'>('all');
  const [ledgerFrom, setLedgerFrom] = useState('');
  const [ledgerTo, setLedgerTo] = useState('');
  const exposure = queryObligationAging(obligations, {
    as_of: new Date().toISOString().slice(0, 10),
    partner_id: partner.id,
  }).totals;
  const partnerLedger = useMemo(() => decorateLedgerEntries(
    partnerLedgerEntries
      .filter((entry) => entry.partner_id === partner.id)
      .filter((entry) => ledgerProject === 'all' || entry.project_id === ledgerProject)
      .filter((entry) => ledgerType === 'all' || entry.entry_type === ledgerType)
      .filter((entry) => !ledgerFrom || entry.posting_date >= ledgerFrom)
      .filter((entry) => !ledgerTo || entry.posting_date <= ledgerTo),
  ).filter((entry) => ledgerStatus === 'all' || (ledgerStatus === 'reversal' ? entry.entry_type === 'reversal' : entry.entry_type !== 'reversal')),
    [ledgerFrom, ledgerProject, ledgerStatus, ledgerTo, ledgerType, partner.id, partnerLedgerEntries],
  );
  const ledgerSummary = calculatePartnerLedgerSummary(partnerLedgerEntries.filter((entry) => entry.partner_id === partner.id));
  const distributionPosition = getPartnerDistributionPosition(partner.id, distributionAllocations, partnerLedgerEntries);
  const partnerDistributionIds = new Set(distributionAllocations.filter((allocation) => allocation.partner_id === partner.id).map((allocation) => allocation.distribution_id));
  const partnerDistributions = distributions.filter((distribution) => partnerDistributionIds.has(distribution.id));
  const ownershipTimeline = equityChangeEvents
    .filter((event) => event.partner_id === partner.id)
    .sort((a, b) => b.effective_date.localeCompare(a.effective_date));

  function entryTypeLabel(type: PartnerLedgerEntryType) {
    const labels: Record<PartnerLedgerEntryType, string> = {
      capital_contribution: label('مساهمة رأسمالية', 'Capital contribution'),
      withdrawal: label('سحب', 'Withdrawal'),
      distribution_entitlement: label('استحقاق توزيع', 'Distribution entitlement'),
      distribution_payment: label('دفعة توزيع', 'Distribution payment'),
      correction: label('تصحيح', 'Correction'),
      reversal: label('عكس', 'Reversal'),
    };
    return labels[type];
  }

  return (
    <article className="space-y-5" aria-labelledby={`partner-${partner.id}-title`}>
      <Card>
        <CardContent className="p-5">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-primary">
                {partner.category === 'equity_partner' ? label('شريك ملكية', 'Equity partner') : label('طرف تعامل', 'Counterparty')}
              </p>
              <h2 id={`partner-${partner.id}-title`} className={embedded ? 'mt-1 text-2xl font-extrabold' : 'mt-1 text-3xl font-extrabold'}>
                {locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar}
              </h2>
              <p className="mt-2 text-sm text-muted-foreground">
                {[partner.counterparty_role, partner.phone, partner.email].filter(Boolean).join(' · ') || label('لا توجد بيانات اتصال إضافية.', 'No additional contact details.')}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {onEdit && <Button variant="secondary" size="sm" onClick={onEdit}><Pencil className="h-4 w-4" /> {label('تعديل', 'Edit')}</Button>}
              {onDelete && <Button variant="danger" size="sm" onClick={onDelete}><Trash2 className="h-4 w-4" /> {label('حذف', 'Delete')}</Button>}
              <Button variant="secondary" size="sm" onClick={() => onHandoff?.(partnerHandoff(partner.id, 'open-obligations'))}><ReceiptText className="h-4 w-4" /> {label('الذمم', 'Obligations')}</Button>
              {onManualLedgerEntry && <Button variant="secondary" size="sm" onClick={onManualLedgerEntry}><HandCoins className="h-4 w-4" /> {label('قيد شريك', 'Ledger entry')}</Button>}
              <Button size="sm" onClick={() => onHandoff?.(partnerHandoff(partner.id, 'open-statement'))}>{label('كشف الحساب', 'Statement')}</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4">
        <Metric label={label('مدين لنا', 'Receivable')} value={`${formatEgp(exposure.receivable_egp, true)} EGP`} />
        <Metric label={label('ندين له', 'Payable')} value={`${formatEgp(exposure.payable_egp, true)} EGP`} />
        <Metric label={label('رصيد الشريك', 'Partner balance')} value={`${formatEgp(ledgerSummary.current_balance_egp, true)} EGP`} />
        <Metric label={label('توزيعات غير مدفوعة', 'Unpaid distributions')} value={`${formatEgp(distributionPosition.unpaid_egp, true)} EGP`} />
      </div>

      <section>
        <SectionTitle title={label('المشاريع والعلاقات', 'Projects and relationships')} description={label('نسب الملكية الفعلية وسريانها.', 'Actual equity percentages and effective dates.')} />
        {links.length === 0 ? (
          <EmptyState title={label('لا توجد مشاريع مرتبطة', 'No linked projects')} description={label('هذا الشريك غير مربوط بأي مشروع حاليًا.', 'This partner is not linked to a project.')} icon={Users} />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {links.map((link) => {
              const project = projectById.get(link.project_id);
              return (
                <button key={link.id} type="button" disabled={!project} onClick={() => project && onOpenProject?.(project)} className="min-h-11 rounded-2xl text-start disabled:opacity-60">
                  <Card className="h-full hover:border-primary/40">
                    <CardContent>
                      <div className="flex justify-between gap-3">
                        <p className="font-extrabold">{project ? (locale === 'ar' ? project.name_ar : project.name_en || project.name_ar) : label('مشروع غير موجود', 'Missing project')}</p>
                        <strong className="text-primary">{link.equity_pct}%</strong>
                      </div>
                      <p className="mt-2 text-xs text-muted-foreground">
                        {label('ساري من', 'Effective from')} {link.effective_from}
                        {link.effective_to ? ` · ${label('حتى', 'to')} ${link.effective_to} · ${label('غير نشط', 'inactive')}` : ` · ${label('نشط', 'active')}`}
                      </p>
                      <p className="mt-1 text-xs text-muted-foreground">{label('حالة المشروع', 'Project status')}: {project?.status ?? '—'}</p>
                    </CardContent>
                  </Card>
                </button>
              );
            })}
          </div>
        )}
      </section>

      <section>
        <SectionTitle title={label('ملخص مركز الشريك', 'Partner position summary')} description={label('تفصل الأرقام بين رأس المال والسحوبات والاستحقاقات والمدفوعات والعكوسات.', 'Totals are separated across capital, withdrawals, entitlements, payments, and reversals.')} />
        <div className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4">
          <Metric label={label('مساهمات رأسمالية', 'Capital contributed')} value={`${formatEgp(ledgerSummary.capital_contributed_egp, true)} EGP`} />
          <Metric label={label('سحوبات', 'Withdrawals')} value={`${formatEgp(ledgerSummary.withdrawals_egp, true)} EGP`} />
          <Metric label={label('استحقاقات أرباح', 'Profit entitlements')} value={`${formatEgp(ledgerSummary.profit_entitlements_egp, true)} EGP`} />
          <Metric label={label('مدفوعات', 'Payments made')} value={`${formatEgp(ledgerSummary.payments_made_egp, true)} EGP`} />
          <Metric label={label('عكوسات ظاهرة', 'Visible reversals')} value={`${formatEgp(ledgerSummary.reversals_egp, true)} EGP`} />
          <Metric label={label('الرصيد الحالي', 'Current balance')} value={`${formatEgp(ledgerSummary.current_balance_egp, true)} EGP`} />
          <Metric label={label('موزع غير مدفوع', 'Distributed unpaid')} value={`${formatEgp(distributionPosition.unpaid_egp, true)} EGP`} />
          <Metric label={label('توزيعات مدفوعة', 'Paid distributions')} value={`${formatEgp(distributionPosition.paid_egp, true)} EGP`} />
        </div>
      </section>

      <section>
        <SectionTitle title={label('سجل الشريك المالي', 'Partner ledger')} description={label('قيود غير قابلة للحذف مع إظهار العكوسات وأثرها النشط.', 'Immutable entries with reversals and active financial effect visible.')} />
        <div className="mb-3 grid gap-3 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2 xl:grid-cols-5">
          <select aria-label={label('فلتر المشروع', 'Project filter')} value={ledgerProject} onChange={(event) => setLedgerProject(event.target.value as string | 'all')} className="min-h-11 rounded-xl border bg-card px-3 text-sm">
            <option value="all">{label('كل المشاريع', 'All projects')}</option>
            {links.map((link) => {
              const project = projectById.get(link.project_id);
              return <option key={link.id} value={link.project_id}>{project ? (locale === 'ar' ? project.name_ar : project.name_en || project.name_ar) : link.project_id}</option>;
            })}
          </select>
          <select aria-label={label('نوع القيد', 'Entry type')} value={ledgerType} onChange={(event) => setLedgerType(event.target.value as PartnerLedgerEntryType | 'all')} className="min-h-11 rounded-xl border bg-card px-3 text-sm">
            <option value="all">{label('كل الأنواع', 'All types')}</option>
            {(['capital_contribution','withdrawal','distribution_entitlement','distribution_payment','correction','reversal'] as PartnerLedgerEntryType[]).map((type) => <option key={type} value={type}>{entryTypeLabel(type)}</option>)}
          </select>
          <select aria-label={label('حالة القيد', 'Entry status')} value={ledgerStatus} onChange={(event) => setLedgerStatus(event.target.value as 'all' | 'active' | 'reversal')} className="min-h-11 rounded-xl border bg-card px-3 text-sm">
            <option value="all">{label('الكل', 'All')}</option>
            <option value="active">{label('أثر نشط', 'Active effect')}</option>
            <option value="reversal">{label('عكوسات', 'Reversals')}</option>
          </select>
          <input aria-label={label('من تاريخ القيد', 'Ledger from date')} type="date" value={ledgerFrom} onChange={(event) => setLedgerFrom(event.target.value)} className="min-h-11 rounded-xl border bg-card px-3 text-sm" />
          <input aria-label={label('إلى تاريخ القيد', 'Ledger to date')} type="date" value={ledgerTo} onChange={(event) => setLedgerTo(event.target.value)} className="min-h-11 rounded-xl border bg-card px-3 text-sm" />
        </div>
        {partnerLedger.length === 0 ? (
          <EmptyState title={label('لا توجد قيود شريك', 'No partner ledger entries')} description={label('سجل مساهمة أو سحب أو دفعة من زر قيد شريك.', 'Record a contribution, withdrawal, or payment from the Ledger entry action.')} />
        ) : (
          <Card>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <caption className="sr-only">{label('قيود سجل الشريك المالي', 'Partner ledger entries')}</caption>
                <thead><tr className="border-b text-xs text-muted-foreground"><th className="p-2 text-start">{label('التاريخ', 'Date')}</th><th className="p-2 text-start">{label('المشروع', 'Project')}</th><th className="p-2 text-start">{label('النوع', 'Type')}</th><th className="p-2 text-end">{label('المبلغ', 'Amount')}</th><th className="p-2 text-end">{label('الأثر', 'Effect')}</th><th className="p-2 text-start">{label('المرجع', 'Reference')}</th></tr></thead>
                <tbody>
                  {partnerLedger.map((entry) => {
                    const project = projectById.get(entry.project_id);
                    return (
                      <tr key={entry.id} className="border-b last:border-b-0">
                        <td className="p-2">{entry.posting_date}</td>
                        <td className="p-2">{project ? (locale === 'ar' ? project.name_ar : project.name_en || project.name_ar) : entry.project_id}</td>
                        <td className="p-2">{entryTypeLabel(entry.entry_type)}{entry.is_reversed_original ? ` · ${label('معكوس', 'reversed')}` : ''}</td>
                        <td className="p-2 text-end">{entry.amount.toLocaleString()} {entry.currency}</td>
                        <td className={`p-2 text-end font-bold ${entry.active_effect_egp < 0 ? 'text-danger' : entry.active_effect_egp > 0 ? 'text-success' : 'text-muted-foreground'}`}>{formatEgp(entry.active_effect_egp)} EGP</td>
                        <td className="p-2 text-xs text-muted-foreground">{entry.related_distribution_id ?? entry.related_equity_event_id ?? entry.reversal_of_id ?? entry.supporting_document_id ?? '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        )}
      </section>

      <section>
        <SectionTitle title={label('توزيعات الشريك', 'Partner distributions')} description={label('المبالغ المجمدة والمدفوعة وغير المدفوعة حسب تخصيصات التوزيع.', 'Frozen allocations, paid amounts, and unpaid position by distribution.')} />
        {partnerDistributions.length === 0 ? (
          <EmptyState title={label('لا توجد توزيعات', 'No distributions')} description={label('تظهر هنا التوزيعات التي تشمل هذا الشريك.', 'Distributions that include this partner appear here.')} />
        ) : (
          <Card>
            <div className="divide-y divide-border">
              {partnerDistributions.map((distribution) => (
                <div key={distribution.id} className="grid gap-2 px-4 py-3 text-sm sm:grid-cols-4">
                  <strong>{distribution.distribution_date}</strong>
                  <span>{projectById.get(distribution.project_id)?.name_ar ?? distribution.project_id}</span>
                  <span>{label('ملكية كما في', 'Ownership as of')} {distribution.ownership_as_of_date}</span>
                  <span className="font-bold">{formatEgp(distribution.total_amount_egp)} EGP · {distribution.status}</span>
                </div>
              ))}
            </div>
          </Card>
        )}
      </section>

      {ownershipTimeline.length > 0 && (
        <section>
          <SectionTitle title={label('تاريخ ملكية الشريك', 'Partner ownership history')} description={label('كل دخول أو زيادة أو تخفيض أو خروج عبر المشاريع.', 'Entries, increases, decreases, and exits across projects.')} />
          <Card><div className="divide-y divide-border">{ownershipTimeline.slice(0, 10).map((event) => <div key={event.id} className="px-4 py-3 text-sm"><strong>{event.effective_date} · {event.change_type}</strong><p className="text-xs text-muted-foreground">{projectById.get(event.project_id)?.name_ar ?? event.project_id} · {event.previous_pct}% → {event.new_pct}% · {event.reason ?? '—'}</p></div>)}</div></Card>
        </section>
      )}

      <section>
        <SectionTitle title={label('الذمم المفتوحة', 'Open obligations')} description={label('الرصيد المتبقي لكل ذمة دون إخفاء السجلات المغلقة من المصدر.', 'Outstanding balance for each obligation without deleting history.')} />
        {partnerObligations.length === 0 ? (
          <EmptyState title={label('لا توجد ذمم', 'No obligations')} description={label('لا توجد التزامات مرتبطة بهذا الطرف.', 'No obligations are linked to this party.')} />
        ) : (
          <Card>
            <div className="divide-y divide-border">
              {partnerObligations.map((obligation) => (
                <div key={obligation.id} className="flex min-h-11 items-center justify-between gap-3 px-4 py-3 text-sm">
                  <span>
                    <strong>{obligation.direction === 'receivable' ? label('مدينة لنا', 'Receivable') : label('دائنة علينا', 'Payable')}</strong>
                    <span className="block text-xs text-muted-foreground">{obligation.status} · {obligation.due_date ?? label('دون استحقاق', 'No due date')}</span>
                  </span>
                  <strong>{formatEgp(Math.max(0, obligation.amount_egp - obligation.amount_settled_egp), true)} EGP</strong>
                </div>
              ))}
            </div>
          </Card>
        )}
      </section>

      <section>
        <SectionTitle title={label('المعاملات', 'Transactions')} description={label('الحركة المالية المرتبطة مباشرة بالطرف.', 'Financial activity linked directly to the party.')} />
        {partnerTransactions.length === 0 ? (
          <EmptyState title={label('لا توجد معاملات', 'No transactions')} description={label('لم تُسجل معاملات لهذا الطرف.', 'No transactions are recorded for this party.')} />
        ) : (
          <Card>
            <div className="divide-y divide-border">
              {partnerTransactions.map((transaction) => (
                <div key={transaction.id} className="flex min-h-11 items-center justify-between gap-3 px-4 py-3 text-sm">
                  <span className="min-w-0">
                    <strong className="block truncate">{transaction.description || transaction.category}</strong>
                    <span className="text-xs text-muted-foreground">{transaction.transaction_date}</span>
                  </span>
                  <strong className={transaction.direction === 'income' ? 'text-success' : 'text-danger'}>
                    {transaction.direction === 'income' ? '+' : '−'}{formatEgp(transaction.amount_egp, true)} EGP
                  </strong>
                </div>
              ))}
            </div>
          </Card>
        )}
      </section>

      <section>
        <SectionTitle title={label('المستندات', 'Documents')} description={label('الدليل المرتبط بالطرف.', 'Evidence linked to the party.')} />
        {partnerDocuments.length === 0 ? (
          <EmptyState title={label('لا توجد مستندات', 'No documents')} description={label('يمكن إضافة مستند من سياق هذا الطرف.', 'Attach a document from this party context.')} />
        ) : (
          <Card>
            <div className="divide-y divide-border">
              {partnerDocuments.map((document) => (
                <div key={document.id} className="flex min-h-11 items-center gap-3 px-4 py-3">
                  <FileText className="h-5 w-5 text-muted-foreground" />
                  <span className="min-w-0">
                    <strong className="block truncate text-sm">{locale === 'ar' ? document.title_ar : document.title_en || document.title_ar}</strong>
                    <span className="text-xs text-muted-foreground">{document.type}</span>
                  </span>
                </div>
              ))}
            </div>
          </Card>
        )}
      </section>
    </article>
  );
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return <Card><CardContent><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 break-words text-xl font-extrabold">{value}</p></CardContent></Card>;
}

function SectionTitle({ title, description }: { title: string; description: string }) {
  return <CardHeader className="mb-3 px-0"><h3 className="text-lg font-extrabold">{title}</h3><p className="mt-1 text-sm text-muted-foreground">{description}</p></CardHeader>;
}

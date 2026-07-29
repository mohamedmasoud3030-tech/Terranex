import { FileText, Pencil, ReceiptText, Trash2, Users } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import { formatEgp } from '../../core/lib/profitability';
import type {
  Document,
  Obligation,
  Partner,
  Project,
  ProjectPartner,
  Transaction,
} from '../../core/types/domain';
import { queryObligationAging } from '../finance/obligationQueries';
import { partnerHandoff, type PortfolioHandoff } from './contracts';

export function PartnerWorkspaceView({
  partner,
  projects,
  projectPartners,
  transactions,
  obligations,
  documents,
  locale,
  embedded = false,
  onEdit,
  onDelete,
  onOpenProject,
  onHandoff,
}: {
  partner: Partner;
  projects: Project[];
  projectPartners: ProjectPartner[];
  transactions: Transaction[];
  obligations: Obligation[];
  documents: Document[];
  locale: 'ar' | 'en';
  embedded?: boolean;
  onEdit?: () => void;
  onDelete?: () => void;
  onOpenProject?: (project: Project) => void;
  onHandoff?: (handoff: PortfolioHandoff) => void;
}) {
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const links = projectPartners.filter((link) => link.partner_id === partner.id);
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const partnerTransactions = transactions.filter((transaction) => transaction.partner_id === partner.id);
  const partnerObligations = obligations.filter((obligation) => obligation.partner_id === partner.id);
  const partnerDocuments = documents.filter((document) => document.partner_id === partner.id);
  const exposure = queryObligationAging(obligations, {
    as_of: new Date().toISOString().slice(0, 10),
    partner_id: partner.id,
  }).totals;

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
              <Button size="sm" onClick={() => onHandoff?.(partnerHandoff(partner.id, 'open-statement'))}>{label('كشف الحساب', 'Statement')}</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4">
        <Metric label={label('مدين لنا', 'Receivable')} value={`${formatEgp(exposure.receivable_egp, true)} EGP`} />
        <Metric label={label('ندين له', 'Payable')} value={`${formatEgp(exposure.payable_egp, true)} EGP`} />
        <Metric label={label('المشاريع', 'Projects')} value={links.length} />
        <Metric label={label('المستندات', 'Documents')} value={partnerDocuments.length} />
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
                      <p className="mt-2 text-xs text-muted-foreground">{label('ساري من', 'Effective from')} {link.effective_from}</p>
                    </CardContent>
                  </Card>
                </button>
              );
            })}
          </div>
        )}
      </section>

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

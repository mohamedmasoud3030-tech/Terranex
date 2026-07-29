import { FilePlus2, Pencil, ReceiptText, Route, Stethoscope } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { EntityInspectorDrawer } from '../../components/ui/EntityInspectorDrawer';
import { formatEgp } from '../../core/lib/profitability';
import { queryObligationAging } from '../finance/obligationQueries';
import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  ProjectPartner,
  Transaction,
} from '../../core/types/domain';
import { assetHandoff, partnerHandoff, projectHandoff, type PortfolioHandoff } from './contracts';

export type InspectedEntity =
  | { kind: 'project'; value: Project }
  | { kind: 'asset'; value: Asset }
  | { kind: 'partner'; value: Partner };

export function PortfolioInspector({
  entity,
  projects,
  assets,
  partners,
  projectPartners,
  transactions,
  obligations,
  documents,
  events,
  locale,
  onClose,
  onEdit,
  onOpenProject,
  onHandoff,
}: {
  entity: InspectedEntity | null;
  projects: Project[];
  assets: Asset[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  transactions: Transaction[];
  obligations: Obligation[];
  documents: Document[];
  events: OperationalEvent[];
  locale: 'ar' | 'en';
  onClose: () => void;
  onEdit: (entity: InspectedEntity) => void;
  onOpenProject: (project: Project) => void;
  onHandoff?: (handoff: PortfolioHandoff) => void;
}) {
  if (!entity) return null;
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const partnerById = new Map(partners.map((partner) => [partner.id, partner]));

  if (entity.kind === 'project') {
    const project = entity.value;
    const relatedAssets = assets.filter((asset) => asset.project_id === project.id);
    const relatedLinks = projectPartners.filter((link) => link.project_id === project.id);
    const relatedDocuments = documents.filter((document) => document.project_id === project.id);
    const relatedEvents = events.filter((event) => event.project_id === project.id);
    return (
      <EntityInspectorDrawer
        open
        onOpenChange={(open) => { if (!open) onClose(); }}
        title={locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}
        description={`${project.sector_id} · ${project.status}`}
        closeLabel={label('إغلاق العرض السريع', 'Close quick view')}
        relationshipsLabel={label('العلاقات', 'Relationships')}
        activityLabel={label('آخر النشاط', 'Recent activity')}
        fullWorkspaceLink={{
          label: label('فتح مساحة المشروع', 'Open project workspace'),
          href: `/portfolio/projects/${project.id}`,
        }}
        summary={
          <div className="grid grid-cols-2 gap-3">
            <Summary label={label('الأصول', 'Assets')} value={relatedAssets.length} />
            <Summary label={label('شركاء الملكية', 'Equity partners')} value={relatedLinks.length} />
            <Summary label={label('المستندات', 'Documents')} value={relatedDocuments.length} />
            <Summary label={label('الأحداث', 'Events')} value={relatedEvents.length} />
          </div>
        }
        relationships={
          <div className="space-y-2">
            {relatedLinks.length === 0 && <p className="text-sm text-muted-foreground">{label('لا توجد علاقات ملكية.', 'No equity relationships.')}</p>}
            {relatedLinks.map((link) => (
              <div key={link.id} className="flex min-h-11 items-center justify-between rounded-xl border px-3 text-sm">
                <span>{partnerById.get(link.partner_id)?.name_ar ?? label('شريك غير موجود', 'Missing partner')}</span>
                <strong>{link.equity_pct}%</strong>
              </div>
            ))}
          </div>
        }
        activity={<Timeline items={relatedEvents.map((event) => ({ id: event.id, date: event.event_date, text: event.description || event.type }))} empty={label('لا يوجد نشاط تشغيلي.', 'No operational activity.')} />}
        actions={
          <>
            <Button variant="secondary" size="sm" onClick={() => onEdit(entity)}><Pencil className="h-4 w-4" /> {label('تعديل', 'Edit')}</Button>
            <Button variant="secondary" size="sm" onClick={() => onHandoff?.(projectHandoff(project.id, project.sector_id, 'attach-document'))}><FilePlus2 className="h-4 w-4" /> {label('مستند', 'Document')}</Button>
            <Button size="sm" onClick={() => onOpenProject(project)}><Route className="h-4 w-4" /> {label('فتح', 'Open')}</Button>
          </>
        }
      />
    );
  }

  if (entity.kind === 'asset') {
    const asset = entity.value;
    const project = projectById.get(asset.project_id);
    const relatedTransactions = transactions.filter((transaction) => transaction.asset_id === asset.id);
    const relatedDocuments = documents.filter((document) => document.asset_id === asset.id);
    const relatedEvents = events.filter((event) => event.asset_id === asset.id);
    return (
      <EntityInspectorDrawer
        open
        onOpenChange={(open) => { if (!open) onClose(); }}
        title={locale === 'ar' ? asset.name_ar : asset.name_en || asset.name_ar}
        description={`${asset.type} · ${asset.status}`}
        closeLabel={label('إغلاق عرض الأصل', 'Close asset view')}
        relationshipsLabel={label('العلاقات', 'Relationships')}
        activityLabel={label('آخر الأحداث', 'Recent events')}
        summary={
          <div className="grid grid-cols-2 gap-3">
            <Summary label={label('القيمة الحالية', 'Current value')} value={`${formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp, true)} EGP`} />
            <Summary label={label('الكمية الأساسية', 'Base quantity')} value={`${asset.quantity ?? '—'} ${asset.unit ?? ''}`} />
            <Summary label={label('المعاملات', 'Transactions')} value={relatedTransactions.length} />
            <Summary label={label('المستندات', 'Documents')} value={relatedDocuments.length} />
          </div>
        }
        relationships={
          <button type="button" disabled={!project} onClick={() => project && onOpenProject(project)} className="min-h-11 w-full rounded-xl border px-3 text-start text-sm font-semibold disabled:opacity-60">
            {label('المشروع', 'Project')}: {project ? (locale === 'ar' ? project.name_ar : project.name_en || project.name_ar) : label('غير موجود', 'Missing')}
          </button>
        }
        activity={<Timeline items={relatedEvents.map((event) => ({ id: event.id, date: event.event_date, text: event.description || event.type }))} empty={label('لا توجد أحداث مسجلة.', 'No recorded events.')} />}
        actions={
          <>
            <Button variant="secondary" size="sm" onClick={() => onEdit(entity)}><Pencil className="h-4 w-4" /> {label('تعديل', 'Edit')}</Button>
            {asset.sector_id !== 'real-estate' && (
              <Button variant="secondary" size="sm" onClick={() => onHandoff?.(assetHandoff(asset.project_id, asset.id, asset.sector_id, 'create-event'))}><Stethoscope className="h-4 w-4" /> {label('حدث', 'Event')}</Button>
            )}
            <Button size="sm" onClick={() => onHandoff?.(assetHandoff(asset.project_id, asset.id, asset.sector_id, 'create-transaction'))}><ReceiptText className="h-4 w-4" /> {label('معاملة', 'Transaction')}</Button>
          </>
        }
      />
    );
  }

  const partner = entity.value;
  const links = projectPartners.filter((link) => link.partner_id === partner.id);
  const partnerTransactions = transactions.filter((transaction) => transaction.partner_id === partner.id);
  const partnerDocuments = documents.filter((document) => document.partner_id === partner.id);
  const exposure = queryObligationAging(obligations, {
    as_of: new Date().toISOString().slice(0, 10),
    partner_id: partner.id,
  }).totals;
  const openReceivable = exposure.receivable_egp;
  const openPayable = exposure.payable_egp;
  return (
    <EntityInspectorDrawer
      open
      onOpenChange={(open) => { if (!open) onClose(); }}
      title={locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar}
      description={partner.category === 'equity_partner' ? label('شريك ملكية', 'Equity partner') : label('طرف تعامل', 'Counterparty')}
      closeLabel={label('إغلاق عرض الشريك', 'Close partner view')}
      relationshipsLabel={label('المشاريع المرتبطة', 'Linked projects')}
      activityLabel={label('آخر المعاملات', 'Recent transactions')}
      fullWorkspaceLink={{ label: label('فتح مساحة الشريك', 'Open partner workspace'), href: `/portfolio/partners/${partner.id}` }}
      summary={
        <div className="grid grid-cols-2 gap-3">
          <Summary label={label('مدين لنا', 'Receivable')} value={`${formatEgp(openReceivable, true)} EGP`} />
          <Summary label={label('ندين له', 'Payable')} value={`${formatEgp(openPayable, true)} EGP`} />
          <Summary label={label('المعاملات', 'Transactions')} value={partnerTransactions.length} />
          <Summary label={label('المستندات', 'Documents')} value={partnerDocuments.length} />
        </div>
      }
      relationships={
        <div className="space-y-2">
          {links.length === 0 && <p className="text-sm text-muted-foreground">{label('لا توجد مشاريع مرتبطة.', 'No linked projects.')}</p>}
          {links.map((link) => {
            const project = projectById.get(link.project_id);
            return (
              <button key={link.id} type="button" disabled={!project} onClick={() => project && onOpenProject(project)} className="flex min-h-11 w-full items-center justify-between rounded-xl border px-3 text-start text-sm disabled:opacity-60">
                <span>{project?.name_ar ?? label('مشروع غير موجود', 'Missing project')}</span>
                <strong>{link.equity_pct}%</strong>
              </button>
            );
          })}
        </div>
      }
      activity={<Timeline items={partnerTransactions.map((transaction) => ({ id: transaction.id, date: transaction.transaction_date, text: transaction.description || transaction.category }))} empty={label('لا توجد معاملات.', 'No transactions.')} />}
      actions={
        <>
          <Button variant="secondary" size="sm" onClick={() => onEdit(entity)}><Pencil className="h-4 w-4" /> {label('تعديل', 'Edit')}</Button>
          <Button variant="secondary" size="sm" onClick={() => onHandoff?.(partnerHandoff(partner.id, 'open-obligations'))}><ReceiptText className="h-4 w-4" /> {label('الذمم', 'Obligations')}</Button>
          <Button size="sm" onClick={() => onHandoff?.(partnerHandoff(partner.id, 'open-statement'))}>{label('كشف الحساب', 'Statement')}</Button>
        </>
      }
    />
  );
}

function Summary({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-xl border bg-muted/30 p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 break-words font-extrabold">{value}</p>
    </div>
  );
}

function Timeline({
  items,
  empty,
}: {
  items: { id: string; date: string; text: string }[];
  empty: string;
}) {
  if (items.length === 0) return <p className="text-sm text-muted-foreground">{empty}</p>;
  return (
    <div className="space-y-2">
      {[...items].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 8).map((item) => (
        <div key={item.id} className="rounded-xl border px-3 py-2">
          <p className="truncate text-sm font-semibold">{item.text}</p>
          <p className="text-xs text-muted-foreground">{item.date}</p>
        </div>
      ))}
    </div>
  );
}

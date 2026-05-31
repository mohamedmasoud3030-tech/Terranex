import { useRouter } from '@tanstack/react-router';
import { ArrowRight, Building, Trash2, User } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { confirmSafeDeletion, guardPartnerDeletion } from '../../core/lib/deletionGuards';
import { useProjects } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { usePartners } from './hooks';
import { formatEgp } from '../../core/lib/profitability';
import type { PartnerCounterpartyRole } from '../../core/types/domain';

const ROLE_LABELS: Record<PartnerCounterpartyRole, string> = {
  supplier: 'مورد',
  client: 'عميل',
  service_provider: 'مزود خدمة',
  lender: 'ممول',
  government: 'جهة حكومية',
  other: 'أخرى',
};

export function PartnerDetailPage({ partnerId }: { partnerId: string }) {
  const router = useRouter();
  const { partners, deletePartner } = usePartners();
  const { projects } = useProjects();
  const { transactions } = useTransactions();
  const { obligations } = useObligations();
  const partner = partners.find((item) => item.id === partnerId) ?? null;

  if (!partner) {
    return (
      <div className="flex flex-col items-center justify-center gap-4 py-24">
        <p className="text-muted-foreground">الشريك غير موجود</p>
        <Button onClick={() => router.navigate({ to: '/partners' } as any)} variant="secondary">
          <ArrowRight className="h-4 w-4" /> العودة للشركاء
        </Button>
      </div>
    );
  }

  const partnerTransactions = transactions.filter((transaction) => transaction.partner_id === partner.id);
  const partnerObligations = obligations.filter((obligation) => obligation.partner_id === partner.id);
  const currentPartnerId = partner.id;
  const receivable = partnerObligations
    .filter((obligation) => obligation.direction === 'receivable' && obligation.status !== 'settled' && obligation.status !== 'written_off')
    .reduce((sum, obligation) => sum + obligation.amount_egp - obligation.amount_settled_egp, 0);
  const payable = partnerObligations
    .filter((obligation) => obligation.direction === 'payable' && obligation.status !== 'settled' && obligation.status !== 'written_off')
    .reduce((sum, obligation) => sum + obligation.amount_egp - obligation.amount_settled_egp, 0);
  const projectNames = new Map(projects.map((project) => [project.id, project.name_ar]));
  const Icon = partner.category === 'equity_partner' ? Building : User;

  function handleDeletePartner() {
    const guard = guardPartnerDeletion(currentPartnerId);
    if (!guard.canDelete) {
      window.alert(guard.message_ar);
      return;
    }
    if (!confirmSafeDeletion(guard.message_ar)) return;
    deletePartner(currentPartnerId);
    router.navigate({ to: '/partners' } as any);
  }

  return (
    <div className="space-y-6">
      <div>
        <button
          onClick={() => router.navigate({ to: '/partners' } as any)}
          className="mb-3 flex items-center gap-1 text-sm text-muted-foreground transition hover:text-foreground"
        >
          <ArrowRight className="h-4 w-4" /> الشركاء
        </button>
        <Card>
          <CardContent className="p-5">
            <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
              <div className="flex items-start gap-3">
                <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-muted">
                  <Icon className="h-6 w-6 text-muted-foreground" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-foreground">{partner.name_ar}</h1>
                  {partner.name_en && <p className="mt-1 text-sm text-muted-foreground" dir="ltr">{partner.name_en}</p>}
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Badge tone={partner.category === 'equity_partner' ? 'info' : 'neutral'}>
                      {partner.category === 'equity_partner' ? 'شريك ملكية' : 'طرف تعامل'}
                    </Badge>
                    {partner.counterparty_role && <Badge>{ROLE_LABELS[partner.counterparty_role]}</Badge>}
                  </div>
                </div>
              </div>
              <div className="grid gap-2 text-sm md:min-w-64">
                {partner.phone && <p><span className="text-muted-foreground">الهاتف: </span><span dir="ltr">{partner.phone}</span></p>}
                {partner.email && <p><span className="text-muted-foreground">البريد: </span><span dir="ltr">{partner.email}</span></p>}
                {partner.address && <p><span className="text-muted-foreground">العنوان: </span>{partner.address}</p>}
                <Button variant="danger" size="sm" onClick={handleDeletePartner} className="mt-2 w-full md:w-auto">
                  <Trash2 className="h-4 w-4" /> حذف الشريك
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">مدين لنا</p>
            <p className="mt-2 text-2xl font-bold text-success">{formatEgp(receivable, true)} EGP</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">ندين له</p>
            <p className="mt-2 text-2xl font-bold text-danger">{formatEgp(payable, true)} EGP</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">صافي العلاقة</p>
            <p className={`mt-2 text-2xl font-bold ${receivable - payable >= 0 ? 'text-success' : 'text-danger'}`}>
              {formatEgp(receivable - payable, true)} EGP
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardContent>
          <h2 className="mb-4 text-lg font-bold">المعاملات المرتبطة</h2>
          {partnerTransactions.length === 0 ? (
            <EmptyState title="لا توجد معاملات مرتبطة" description="لم يتم تسجيل معاملات لهذا الشريك بعد." />
          ) : (
            <div className="divide-y divide-border">
              {partnerTransactions.map((transaction) => (
                <div key={transaction.id} className="flex flex-col gap-2 py-3 md:flex-row md:items-center md:justify-between">
                  <div>
                    <p className="font-semibold">{transaction.description || 'معاملة مالية'}</p>
                    <p className="text-sm text-muted-foreground">
                      {projectNames.get(transaction.project_id) ?? 'مشروع غير معروف'} · {transaction.transaction_date}
                    </p>
                  </div>
                  <p className={`font-bold ${transaction.direction === 'income' ? 'text-success' : 'text-danger'}`}>
                    {transaction.direction === 'income' ? '+' : '−'}{formatEgp(transaction.amount_egp, true)} EGP
                  </p>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {partner.notes && (
        <Card>
          <CardContent>
            <h2 className="mb-2 text-lg font-bold">ملاحظات</h2>
            <p className="text-sm leading-7 text-muted-foreground">{partner.notes}</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

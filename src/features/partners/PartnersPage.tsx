import { useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import { Plus, User, Building } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { usePartners } from './hooks';
import { useObligations } from '../obligations/hooks';
import { formatEgp } from '../../core/lib/profitability';
import type { PartnerInput } from './storage';
import type { Partner } from '../../core/types/domain';

const ROLES = [
  { id: 'supplier', ar: 'مورد' }, { id: 'client', ar: 'عميل' },
  { id: 'service_provider', ar: 'مزود خدمة' }, { id: 'lender', ar: 'ممول' },
  { id: 'government', ar: 'جهة حكومية' }, { id: 'other', ar: 'أخرى' },
];

function PartnerForm({ onSubmit, onCancel }: { onSubmit: (i: PartnerInput) => void; onCancel: () => void }) {
  const [name_ar, setNameAr] = useState('');
  const [category, setCategory] = useState<Partner['category']>('counterparty');
  const [counterparty_role, setRole] = useState<Partner['counterparty_role']>('supplier');
  const [phone, setPhone] = useState('');
  const [notes, setNotes] = useState('');

  const ic = 'block w-full min-w-0 rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'block text-sm font-medium text-foreground mb-1';

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name_ar.trim()) return;
    onSubmit({ name_ar, category, counterparty_role: category === 'counterparty' ? counterparty_role : undefined, phone: phone || undefined, notes: notes || undefined });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={lc}>الاسم *</label>
          <input className={ic} value={name_ar} onChange={e => setNameAr(e.target.value)} placeholder="شركة الأمل للمقاولات" />
        </div>
        <div>
          <label className={lc}>التصنيف</label>
          <select className={ic} value={category} onChange={e => setCategory(e.target.value as Partner['category'])}>
            <option value="counterparty">طرف تعامل</option>
            <option value="equity_partner">شريك ملكية</option>
          </select>
        </div>
      </div>
      {category === 'counterparty' && (
        <div>
          <label className={lc}>الدور</label>
          <select className={ic} value={counterparty_role} onChange={e => setRole(e.target.value as Partner['counterparty_role'])}>
            {ROLES.map(r => <option key={r.id} value={r.id}>{r.ar}</option>)}
          </select>
        </div>
      )}
      <div>
        <label className={lc}>رقم الهاتف</label>
        <input className={ic} value={phone} onChange={e => setPhone(e.target.value)} placeholder="+20..." dir="ltr" />
      </div>
      <div>
        <label className={lc}>ملاحظات</label>
        <textarea className={ic} rows={2} value={notes} onChange={e => setNotes(e.target.value)} />
      </div>
      <div className="flex flex-col gap-3 sm:flex-row sm:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit">حفظ الشريك</Button>
      </div>
    </form>
  );
}

export function PartnersPage() {
  const router = useRouter();
  const { partners, createPartner } = usePartners();
  const { obligations } = useObligations();
  const [showForm, setShowForm] = useState(false);

  function getBalance(partnerId: string) {
    const partnerObls = obligations.filter(o => o.partner_id === partnerId && o.status !== 'settled' && o.status !== 'written_off');
    const rec = partnerObls.filter(o => o.direction === 'receivable').reduce((s, o) => s + o.amount_egp - o.amount_settled_egp, 0);
    const pay = partnerObls.filter(o => o.direction === 'payable').reduce((s, o) => s + o.amount_egp - o.amount_settled_egp, 0);
    return { rec, pay, net: rec - pay };
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="الشركاء والأطراف"
        description="إدارة جميع الشركاء والأطراف والعلاقات المالية معهم."
      >
        <Button onClick={() => setShowForm(true)}>
          <Plus className="h-4 w-4" /> شريك جديد
        </Button>
      </PageHeader>

      {showForm && (
        <Card>
          <CardContent>
            <h3 className="mb-4 text-base font-semibold">شريك / طرف جديد</h3>
            <PartnerForm onSubmit={p => { createPartner(p); setShowForm(false); }} onCancel={() => setShowForm(false)} />
          </CardContent>
        </Card>
      )}

      {partners.length === 0 ? (
        <EmptyState title="لا توجد بيانات بعد" description="أضف أول سجل لهذا القسم لتبدأ." />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {partners.map(partner => {
            const bal = getBalance(partner.id);
            const Icon = partner.category === 'equity_partner' ? Building : User;
            return (
              <button
                key={partner.id}
                onClick={() => router.navigate({ to: '/partners/$id', params: { id: partner.id } } as any)}
                className="rounded-2xl text-start transition hover:-translate-y-0.5 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                <Card>
                <CardContent className="p-5">
                  <div className="mb-3 flex items-center gap-3">
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-muted">
                      <Icon className="h-5 w-5 text-muted-foreground" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold truncate">{partner.name_ar}</p>
                      <p className="text-xs text-muted-foreground">
                        {partner.category === 'equity_partner' ? 'شريك ملكية' : ROLES.find(r => r.id === partner.counterparty_role)?.ar ?? 'طرف تعامل'}
                      </p>
                    </div>
                  </div>
                  {(bal.rec > 0 || bal.pay > 0) && (
                    <div className="space-y-1.5 rounded-xl border border-border bg-muted/50 p-3">
                      {bal.rec > 0 && (
                        <div className="flex justify-between text-xs">
                          <span className="text-muted-foreground">مدين لنا</span>
                          <span className="font-bold text-success">+{formatEgp(bal.rec, true)} EGP</span>
                        </div>
                      )}
                      {bal.pay > 0 && (
                        <div className="flex justify-between text-xs">
                          <span className="text-muted-foreground">ندين له</span>
                          <span className="font-bold text-danger">−{formatEgp(bal.pay, true)} EGP</span>
                        </div>
                      )}
                    </div>
                  )}
                </CardContent>
                </Card>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

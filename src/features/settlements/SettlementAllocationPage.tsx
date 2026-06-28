import { useMemo, useState } from 'react';
import { CheckCircle2, Split } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { EmptyState } from '../../components/ui/States';
import { formatEgp } from '../../core/lib/profitability';
import { useObligations } from '../obligations/hooks';
import {
  buildSettlementAllocationFormPlans,
  getCompatibleSettleableObligations,
  getObligationRemainingEgp,
  getSettlementAllocationPlanTotal,
} from './allocationForm';
import { usePartners } from '../partners/hooks';
import { useProjects } from '../projects/hooks';
import type { SettlementPaymentMethod } from './types';

export function SettlementAllocationPage() {
  const { obligations, settleObligations } = useObligations();
  const { partners } = usePartners();
  const { projects } = useProjects();
  const [anchorId, setAnchorId] = useState('');
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [settlementDate, setSettlementDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [paymentMethod, setPaymentMethod] = useState<SettlementPaymentMethod>('cash');
  const [referenceNumber, setReferenceNumber] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const settleable = useMemo(
    () => obligations.filter((item) => item.status === 'open' || item.status === 'partial'),
    [obligations],
  );
  const anchor = useMemo(() => settleable.find((item) => item.id === anchorId), [anchorId, settleable]);
  const candidates = useMemo(() => getCompatibleSettleableObligations(anchor, settleable), [anchor, settleable]);
  const previewPlans = useMemo(() => candidates.flatMap((item) => {
    const amount = Number(amounts[item.id]);
    return Number.isFinite(amount) && amount > 0 ? [{ obligation_id: item.id, allocated_amount_egp: amount }] : [];
  }), [amounts, candidates]);
  const total = getSettlementAllocationPlanTotal(previewPlans);

  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'mb-1 block text-sm font-medium text-foreground';

  function partnerName(partnerId: string) {
    return partners.find((item) => item.id === partnerId)?.name_ar ?? partnerId;
  }

  function projectName(projectId?: string) {
    if (!projectId) return 'بدون مشروع';
    return projects.find((item) => item.id === projectId)?.name_ar ?? projectId;
  }

  function selectAnchor(nextId: string) {
    setAnchorId(nextId);
    setAmounts({});
    setError(null);
    setSuccess(null);
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    try {
      const plans = buildSettlementAllocationFormPlans(candidates, amounts);
      const amount = getSettlementAllocationPlanTotal(plans);
      const settlement = settleObligations({
        amount,
        currency: 'EGP',
        fx_rate: 1,
        settlement_date: settlementDate,
        payment_method: paymentMethod,
        reference_number: referenceNumber.trim() || undefined,
        notes: notes.trim() || undefined,
        allocations: plans,
      });
      setAmounts({});
      setReferenceNumber('');
      setNotes('');
      setError(null);
      setSuccess(`تم تسجيل السند ${settlement.reference_number ?? settlement.id} وتوزيعه على ${plans.length} التزامات.`);
    } catch (submissionError) {
      setSuccess(null);
      setError(submissionError instanceof Error ? submissionError.message : 'تعذر تسجيل الدفعة الموزعة.');
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="دفعة موزعة"
        description="سند نقدي واحد يُوزع على التزامات متوافقة للطرف والمشروع والاتجاه نفسه."
      />

      {settleable.length === 0 ? (
        <EmptyState title="لا توجد التزامات قابلة للتسوية" description="أضف التزامات مفتوحة أو جزئية أولاً." />
      ) : (
        <Card>
          <CardContent>
            <form onSubmit={submit} className="space-y-5">
              <div>
                <label className={lc}>التزام مرجعي</label>
                <select className={ic} value={anchorId} onChange={(e) => selectAnchor(e.target.value)}>
                  <option value="">اختر التزاماً لعرض التوزيعات المتوافقة…</option>
                  {settleable.map((obligation) => (
                    <option key={obligation.id} value={obligation.id}>
                      {partnerName(obligation.partner_id)} — {obligation.direction === 'receivable' ? 'مدين' : 'دائن'} — {projectName(obligation.project_id)} — {formatEgp(getObligationRemainingEgp(obligation))} EGP
                    </option>
                  ))}
                </select>
              </div>

              {anchor && (
                <div className="rounded-xl border border-border bg-muted/30 p-3 text-sm">
                  <p className="font-medium">الطرف: {partnerName(anchor.partner_id)}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {anchor.direction === 'receivable' ? 'ذمم مدينة' : 'ذمم دائنة'} — {projectName(anchor.project_id)}. الالتزامات الأخرى غير المتوافقة مستبعدة تلقائياً.
                  </p>
                </div>
              )}

              {candidates.length > 0 && (
                <div className="space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <label className={lc}>التوزيعات</label>
                    <span className="text-sm font-semibold text-primary">إجمالي السند: {formatEgp(total)} EGP</span>
                  </div>
                  <div className="divide-y divide-border rounded-xl border border-border">
                    {candidates.map((obligation) => {
                      const remaining = getObligationRemainingEgp(obligation);
                      return (
                        <div key={obligation.id} className="grid gap-2 p-3 sm:grid-cols-[1fr_11rem] sm:items-center">
                          <div>
                            <p className="text-sm font-medium">{projectName(obligation.project_id)}</p>
                            <p className="text-xs text-muted-foreground">
                              {obligation.due_date ? `الاستحقاق: ${obligation.due_date} — ` : ''}المتبقي: {formatEgp(remaining)} EGP
                            </p>
                          </div>
                          <input
                            type="number"
                            min="0"
                            max={remaining}
                            step="0.01"
                            inputMode="decimal"
                            className={ic}
                            value={amounts[obligation.id] ?? ''}
                            placeholder={`حتى ${formatEgp(remaining)}`}
                            onChange={(e) => setAmounts((current) => ({ ...current, [obligation.id]: e.target.value }))}
                            aria-label={`قيمة توزيع الالتزام ${projectName(obligation.project_id)}`}
                          />
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className={lc}>تاريخ التسوية</label>
                  <input type="date" className={ic} value={settlementDate} onChange={(e) => setSettlementDate(e.target.value)} required />
                </div>
                <div>
                  <label className={lc}>طريقة الدفع</label>
                  <select className={ic} value={paymentMethod} onChange={(e) => setPaymentMethod(e.target.value as SettlementPaymentMethod)}>
                    <option value="cash">نقدي</option>
                    <option value="bank_transfer">تحويل بنكي</option>
                    <option value="cheque">شيك</option>
                    <option value="card">بطاقة</option>
                    <option value="other">أخرى</option>
                  </select>
                </div>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className={lc}>رقم المرجع</label>
                  <input className={ic} value={referenceNumber} onChange={(e) => setReferenceNumber(e.target.value)} />
                </div>
                <div>
                  <label className={lc}>ملاحظات</label>
                  <input className={ic} value={notes} onChange={(e) => setNotes(e.target.value)} />
                </div>
              </div>

              {error && <p className="text-sm text-danger">{error}</p>}
              {success && <p className="flex items-center gap-2 text-sm text-success"><CheckCircle2 className="h-4 w-4" />{success}</p>}

              <div className="flex justify-end">
                <Button type="submit" disabled={!anchor || total <= 0}>
                  <Split className="h-4 w-4" /> تسجيل الدفعة الموزعة
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

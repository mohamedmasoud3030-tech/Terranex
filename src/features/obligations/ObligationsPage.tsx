import { useState } from 'react';
import { Plus, AlertCircle, CheckCircle2, Clock } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { useObligations } from './hooks';
import { usePartners } from '../partners/hooks';
import { useProjects } from '../projects/hooks';
import { formatEgp } from '../../core/lib/profitability';
import type { ObligationInput } from './storage';
import type { Obligation } from '../../core/types/domain';

const STATUS_META: Record<Obligation['status'], { ar: string; tone: 'neutral' | 'positive' | 'warning' | 'negative' | 'info'; Icon: typeof Clock }> = {
  open:        { ar: 'مفتوح',           tone: 'warning', Icon: Clock },
  partial:     { ar: 'جزئي',            tone: 'info',    Icon: Clock },
  settled:     { ar: 'مسدد',            tone: 'positive', Icon: CheckCircle2 },
  disputed:    { ar: 'متنازع',          tone: 'negative',  Icon: AlertCircle },
  written_off: { ar: 'مشطوب',           tone: 'neutral', Icon: AlertCircle },
};

function ObligationForm({
  partners,
  projects,
  onSubmit,
  onCancel,
}: {
  partners: ReturnType<typeof usePartners>['partners'];
  projects: ReturnType<typeof useProjects>['projects'];
  onSubmit: (i: ObligationInput) => void;
  onCancel: () => void;
}) {
  const [direction, setDirection] = useState<Obligation['direction']>('receivable');
  const [partner_id, setPartnerId] = useState('');
  const [project_id, setProjectId] = useState('');
  const [amount, setAmount] = useState('');
  const [due_date, setDueDate] = useState('');
  const [notes, setNotes] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});

  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'block text-sm font-medium text-foreground mb-1';

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const errs: Record<string, string> = {};
    if (!partner_id) errs.partner = 'اختر الطرف';
    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) errs.amount = 'أدخل مبلغاً صحيحاً أكبر من صفر';
    setErrors(errs);
    if (Object.keys(errs).length > 0) return;
    const amountNum = parsedAmount;
    onSubmit({
      direction,
      partner_id,
      project_id: project_id || undefined,
      amount: amountNum,
      currency: 'EGP',
      amount_egp: amountNum,
      due_date: due_date || undefined,
      status: 'open',
      notes: notes || undefined,
    });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex gap-2">
        {(['receivable', 'payable'] as const).map((d) => (
          <button
            key={d}
            type="button"
            onClick={() => setDirection(d)}
            className={`flex-1 rounded-xl border py-2.5 text-sm font-semibold transition ${
              direction === d
                ? d === 'receivable'
                  ? 'border-success bg-success/10 text-success'
                  : 'border-danger bg-danger/10 text-danger'
                : 'border-border text-muted-foreground hover:bg-muted'
            }`}
          >
            {d === 'receivable' ? '← ذمة مدينة (لنا)' : 'ذمة دائنة (علينا) →'}
          </button>
        ))}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={lc}>الطرف *</label>
          <select className={ic} value={partner_id} onChange={(e) => setPartnerId(e.target.value)}>
            <option value="">اختر الطرف…</option>
            {partners.map((p) => <option key={p.id} value={p.id}>{p.name_ar}</option>)}
          </select>
          {errors.partner && <p className="mt-1 text-xs text-danger">{errors.partner}</p>}
        </div>
        <div>
          <label className={lc}>المشروع (اختياري)</label>
          <select className={ic} value={project_id} onChange={(e) => setProjectId(e.target.value)}>
            <option value="">بدون مشروع</option>
            {projects.map((p) => <option key={p.id} value={p.id}>{p.name_ar}</option>)}
          </select>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={lc}>المبلغ (EGP) *</label>
          <input type="number" min="0" step="0.01" className={ic} value={amount} onChange={(e) => setAmount(e.target.value)} />
          {errors.amount && <p className="mt-1 text-xs text-danger">{errors.amount}</p>}
        </div>
        <div>
          <label className={lc}>تاريخ الاستحقاق</label>
          <input type="date" className={ic} value={due_date} onChange={(e) => setDueDate(e.target.value)} />
        </div>
      </div>

      <div>
        <label className={lc}>ملاحظات</label>
        <textarea className={ic} rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </div>

      <div className="flex flex-col gap-3 min-[360px]:flex-row min-[360px]:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit">حفظ الالتزام</Button>
      </div>
    </form>
  );
}

export function ObligationsPage() {
  const { obligations, totalReceivableEgp, totalPayableEgp, createObligation, settleObligation } = useObligations();
  const { partners } = usePartners();
  const { projects } = useProjects();
  const [showForm, setShowForm] = useState(false);
  const [filterDir, setFilterDir] = useState<'all' | 'receivable' | 'payable'>('all');
  const [settleId, setSettleId] = useState<string | null>(null);
  const [settleAmt, setSettleAmt] = useState('');
  const [settleError, setSettleError] = useState<string | null>(null);

  const filtered = filterDir === 'all' ? obligations : obligations.filter((o) => o.direction === filterDir);
  const open = filtered.filter((o) => o.status !== 'settled' && o.status !== 'written_off');
  const closed = filtered.filter((o) => o.status === 'settled' || o.status === 'written_off');

  function getPartnerName(id: string) {
    return partners.find((p) => p.id === id)?.name_ar ?? id;
  }

  function getProjectName(id?: string) {
    if (!id) return null;
    return projects.find((p) => p.id === id)?.name_ar ?? null;
  }

  function handleSettle(id: string) {
    const amt = Number(settleAmt);
    try {
      settleObligation(id, amt);
      setSettleId(null);
      setSettleAmt('');
      setSettleError(null);
    } catch (error) {
      setSettleError(error instanceof Error ? error.message : 'تعذر تسجيل الدفعة.');
    }
  }

  const ic = 'rounded-xl border border-border bg-background px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';

  return (
    <div className="space-y-6">
      <PageHeader
        title="الذمم والالتزامات"
        description="يربط كل سجل بالمال والقطاع والطرف والمستند."
      >
        <Button onClick={() => setShowForm(true)}>
          <Plus className="h-4 w-4" /> التزام جديد
        </Button>
      </PageHeader>

      <div className="grid gap-3 sm:grid-cols-3">
        {[
          { label: 'ذمم مدينة (لنا)', value: totalReceivableEgp, color: 'text-success', border: 'border-success/30 bg-success/5' },
          { label: 'ذمم دائنة (علينا)', value: totalPayableEgp, color: 'text-danger', border: 'border-danger/30 bg-danger/5' },
          { label: 'الصافي لصالحنا', value: totalReceivableEgp - totalPayableEgp, color: (totalReceivableEgp - totalPayableEgp) >= 0 ? 'text-success' : 'text-danger', border: 'border-border' },
        ].map((s) => (
          <Card key={s.label} className={`border ${s.border}`}>
            <CardContent className="p-4">
              <p className="text-xs text-muted-foreground mb-1">{s.label}</p>
              <p className={`text-xl font-bold ${s.color}`}>{formatEgp(s.value)} EGP</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {showForm && (
        <Card>
          <CardContent>
            <h3 className="mb-4 text-base font-semibold">التزام جديد</h3>
            <ObligationForm
              partners={partners}
              projects={projects}
              onSubmit={(i) => { createObligation(i); setShowForm(false); }}
              onCancel={() => setShowForm(false)}
            />
          </CardContent>
        </Card>
      )}

          <div className="flex gap-2 overflow-x-auto pb-1">
        {(['all', 'receivable', 'payable'] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFilterDir(f)}
            className={`rounded-full border px-4 py-1.5 text-sm font-medium transition ${filterDir === f ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted'}`}
          >
            {f === 'all' ? 'الكل' : f === 'receivable' ? 'المدين (لنا)' : 'الدائن (علينا)'}
          </button>
        ))}
      </div>

      {open.length === 0 && closed.length === 0 ? (
        <EmptyState title="لا توجد بيانات بعد" description="أضف أول سجل لهذا القسم لتبدأ." />
      ) : (
        <>
          {open.length > 0 && (
            <div>
              <h3 className="mb-3 text-sm font-semibold text-muted-foreground uppercase tracking-wide">مفتوحة ({open.length})</h3>
              <Card>
                <div className="divide-y divide-border">
                  {open.map((obl) => {
                    const meta = STATUS_META[obl.status];
                    const StatusIcon = meta.Icon;
                    const remaining = obl.amount_egp - obl.amount_settled_egp;
                    const isOverdue = obl.due_date && new Date(obl.due_date) < new Date();

                    return (
                      <div key={obl.id} className="px-4 py-4">
                        <div className="flex items-start justify-between gap-4">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="font-medium">{getPartnerName(obl.partner_id)}</span>
                              <Badge tone={obl.direction === 'receivable' ? 'positive' : 'negative'}>
                                {obl.direction === 'receivable' ? 'مدين' : 'دائن'}
                              </Badge>
                              <Badge tone={meta.tone}>{meta.ar}</Badge>
                              {isOverdue && <Badge tone="negative">متأخر</Badge>}
                            </div>
                            {getProjectName(obl.project_id) && (
                              <p className="mt-0.5 text-xs text-muted-foreground">{getProjectName(obl.project_id)}</p>
                            )}
                            {obl.due_date && (
                              <p className={`mt-0.5 text-xs ${isOverdue ? 'text-danger' : 'text-muted-foreground'}`}>
                                الاستحقاق: {obl.due_date}
                              </p>
                            )}
                          </div>
                          <div className="text-end flex-shrink-0">
                            <p className={`font-bold ${obl.direction === 'receivable' ? 'text-success' : 'text-danger'}`}>
                              {formatEgp(remaining)} EGP
                            </p>
                            {obl.status === 'partial' && (
                              <p className="text-xs text-muted-foreground">من {formatEgp(obl.amount_egp)}</p>
                            )}
                          </div>
                        </div>

                        {settleId === obl.id ? (
                          <div className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center">
                            <input
                              type="number"
                              min="0"
                              max={remaining}
                              step="0.01"
                              className={`${ic} flex-1`}
                              placeholder={`الحد الأقصى ${formatEgp(remaining)}`}
                              value={settleAmt}
                              onChange={(e) => setSettleAmt(e.target.value)}
                            />
                            <Button size="sm" variant="success" onClick={() => handleSettle(obl.id)}>تأكيد</Button>
                            <Button size="sm" variant="secondary" onClick={() => { setSettleId(null); setSettleAmt(''); setSettleError(null); }}>إلغاء</Button>
                            {settleError && <p className="text-xs text-danger sm:basis-full">{settleError}</p>}
                          </div>
                        ) : (
                          <button
                            onClick={() => setSettleId(obl.id)}
                            className="mt-2 text-xs text-primary hover:underline"
                          >
                            تسجيل دفعة
                          </button>
                        )}
                      </div>
                    );
                  })}
                </div>
              </Card>
            </div>
          )}

          {closed.length > 0 && (
            <div>
              <h3 className="mb-3 text-sm font-semibold text-muted-foreground uppercase tracking-wide">مغلقة ({closed.length})</h3>
              <Card>
                <div className="divide-y divide-border">
                  {closed.map((obl) => (
                    <div key={obl.id} className="flex items-center gap-4 px-4 py-3 opacity-60">
                      <CheckCircle2 className="h-4 w-4 text-success flex-shrink-0" />
                      <span className="flex-1 text-sm truncate">{getPartnerName(obl.partner_id)}</span>
                      <span className="text-sm font-medium">{formatEgp(obl.amount_egp)} EGP</span>
                      <Badge tone="positive">مسدد</Badge>
                    </div>
                  ))}
                </div>
              </Card>
            </div>
          )}
        </>
      )}
    </div>
  );
}

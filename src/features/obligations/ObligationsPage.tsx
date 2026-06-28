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
import type { Obligation } from '../../core/types/domain';
import { ObligationForm } from './ObligationForm';
import { useI18n } from '../../core/i18n/context';
import { ExportExcelButton } from '../reports/ExportExcelButton';

const STATUS_META: Record<Obligation['status'], { ar: string; en: string; tone: 'neutral' | 'positive' | 'warning' | 'negative' | 'info'; Icon: typeof Clock }> = {
  open:        { ar: 'مفتوح',    en: 'Open',       tone: 'warning', Icon: Clock },
  partial:     { ar: 'جزئي',     en: 'Partial',    tone: 'info',    Icon: Clock },
  settled:     { ar: 'مسدد',     en: 'Settled',    tone: 'positive', Icon: CheckCircle2 },
  disputed:    { ar: 'متنازع',   en: 'Disputed',   tone: 'negative', Icon: AlertCircle },
  written_off: { ar: 'مشطوب',    en: 'Written off',tone: 'neutral', Icon: AlertCircle },
};

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
        <ExportExcelButton />
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
                  {closed.map((obl) => {
                    const meta = STATUS_META[obl.status];
                    const StatusIcon = meta.Icon;
                    return (
                      <div key={obl.id} className="flex items-center gap-4 px-4 py-3 opacity-60">
                        <StatusIcon className={`h-4 w-4 flex-shrink-0 ${obl.status === 'settled' ? 'text-success' : 'text-muted-foreground'}`} />
                        <span className="flex-1 text-sm truncate">{getPartnerName(obl.partner_id)}</span>
                        <span className="text-sm font-medium">{formatEgp(obl.amount_egp)} EGP</span>
                        <Badge tone={meta.tone}>{meta.ar}</Badge>
                      </div>
                    );
                  })}
                </div>
              </Card>
            </div>
          )}
        </>
      )}
    </div>
  );
}

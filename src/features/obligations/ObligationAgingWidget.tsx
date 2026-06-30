/**
 * ObligationAgingWidget — R4
 * Surfaces the aging buckets from obligationQueries.ts as a visual dashboard widget.
 * ADR-003: queryObligationAging already tested (obligation-aging-query.test.cjs).
 */
import { todayIso } from '../../core/lib/dateUtils';
import { useMemo } from 'react';
import { AlertTriangle, Clock, CheckCircle2, HelpCircle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { formatEgp } from '../../core/lib/profitability';
import { queryObligationAging, type ObligationAgingTotals } from '../finance/obligationQueries';
import type { Obligation } from '../../core/types/domain';

interface ObligationAgingWidgetProps {
  obligations: Obligation[];
  /** ISO date — defaults to today */
  asOf?: string;
}

interface BucketMeta {
  key: keyof ObligationAgingTotals;
  label: string;
  days: string;
  tone: 'safe' | 'warn' | 'danger' | 'muted';
  Icon: typeof Clock;
}

const BUCKETS: BucketMeta[] = [
  { key: 'not_due_egp',       label: 'لم يحن موعده',  days: 'غير متأخر',    tone: 'safe',   Icon: CheckCircle2 },
  { key: 'overdue_1_30_egp',  label: 'متأخر 1–30 يوم', days: '1–30 يوم',   tone: 'warn',   Icon: Clock },
  { key: 'overdue_31_60_egp', label: 'متأخر 31–60',   days: '31–60 يوم',   tone: 'warn',   Icon: AlertTriangle },
  { key: 'overdue_61_90_egp', label: 'متأخر 61–90',   days: '61–90 يوم',   tone: 'danger', Icon: AlertTriangle },
  { key: 'overdue_91_plus_egp',label: 'متأخر +90 يوم', days: '91+ يوم',    tone: 'danger', Icon: AlertTriangle },
  { key: 'undated_egp',       label: 'بلا تاريخ',     days: 'غير محدد',    tone: 'muted',  Icon: HelpCircle },
];

const TONE_CLASS: Record<BucketMeta['tone'], { bar: string; text: string; bg: string }> = {
  safe:   { bar: 'bg-success',     text: 'text-success',  bg: 'bg-success/5 border-success/20' },
  warn:   { bar: 'bg-amber-400',   text: 'text-amber-600', bg: 'bg-amber-50 border-amber-200' },
  danger: { bar: 'bg-danger',      text: 'text-danger',   bg: 'bg-danger/5 border-danger/20' },
  muted:  { bar: 'bg-muted-foreground/30', text: 'text-muted-foreground', bg: 'bg-muted/30 border-border' },
};


export function ObligationAgingWidget({ obligations, asOf }: ObligationAgingWidgetProps) {
  const asOfDate = asOf ?? todayIso();

  const result = useMemo(() =>
    queryObligationAging(obligations, { as_of: asOfDate }),
    [obligations, asOfDate],
  );

  const totalOutstanding = result.totals.outstanding_egp;
  const hasData = totalOutstanding > 0 || result.rows.length > 0;

  if (!hasData) return null;

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between gap-3">
          <div>
            <h3 className="text-sm font-semibold">تقادم الذمم (Aging)</h3>
            <p className="text-xs text-muted-foreground mt-0.5">كما في {asOfDate} — الالتزامات المفتوحة فقط</p>
          </div>
          <div className="text-end">
            <p className="text-xs text-muted-foreground">الإجمالي</p>
            <p className="text-base font-bold">{formatEgp(totalOutstanding, true)} EGP</p>
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-2 pb-4">
        {/* Direction split */}
        <div className="flex gap-3 mb-3">
          <div className="flex-1 rounded-lg border border-success/20 bg-success/5 px-3 py-2 text-center">
            <p className="text-xs text-muted-foreground">مدين (لنا)</p>
            <p className="font-bold text-success">{formatEgp(result.totals.receivable_egp, true)} EGP</p>
          </div>
          <div className="flex-1 rounded-lg border border-danger/20 bg-danger/5 px-3 py-2 text-center">
            <p className="text-xs text-muted-foreground">دائن (علينا)</p>
            <p className="font-bold text-danger">{formatEgp(result.totals.payable_egp, true)} EGP</p>
          </div>
        </div>

        {/* Aging buckets */}
        {BUCKETS.map((bucket) => {
          const amount = result.totals[bucket.key] as number;
          if (amount === 0) return null;
          const pct = totalOutstanding > 0 ? (amount / totalOutstanding) * 100 : 0;
          const tc = TONE_CLASS[bucket.tone];
          const BucketIcon = bucket.Icon;
          return (
            <div key={bucket.key} className={`flex items-center gap-3 rounded-lg border px-3 py-2.5 ${tc.bg}`}>
              <BucketIcon className={`h-4 w-4 flex-shrink-0 ${tc.text}`} />
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-medium truncate">{bucket.label}</span>
                  <span className={`text-sm font-bold flex-shrink-0 ${tc.text}`}>{formatEgp(amount, true)} EGP</span>
                </div>
                {/* Mini progress bar */}
                <div className="mt-1.5 h-1.5 w-full rounded-full bg-black/5">
                  <div
                    className={`h-1.5 rounded-full ${tc.bar} transition-all`}
                    style={{ width: `${Math.min(100, pct)}%` }}
                  />
                </div>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  {pct.toFixed(1)}% من الإجمالي — {bucket.days}
                </p>
              </div>
            </div>
          );
        })}

        {/* Overdue critical alert */}
        {(result.totals.overdue_91_plus_egp > 0) && (
          <div className="mt-3 flex items-start gap-2 rounded-lg border border-danger/30 bg-danger/5 px-3 py-2.5">
            <AlertTriangle className="h-4 w-4 flex-shrink-0 text-danger mt-0.5" />
            <p className="text-xs text-danger">
              <span className="font-semibold">{formatEgp(result.totals.overdue_91_plus_egp, true)} EGP</span> متأخرة أكثر من 90 يوماً — تحتاج مراجعة عاجلة.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

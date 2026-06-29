import { useProjects } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { computeGlobalSummary, computeProjectProfitability, formatEgp } from '../../core/lib/profitability';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { TrendingUp, TrendingDown, Building2, Wheat, PawPrint } from 'lucide-react';
import { ExportGlobalPdfButton } from '../reports/ExportGlobalPdfButton';
import { ExportExcelButton } from '../reports/ExportExcelButton';
import type { SectorId } from '../../core/types/domain';

const SECTOR_META: Record<SectorId, { icon: typeof Building2; color: string; bg: string; label: string }> = {
  'real-estate': { icon: Building2, color: 'text-amber-700', bg: 'bg-amber-50 border-amber-200', label: 'العقاري' },
  agriculture:   { icon: Wheat,     color: 'text-green-700', bg: 'bg-green-50 border-green-200', label: 'الزراعي' },
  livestock:     { icon: PawPrint,  color: 'text-blue-700',  bg: 'bg-blue-50 border-blue-200',   label: 'الحيواني' },
};

export function ProfitabilityPage() {
  const { projects } = useProjects();
  const { transactions } = useTransactions();
  const { obligations } = useObligations();

  const global = computeGlobalSummary(projects, transactions, obligations);
  const isProfit = global.gross_profit_egp >= 0;

  const projectProfits = projects.map(p =>
    computeProjectProfitability(p, transactions, obligations, [], [])
  ).sort((a, b) => b.gross_profit_egp - a.gross_profit_egp);

  return (
    <div className="space-y-6">
      {/* Title + Export buttons */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">محرك الربحية</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            الربح = Σ الإيرادات − Σ المصروفات — قابل للتتبع حتى كل معاملة ومستند
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <ExportGlobalPdfButton />
          <ExportExcelButton />
        </div>
      </div>

      {/* Global formula card */}
      <Card>
        <CardHeader><h3 className="font-semibold">الملخص الإجمالي</h3></CardHeader>
        <CardContent>
          <div className="space-y-2">
            {[
              { label: 'إجمالي الإيرادات', value: global.total_income_egp, color: 'text-success', Icon: TrendingUp, sign: '+' },
              { label: 'إجمالي المصروفات', value: global.total_expense_egp, color: 'text-danger', Icon: TrendingDown, sign: '−' },
            ].map(row => (
              <div key={row.label} className="flex items-center gap-3 rounded-xl border border-border px-4 py-3">
                <row.Icon className={`h-4 w-4 ${row.color}`} />
                <span className="flex-1 text-sm text-muted-foreground">{row.label}</span>
                <span className={`font-bold ${row.color}`}>{row.sign} {formatEgp(row.value)} EGP</span>
              </div>
            ))}
            <div className="flex items-center gap-3 rounded-xl border-2 border-primary/30 bg-primary/5 px-4 py-3">
              {isProfit ? <TrendingUp className="h-5 w-5 text-success" /> : <TrendingDown className="h-5 w-5 text-danger" />}
              <span className="flex-1 text-sm font-medium">إجمالي الربح</span>
              <span className={`text-lg font-bold ${isProfit ? 'text-success' : 'text-danger'}`}>
                = {formatEgp(global.gross_profit_egp)} EGP
              </span>
            </div>
            {global.gross_profit_egp !== 0 && (
              <p className="text-center text-sm text-muted-foreground">
                هامش الربح: <span className="font-bold">{global.margin_pct.toFixed(1)}%</span>
              </p>
            )}
          </div>
        </CardContent>
      </Card>

      {/* By Sector */}
      <div>
        <h3 className="mb-3 font-semibold">الربحية بالقطاع</h3>
        <div className="grid gap-4 sm:grid-cols-3">
          {(['real-estate', 'agriculture', 'livestock'] as SectorId[]).map(sId => {
            const s = global.by_sector[sId];
            const meta = SECTOR_META[sId];
            const Icon = meta.icon;
            const positive = s.gross_profit_egp >= 0;
            return (
              <Card key={sId}>
                <CardContent className="p-5">
                  <div className="mb-4 flex items-center gap-3">
                    <div className={`flex h-10 w-10 items-center justify-center rounded-xl border ${meta.bg}`}>
                      <Icon className={`h-5 w-5 ${meta.color}`} />
                    </div>
                    <div>
                      <p className="font-semibold">{meta.label}</p>
                      <p className="text-xs text-muted-foreground">{s.project_count} مشروع</p>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <div className="flex justify-between text-xs">
                      <span className="text-muted-foreground">الإيرادات</span>
                      <span className="font-medium text-success">{formatEgp(s.total_income_egp, true)} EGP</span>
                    </div>
                    <div className="flex justify-between text-xs">
                      <span className="text-muted-foreground">المصروفات</span>
                      <span className="font-medium text-danger">{formatEgp(s.total_expense_egp, true)} EGP</span>
                    </div>
                    <div className={`flex justify-between rounded-lg px-2 py-1.5 text-xs font-bold ${positive ? 'bg-success/10 text-success' : 'bg-danger/10 text-danger'}`}>
                      <span>صافي الربح</span>
                      <span>{positive ? '+' : ''}{formatEgp(s.gross_profit_egp, true)} EGP</span>
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      </div>

      {/* By Project */}
      {projectProfits.length > 0 && (
        <div>
          <h3 className="mb-3 font-semibold">الربحية بالمشروع</h3>
          <Card>
            <div className="divide-y divide-border">
              {projectProfits.map(pp => {
                const meta = SECTOR_META[pp.sector_id];
                const Icon = meta.icon;
                const positive = pp.gross_profit_egp >= 0;
                const totalAbs = pp.total_income_egp + pp.total_expense_egp;
                const barPct = totalAbs > 0 ? Math.abs(pp.gross_profit_egp) / totalAbs * 100 : 0;
                return (
                  <div key={pp.project_id} className="px-4 py-4">
                    <div className="mb-2 flex items-center justify-between gap-4">
                      <div className="flex items-center gap-2 min-w-0">
                        <Icon className={`h-4 w-4 flex-shrink-0 ${meta.color}`} />
                        <span className="truncate text-sm font-medium">{pp.project_name_ar}</span>
                      </div>
                      <span className={`flex-shrink-0 text-sm font-bold ${positive ? 'text-success' : 'text-danger'}`}>
                        {positive ? '+' : ''}{formatEgp(pp.gross_profit_egp, true)} EGP
                      </span>
                    </div>
                    <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                      <div
                        className={`h-full rounded-full transition-all ${positive ? 'bg-success' : 'bg-danger'}`}
                        style={{ width: `${Math.min(barPct, 100)}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}

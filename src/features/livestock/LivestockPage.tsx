import { useState } from 'react';
import { PawPrint, Plus, TrendingUp, Beef } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { useProjects } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { useAssets } from '../assets/hooks';
import { computeProjectProfitability, computeSectorSummary, formatEgp } from '../../core/lib/profitability';
import { ProjectForm } from '../projects/ProjectForm';
import type { ProjectInput } from '../projects/storage';

export function LivestockPage() {
  const { projects, createProject } = useProjects();
  const { transactions } = useTransactions();
  const { obligations } = useObligations();
  const { assets } = useAssets();
  const [showForm, setShowForm] = useState(false);

  const lvProjects = projects.filter((p) => p.sector_id === 'livestock');
  const lvAssets = assets.filter((a) => a.sector_id === 'livestock');
  const summary = computeSectorSummary('livestock', projects, transactions, obligations);
  const totalHeads = lvAssets.reduce((s, a) => s + (a.quantity ?? 0), 0);

  function handleCreate(input: ProjectInput) {
    createProject({ ...input, sector_id: 'livestock' });
    setShowForm(false);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="الاستثمار الحيواني"
        description="قطعان، أعلاف، علاج، تحصينات، ولادات، نفوق ومبيعات."
      >
        <Button onClick={() => setShowForm(true)}>
          <Plus className="h-4 w-4" /> قطيع جديد
        </Button>
      </PageHeader>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'إجمالي الرؤوس', value: totalHeads, isCount: true, color: 'text-blue-700' },
          { label: 'إيرادات البيع', value: summary.total_income_egp, color: 'text-success' },
          { label: 'تكاليف الرعاية', value: summary.total_expense_egp, color: 'text-danger' },
          { label: 'صافي الربح', value: summary.gross_profit_egp, color: summary.gross_profit_egp >= 0 ? 'text-success' : 'text-danger' },
        ].map((k) => (
          <Card key={k.label}>
            <CardContent className="p-4">
              <p className="text-xs text-muted-foreground mb-1">{k.label}</p>
              <p className={`text-xl font-bold ${k.color}`}>
                {(k as any).isCount ? k.value : `${formatEgp(k.value, true)} EGP`}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>

      {showForm && (
        <Card>
          <CardContent>
            <h3 className="mb-4 font-semibold">قطيع / مشروع حيواني جديد</h3>
            <ProjectForm onSubmit={handleCreate} onCancel={() => setShowForm(false)} />
          </CardContent>
        </Card>
      )}

      {lvAssets.length > 0 && (
        <div>
          <h3 className="mb-3 font-semibold">القطعان والأصول ({lvAssets.length})</h3>
          <div className="grid gap-3 sm:grid-cols-3">
            {lvAssets.map((asset) => (
              <Card key={asset.id}>
                <CardContent className="p-4">
                  <Beef className="h-4 w-4 text-blue-600 mb-2" />
                  <p className="text-sm font-medium">{asset.name_ar}</p>
                  <p className="text-xs text-muted-foreground">{asset.type}</p>
                  {asset.quantity && (
                    <p className="text-sm font-bold text-blue-700 mt-1">{asset.quantity} {asset.unit ?? 'رأس'}</p>
                  )}
                  <p className="text-xs text-muted-foreground mt-0.5">{formatEgp(asset.acquisition_cost_egp, true)} EGP تكلفة</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      <div>
        <h3 className="mb-3 font-semibold">مشاريع القطعان ({lvProjects.length})</h3>
        {lvProjects.length === 0 ? (
          <EmptyState title="لا توجد بيانات بعد" description="أضف أول سجل لهذا القسم لتبدأ." />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            {lvProjects.map((project) => {
              const prof = computeProjectProfitability(project, transactions, obligations, [], []);
              const positive = prof.gross_profit_egp >= 0;
              return (
                <Card key={project.id}>
                  <CardContent className="p-5">
                    <div className="mb-3 flex items-start justify-between">
                      <p className="font-semibold">{project.name_ar}</p>
                      <Badge tone={project.status === 'active' ? 'positive' : 'neutral'}>{project.status}</Badge>
                    </div>
                    <div className={`flex items-center gap-2 rounded-xl px-3 py-2 ${positive ? 'bg-success/10' : 'bg-danger/10'}`}>
                      <TrendingUp className={`h-4 w-4 ${positive ? 'text-success' : 'text-danger'}`} />
                      <span className={`text-sm font-bold ${positive ? 'text-success' : 'text-danger'}`}>{formatEgp(prof.gross_profit_egp, true)} EGP</span>
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

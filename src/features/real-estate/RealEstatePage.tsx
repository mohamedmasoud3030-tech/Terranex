import { useState } from 'react';
import { Building2, Plus, MapPin, TrendingUp } from 'lucide-react';
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

export function RealEstatePage() {
  const { projects, createProject } = useProjects();
  const { transactions } = useTransactions();
  const { obligations } = useObligations();
  const { assets } = useAssets();
  const [showForm, setShowForm] = useState(false);

  const reProjects = projects.filter((p) => p.sector_id === 'real-estate');
  const reAssets = assets.filter((a) => a.sector_id === 'real-estate');
  const summary = computeSectorSummary('real-estate', projects, transactions, obligations);

  function handleCreate(input: ProjectInput) {
    createProject({ ...input, sector_id: 'real-estate' });
    setShowForm(false);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="الاستثمار العقاري"
        description="أراضي، أصول، شراء، تطوير، بيع، مستندات ملكية وربحية."
      >
        <Button onClick={() => setShowForm(true)}>
          <Plus className="h-4 w-4" /> مشروع عقاري جديد
        </Button>
      </PageHeader>

      <div className="grid gap-3 min-[420px]:grid-cols-3">
        {[
          { label: 'إجمالي الإيرادات', value: summary.total_income_egp, color: 'text-success' },
          { label: 'إجمالي المصروفات', value: summary.total_expense_egp, color: 'text-danger' },
          { label: 'إجمالي الربح', value: summary.gross_profit_egp, color: summary.gross_profit_egp >= 0 ? 'text-success' : 'text-danger' },
        ].map((k) => (
          <Card key={k.label}>
            <CardContent className="p-4">
              <p className="text-xs text-muted-foreground mb-1">{k.label}</p>
              <p className={`text-xl font-bold ${k.color}`}>{formatEgp(k.value, true)} EGP</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {showForm && (
        <Card>
          <CardContent>
            <h3 className="mb-4 font-semibold">مشروع عقاري جديد</h3>
            <ProjectForm onSubmit={handleCreate} onCancel={() => setShowForm(false)} />
          </CardContent>
        </Card>
      )}

      {reAssets.length > 0 && (
        <div>
          <h3 className="mb-3 font-semibold">الأصول العقارية ({reAssets.length})</h3>
          <div className="grid gap-3 sm:grid-cols-3">
            {reAssets.map((asset) => (
              <Card key={asset.id}>
                <CardContent className="p-4">
                  <div className="flex items-start gap-2">
                    <MapPin className="h-4 w-4 text-amber-600 mt-0.5 flex-shrink-0" />
                    <div>
                      <p className="text-sm font-medium">{asset.name_ar}</p>
                      <p className="text-xs text-muted-foreground">{asset.type}</p>
                      <p className="text-sm font-bold text-amber-700 mt-1">{formatEgp(asset.acquisition_cost_egp, true)} EGP</p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      <div>
        <h3 className="mb-3 font-semibold">مشاريع القطاع ({reProjects.length})</h3>
        {reProjects.length === 0 ? (
          <EmptyState title="لا توجد بيانات بعد" description="أضف أول سجل لهذا القسم لتبدأ." />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            {reProjects.map((project) => {
              const prof = computeProjectProfitability(project, transactions, obligations, [], []);
              const positive = prof.gross_profit_egp >= 0;
              return (
                <Card key={project.id}>
                  <CardContent className="p-5">
                    <div className="flex items-start justify-between mb-3">
                      <div>
                        <p className="font-semibold">{project.name_ar}</p>
                        <p className="text-xs text-muted-foreground mt-0.5">{project.start_date}</p>
                      </div>
                      <Badge tone={project.status === 'active' ? 'positive' : 'neutral'}>{project.status}</Badge>
                    </div>
                    <div className={`flex items-center gap-2 rounded-xl px-3 py-2 ${positive ? 'bg-success/10' : 'bg-danger/10'}`}>
                      <TrendingUp className={`h-4 w-4 ${positive ? 'text-success' : 'text-danger'}`} />
                      <span className={`text-sm font-bold ${positive ? 'text-success' : 'text-danger'}`}>
                        {formatEgp(prof.gross_profit_egp, true)} EGP
                      </span>
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

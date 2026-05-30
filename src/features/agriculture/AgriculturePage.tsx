import { useState } from 'react';
import { Wheat, Plus, Sprout, TrendingUp } from 'lucide-react';
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

export function AgriculturePage() {
  const { projects, createProject } = useProjects();
  const { transactions } = useTransactions();
  const { obligations } = useObligations();
  const { assets } = useAssets();
  const [showForm, setShowForm] = useState(false);

  const agProjects = projects.filter((p) => p.sector_id === 'agriculture');
  const agAssets = assets.filter((a) => a.sector_id === 'agriculture');
  const summary = computeSectorSummary('agriculture', projects, transactions, obligations);

  function handleCreate(input: ProjectInput) {
    createProject({ ...input, sector_id: 'agriculture' });
    setShowForm(false);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        titleKey="sector_agriculture_name"
        descriptionKey="sector_agriculture_desc"
        actions={<Button onClick={() => setShowForm(true)}><Plus className="h-4 w-4" /> موسم جديد</Button>}
      />
      <div className="grid grid-cols-3 gap-4">
        {[
          { label: 'إجمالي المبيعات', value: summary.total_income_egp, color: 'text-success' },
          { label: 'تكاليف المواسم', value: summary.total_expense_egp, color: 'text-danger' },
          { label: 'ربحية الموسم', value: summary.gross_profit_egp, color: summary.gross_profit_egp >= 0 ? 'text-success' : 'text-danger' },
        ].map((k) => (
          <Card key={k.label}><CardContent className="p-4">
            <p className="text-xs text-muted-foreground mb-1">{k.label}</p>
            <p className={`text-xl font-bold ${k.color}`}>{formatEgp(k.value, true)} EGP</p>
          </CardContent></Card>
        ))}
      </div>
      {showForm && (
        <Card><CardContent>
          <h3 className="mb-4 font-semibold">موسم / مشروع زراعي جديد</h3>
          <ProjectForm onSubmit={handleCreate} onCancel={() => setShowForm(false)} />
        </CardContent></Card>
      )}
      {agAssets.length > 0 && (
        <div>
          <h3 className="mb-3 font-semibold">المزارع والأراضي ({agAssets.length})</h3>
          <div className="grid gap-3 sm:grid-cols-3">
            {agAssets.map((asset) => (
              <Card key={asset.id}><CardContent className="p-4">
                <Sprout className="h-4 w-4 text-green-600 mb-2" />
                <p className="text-sm font-medium">{asset.name_ar}</p>
                <p className="text-xs text-muted-foreground">{asset.type}{asset.quantity ? ` • ${asset.quantity} ${asset.unit ?? ''}` : ''}</p>
                <p className="text-sm font-bold text-green-700 mt-1">{formatEgp(asset.acquisition_cost_egp, true)} EGP</p>
              </CardContent></Card>
            ))}
          </div>
        </div>
      )}
      <div>
        <h3 className="mb-3 font-semibold">المواسم ({agProjects.length})</h3>
        {agProjects.length === 0 ? (
          <EmptyState titleKey="state_empty_title" descriptionKey="state_empty_description" />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            {agProjects.map((project) => {
              const prof = computeProjectProfitability(project, transactions, obligations, [], []);
              const positive = prof.gross_profit_egp >= 0;
              return (
                <Card key={project.id}><CardContent className="p-5">
                  <div className="mb-3 flex items-start justify-between">
                    <p className="font-semibold">{project.name_ar}</p>
                    <Badge variant={project.status === 'active' ? 'success' : 'default'}>{project.status}</Badge>
                  </div>
                  <div className="mb-2 space-y-1 text-xs text-muted-foreground">
                    <div className="flex justify-between"><span>إيرادات</span><span className="text-success font-medium">{formatEgp(prof.total_income_egp, true)} EGP</span></div>
                    <div className="flex justify-between"><span>تكاليف</span><span className="text-danger font-medium">{formatEgp(prof.total_expense_egp, true)} EGP</span></div>
                  </div>
                  <div className={`flex items-center gap-2 rounded-xl px-3 py-2 ${positive ? 'bg-success/10' : 'bg-danger/10'}`}>
                    <TrendingUp className={`h-4 w-4 ${positive ? 'text-success' : 'text-danger'}`} />
                    <span className={`text-sm font-bold ${positive ? 'text-success' : 'text-danger'}`}>{formatEgp(prof.gross_profit_egp, true)} EGP</span>
                  </div>
                </CardContent></Card>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

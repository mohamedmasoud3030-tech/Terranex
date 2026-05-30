import { useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import { Plus, Building2, Wheat, PawPrint, TrendingUp, TrendingDown, Minus, ChevronLeft } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { useProjects } from './hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { computeProjectProfitability, formatEgp } from '../../core/lib/profitability';
import { ProjectForm } from './ProjectForm';
import type { ProjectInput } from './storage';
import type { SectorId, Project } from '../../core/types/domain';

const SECTOR_META: Record<SectorId, { icon: typeof Building2; color: string; bg: string; label: string }> = {
  'real-estate': { icon: Building2, color: 'text-amber-700', bg: 'bg-amber-50 border-amber-200', label: 'عقاري' },
  agriculture:   { icon: Wheat,     color: 'text-green-700', bg: 'bg-green-50 border-green-200', label: 'زراعي' },
  livestock:     { icon: PawPrint,  color: 'text-blue-700',  bg: 'bg-blue-50 border-blue-200',   label: 'حيواني' },
};

const STATUS_LABELS: Record<Project['status'], { ar: string; tone: 'neutral' | 'positive' | 'warning' | 'negative' | 'info' }> = {
  planning:  { ar: 'تخطيط',          tone: 'info' as const },
  active:    { ar: 'نشط',             tone: 'positive' as const },
  on_hold:   { ar: 'متوقف مؤقتاً',   tone: 'warning' as const },
  completed: { ar: 'مكتمل',           tone: 'neutral' as const },
  cancelled: { ar: 'ملغى',            tone: 'negative' as const },
};

export function ProjectsPage() {
  const router = useRouter();
  const { projects, createProject, deleteProject } = useProjects();
  const { transactions } = useTransactions();
  const { obligations } = useObligations();
  const [showForm, setShowForm] = useState(false);
  const [filterSector, setFilterSector] = useState<SectorId | 'all'>('all');

  const filtered = filterSector === 'all' ? projects : projects.filter((p) => p.sector_id === filterSector);

  function handleCreate(input: ProjectInput) {
    createProject(input);
    setShowForm(false);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="إدارة المشاريع"
        description="كل مشروع هو حاوية الأصول والمعاملات والمستندات والشركاء."
        children={
          <Button onClick={() => setShowForm(true)}
      /> مشروع جديد
          </Button>
        }
      />

      {/* Create form inline card */}
      {showForm && (
        <Card>
          <CardContent>
            <h3 className="mb-4 text-base font-semibold">مشروع جديد</h3>
            <ProjectForm onSubmit={handleCreate} onCancel={() => setShowForm(false)} />
          </CardContent>
        </Card>
      )}

      {/* Sector filter pills */}
      <div className="flex gap-2">
        {(['all', 'real-estate', 'agriculture', 'livestock'] as const).map((s) => (
          <button
            key={s}
            onClick={() => setFilterSector(s)}
            className={`rounded-full border px-4 py-1.5 text-sm font-medium transition ${
              filterSector === s
                ? 'border-primary bg-primary/10 text-primary'
                : 'border-border text-muted-foreground hover:bg-muted'
            }`}
          >
            {s === 'all' ? 'الكل' : SECTOR_META[s].label}
          </button>
        ))}
      </div>

      {/* Projects grid */}
      {filtered.length === 0 ? (
        <EmptyState title="لا توجد بيانات بعد" description="أضف أول سجل لهذا القسم لتبدأ." />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((project) => {
            const meta = SECTOR_META[project.sector_id];
            const SectorIcon = meta.icon;
            const statusInfo = STATUS_LABELS[project.status];
            const profitability = computeProjectProfitability(project, transactions, obligations, [], []);
            const isProfit = profitability.gross_profit_egp >= 0;

            return (
              <button
                key={project.id}
                onClick={() => router.navigate({ to: '/projects/$id', params: { id: project.id } } as any)}
                className="group text-start rounded-2xl border border-border bg-card p-5 shadow-sm transition hover:border-primary/40 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary cursor-pointer"
              >
                {/* Header */}
                <div className="mb-3 flex items-start justify-between gap-2">
                  <div className={`flex h-10 w-10 items-center justify-center rounded-xl border ${meta.bg}`}>
                    <SectorIcon className={`h-5 w-5 ${meta.color}`} />
                  </div>
                  <Badge tone={statusInfo.tone}>{statusInfo.ar}</Badge>
                </div>

                {/* Name */}
                <h3 className="mb-1 font-semibold text-foreground line-clamp-1">{project.name_ar}</h3>
                {project.name_en && (
                  <p className="mb-3 text-xs text-muted-foreground line-clamp-1" dir="ltr">{project.name_en}</p>
                )}

                {/* Profitability mini strip */}
                <div className="mt-3 flex items-center justify-between rounded-xl border border-border bg-muted/50 px-3 py-2">
                  <span className="text-xs text-muted-foreground">صافي الربح</span>
                  <span className={`flex items-center gap-1 text-sm font-bold ${isProfit ? 'text-success' : 'text-danger'}`}>
                    {isProfit ? <TrendingUp className="h-3.5 w-3.5" /> : <TrendingDown className="h-3.5 w-3.5" />}
                    {formatEgp(profitability.gross_profit_egp, true)} EGP
                  </span>
                </div>

                {/* Footer */}
                <div className="mt-3 flex items-center justify-between text-xs text-muted-foreground">
                  <span>{meta.label}</span>
                  <ChevronLeft className="h-4 w-4 transition group-hover:text-primary" />
                </div>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

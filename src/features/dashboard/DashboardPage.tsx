import { Plus, TrendingUp, TrendingDown, Building2, Wheat, PawPrint, AlertCircle, ArrowLeft } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { useProjects } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { usePartners } from '../partners/hooks';
import { computeGlobalSummary, formatEgp } from '../../core/lib/profitability';
import type { SectorId } from '../../core/types/domain';
const SECTOR_META: Record<SectorId, { icon: typeof Building2; label: string; color: string; bg: string; route: string }> = {
'real-estate': { icon: Building2, label: 'العقاري',  color: 'text-amber-700', bg: 'bg-amber-50 border-amber-200', route: '/real-estate' },
agriculture:   { icon: Wheat,     label: 'الزراعي',  color: 'text-green-700', bg: 'bg-green-50 border-green-200', route: '/agriculture' },
livestock:     { icon: PawPrint,  label: 'الحيواني', color: 'text-blue-700', bg: 'bg-blue-50 border-blue-200',   route: '/livestock' },
};
export function DashboardPage() {
const router = useRouter();
const { projects } = useProjects();
const { transactions } = useTransactions();
const { obligations, open: openObls } = useObligations();
const { partners } = usePartners();
const global = computeGlobalSummary(projects, transactions, obligations);
const isProfit = global.gross_profit_egp >= 0;
const today = new Date().toISOString().slice(0, 10);
const overdue = openObls.filter((o) => o.due_date && o.due_date < today);
const dueSoon = openObls.filter((o) => o.due_date && o.due_date >= today && o.due_date <= new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10));
const priorityIds = new Set([...overdue, ...dueSoon].map((obligation) => obligation.id));
const prioritizedOpenObls = [...overdue, ...dueSoon, ...openObls.filter((obligation) => !priorityIds.has(obligation.id))];
return (
<div className="space-y-6">
<PageHeader title="أين تقف الشركة ماليًا وتشغيليًا الآن؟" description="مؤشرات موحدة بالجنيه المصري تغطي القطاعات والمشاريع والالتزامات والأصول.">
<Button onClick={() => router.navigate({ to: '/projects' } as any)}><Plus className="h-4 w-4" /> مشروع جديد</Button>
</PageHeader>
{overdue.length > 0 && (<div className="flex items-start gap-3 rounded-2xl border border-danger/30 bg-danger/5 px-4 py-3"><AlertCircle className="h-5 w-5 text-danger flex-shrink-0 mt-0.5" /><div><p className="text-sm font-semibold text-danger">{overdue.length} التزام متأخر عن الاستحقاق</p><p className="text-xs text-muted-foreground mt-0.5">تأكد من مراجعة صفحة الذمم والالتزامات</p></div></div>)}
<div className="grid grid-cols-2 gap-4 sm:grid-cols-4">{[
{ label: 'إجمالي الإيرادات', value: global.total_income_egp, color: 'text-success', Icon: TrendingUp },
{ label: 'إجمالي المصروفات', value: global.total_expense_egp, color: 'text-danger', Icon: TrendingDown },
{ label: 'إجمالي الربح', value: global.gross_profit_egp, color: isProfit ? 'text-success' : 'text-danger', Icon: isProfit ? TrendingUp : TrendingDown },
{ label: 'ذمم مدينة مفتوحة', value: global.open_receivables_egp, color: 'text-warning', Icon: AlertCircle },
].map((kpi) => (<Card key={kpi.label}><CardContent className="p-4"><div className="flex items-center justify-between mb-2"><span className="text-xs text-muted-foreground">{kpi.label}</span><kpi.Icon className={`h-4 w-4 ${kpi.color}`} /></div><p className={`text-xl font-bold ${kpi.color}`}>{formatEgp(kpi.value, true)}</p><p className="text-xs text-muted-foreground">EGP</p></CardContent></Card>))}</div>
<div><h3 className="mb-3 font-semibold">الأداء بالقطاع</h3><div className="grid gap-4 sm:grid-cols-3">{(Object.keys(SECTOR_META) as SectorId[]).map((sId) => { const meta = SECTOR_META[sId]; const s = global.by_sector[sId]; const Icon = meta.icon; const positive = s.gross_profit_egp >= 0; const sectorProjects = projects.filter((p) => p.sector_id === sId); return (<button key={sId} onClick={() => router.navigate({ to: meta.route } as any)} className="group text-start rounded-2xl border border-border bg-card p-5 shadow-sm hover:border-primary/30 hover:shadow-md transition cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"><div className="mb-4 flex items-center justify-between"><div className={`flex h-10 w-10 items-center justify-center rounded-xl border ${meta.bg}`}><Icon className={`h-5 w-5 ${meta.color}`} /></div><ArrowLeft className="h-4 w-4 text-muted-foreground transition group-hover:text-primary" /></div><p className="mb-1 font-semibold">{meta.label}</p><p className="text-xs text-muted-foreground mb-3">{sectorProjects.length} مشروع</p><div className="space-y-1.5"><div className="flex justify-between text-xs"><span className="text-muted-foreground">إيرادات</span><span className="font-medium text-success">{formatEgp(s.total_income_egp, true)} EGP</span></div><div className="flex justify-between text-xs"><span className="text-muted-foreground">مصروفات</span><span className="font-medium text-danger">{formatEgp(s.total_expense_egp, true)} EGP</span></div><div className={`flex justify-between rounded-lg px-2 py-1.5 text-xs font-bold mt-1 ${positive ? 'bg-success/10 text-success' : 'bg-danger/10 text-danger'}`}><span>الربح</span><span>{positive ? '+' : ''}{formatEgp(s.gross_profit_egp, true)} EGP</span></div></div></button>); })}</div></div>
<div className="grid gap-4 lg:grid-cols-2"><Card><CardHeader><div className="flex items-center justify-between"><h3 className="font-semibold">آخر المشاريع</h3><button onClick={() => router.navigate({ to: '/projects' } as any)} className="text-xs text-primary hover:underline">عرض الكل</button></div></CardHeader><CardContent className="p-0">{projects.length === 0 ? (<p className="px-4 py-8 text-center text-sm text-muted-foreground">لا توجد مشاريع بعد</p>) : (<div className="divide-y divide-border">{projects.slice(0, 5).map((p) => { const meta = SECTOR_META[p.sector_id]; const Icon = meta.icon; const txCount = transactions.filter(t => t.project_id === p.id).length; return (<div key={p.id} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/50 transition"><div className={`flex h-8 w-8 items-center justify-center rounded-lg border ${meta.bg} flex-shrink-0`}><Icon className={`h-4 w-4 ${meta.color}`} /></div><div className="flex-1 min-w-0"><p className="text-sm font-medium truncate">{p.name_ar}</p><p className="text-xs text-muted-foreground">{txCount} معاملة</p></div><Badge tone={p.status === 'active' ? 'positive' : 'neutral'}>{p.status === 'active' ? 'نشط' : p.status}</Badge></div>); })}</div>)}</CardContent></Card>
<Card><CardHeader><div className="flex items-center justify-between"><h3 className="font-semibold">الالتزامات المفتوحة</h3><button onClick={() => router.navigate({ to: '/finance/obligations' } as any)} className="text-xs text-primary hover:underline">عرض الكل</button></div></CardHeader><CardContent className="p-0">{openObls.length === 0 ? (<p className="px-4 py-8 text-center text-sm text-muted-foreground">لا توجد التزامات مفتوحة</p>) : (<div className="divide-y divide-border">{prioritizedOpenObls.slice(0, 5).map((o) => { const partnerName = partners.find(p => p.id === o.partner_id)?.name_ar ?? o.partner_id; const isLate = o.due_date && o.due_date < today; const remaining = o.amount_egp - o.amount_settled_egp; return (<div key={o.id} className="flex items-center gap-3 px-4 py-3"><div className={`h-2 w-2 rounded-full flex-shrink-0 ${isLate ? 'bg-danger' : 'bg-warning'}`} /><div className="flex-1 min-w-0"><p className="text-sm font-medium truncate">{partnerName}</p><p className={`text-xs ${isLate ? 'text-danger' : 'text-muted-foreground'}`}>{isLate ? 'متأخر — ' : ''}{o.due_date}</p></div><span className={`text-sm font-bold flex-shrink-0 ${o.direction === 'receivable' ? 'text-success' : 'text-danger'}`}>{formatEgp(remaining, true)} EGP</span></div>); })}</div>)}</CardContent></Card></div>
<div className="grid gap-4 min-[420px]:grid-cols-3">{[
{ label: 'المشاريع', value: projects.length, sub: `${projects.filter(p => p.status === 'active').length} نشط` },
{ label: 'المعاملات', value: transactions.length, sub: `${transactions.filter(t => t.direction === 'income').length} إيراد / ${transactions.filter(t => t.direction === 'expense').length} مصروف` },
{ label: 'الشركاء', value: partners.length, sub: `${openObls.length} التزام مفتوح` },
].map((stat) => (<Card key={stat.label}><CardContent className="p-4 text-center"><p className="text-3xl font-bold">{stat.value}</p><p className="text-sm font-medium mt-1">{stat.label}</p><p className="text-xs text-muted-foreground mt-0.5">{stat.sub}</p></CardContent></Card>))}</div>
</div>);
}

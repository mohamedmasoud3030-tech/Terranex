import type { ComponentType, ReactNode } from 'react';
import { AlertTriangle, ArrowUpLeft, CircleDollarSign, FileText, Loader2 } from 'lucide-react';
import type { Currency, Kpi, Obligation, Sector } from '../data/fixtures';
import { formatMoney, formatNumber } from '../lib/format';

const statusTone = {
  neutral: 'border-border bg-card text-foreground',
  positive: 'border-success/30 bg-success/10 text-success',
  negative: 'border-danger/30 bg-danger/10 text-danger',
  warning: 'border-warning/30 bg-warning/10 text-warning',
};

const sectorStatusLabel = {
  active: 'نشط',
  review: 'يحتاج مراجعة',
  stable: 'مستقر',
};

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-background text-foreground" dir="rtl">
      <div className="flex min-h-screen">
        <aside className="hidden w-72 shrink-0 border-l border-border bg-card px-4 py-5 lg:block">
          <div className="mb-8 rounded-2xl border border-border p-4">
            <p className="text-xs text-muted-foreground">Terranex</p>
            <h1 className="mt-1 text-xl font-bold">نظام التشغيل الاستثماري</h1>
          </div>
          <nav aria-label="التنقل الرئيسي" className="space-y-2">
            {['لوحة القيادة', 'العقاري', 'الزراعي', 'الحيواني', 'المالية', 'المستندات'].map((item) => (
              <a
                className="block rounded-xl px-3 py-3 text-sm font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                href="#"
                key={item}
              >
                {item}
              </a>
            ))}
          </nav>
        </aside>
        <div className="min-w-0 flex-1">
          <header className="sticky top-0 z-10 border-b border-border bg-card/95 px-4 py-3 backdrop-blur lg:px-8">
            <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="text-xs text-muted-foreground">بيئة تأسيسية ببيانات تجريبية معزولة</p>
                <p className="text-sm font-semibold">لوحة Terranex الأولى</p>
              </div>
              <div className="flex flex-col gap-2 sm:flex-row">
                <label className="sr-only" htmlFor="global-search">بحث</label>
                <input
                  id="global-search"
                  className="h-11 rounded-xl border border-border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  placeholder="ابحث عن أصل، موسم، قطيع أو مستند"
                  type="search"
                />
                <select className="h-11 rounded-xl border border-border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary" defaultValue="quarter">
                  <option value="quarter">الربع الحالي</option>
                  <option value="month">الشهر الحالي</option>
                  <option value="year">السنة الحالية</option>
                </select>
              </div>
            </div>
          </header>
          <main className="px-4 py-6 lg:px-8">{children}</main>
        </div>
      </div>
    </div>
  );
}

export function PageHeader({ title, description }: { title: string; description: string }) {
  return (
    <div className="mb-6 flex flex-col gap-4 rounded-3xl border border-border bg-card p-5 lg:flex-row lg:items-center lg:justify-between">
      <div>
        <p className="text-sm text-muted-foreground">سؤال الإدارة الأساسي</p>
        <h2 className="mt-2 text-2xl font-bold md:text-3xl">{title}</h2>
        <p className="mt-2 max-w-3xl text-sm leading-7 text-muted-foreground">{description}</p>
      </div>
      <button className="h-11 rounded-xl bg-primary px-5 text-sm font-semibold text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
        إضافة سجل جديد
      </button>
    </div>
  );
}

export function KpiCard({ kpi }: { kpi: Kpi }) {
  return (
    <article className="rounded-2xl border border-border bg-card p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm text-muted-foreground">{kpi.title}</p>
          <p className="mt-3 text-2xl font-bold">
            {kpi.currency ? formatMoney(kpi.value, kpi.currency) : formatNumber(kpi.value)}
          </p>
        </div>
        <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${statusTone[kpi.status]}`}>
          {kpi.period}
        </span>
      </div>
      <p className="mt-4 text-sm text-muted-foreground">{kpi.trendLabel}</p>
      <a className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-primary underline-offset-4 hover:underline" href="#">
        <ArrowUpLeft className="h-4 w-4" aria-hidden="true" />
        {kpi.sourceLabel}
      </a>
    </article>
  );
}

export function SectorCard({ sector }: { sector: Sector }) {
  return (
    <article className="rounded-2xl border border-border bg-card p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-lg font-bold">{sector.title}</h3>
          <p className="mt-2 min-h-14 text-sm leading-7 text-muted-foreground">{sector.description}</p>
        </div>
        <span className="rounded-full border border-border px-2.5 py-1 text-xs font-semibold text-muted-foreground">
          {sectorStatusLabel[sector.status]}
        </span>
      </div>
      <div className="mt-5 rounded-2xl bg-muted p-4">
        <p className="text-xs text-muted-foreground">{sector.metric}</p>
        <p className="mt-1 text-2xl font-bold">{sector.value}</p>
      </div>
      <a className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-primary underline-offset-4 hover:underline" href={sector.href}>
        فتح سجل القطاع
        <ArrowUpLeft className="h-4 w-4" aria-hidden="true" />
      </a>
    </article>
  );
}

export function DataTableShell({ obligations }: { obligations: Obligation[] }) {
  return (
    <section className="rounded-3xl border border-border bg-card p-4 shadow-sm">
      <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h3 className="text-xl font-bold">الذمم والالتزامات القريبة</h3>
          <p className="mt-1 text-sm text-muted-foreground">جدول تجريبي يوضح شكل الربط بين المال، القطاع، والطرف، والمستند.</p>
        </div>
        <span className="rounded-full border border-warning/30 bg-warning/10 px-3 py-1 text-sm font-semibold text-warning">بيانات تجريبية</span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[780px] border-separate border-spacing-0 text-right text-sm">
          <thead>
            <tr className="text-muted-foreground">
              {['التاريخ', 'النوع', 'القطاع', 'الطرف', 'المبلغ', 'الحالة', 'المستند'].map((header) => (
                <th className="border-b border-border px-3 py-3 font-semibold" key={header}>{header}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {obligations.map((row) => (
              <tr className="align-top" key={row.id}>
                <td className="border-b border-border px-3 py-3">{row.date}</td>
                <td className="border-b border-border px-3 py-3">{row.type}</td>
                <td className="border-b border-border px-3 py-3">{row.sector}</td>
                <td className="border-b border-border px-3 py-3">{row.counterparty}</td>
                <td className="border-b border-border px-3 py-3 font-semibold">{formatMoney(row.amount, row.currency)}</td>
                <td className="border-b border-border px-3 py-3"><StatusBadge>{row.status}</StatusBadge></td>
                <td className="border-b border-border px-3 py-3">{row.document}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export function StatusBadge({ children }: { children: ReactNode }) {
  return <span className="inline-flex rounded-full border border-border bg-muted px-2.5 py-1 text-xs font-semibold">{children}</span>;
}

export function EmptyState({ title, description, icon: Icon = FileText }: { title: string; description: string; icon?: ComponentType<{ className?: string }> }) {
  return (
    <div className="rounded-3xl border border-dashed border-border bg-card p-8 text-center">
      <Icon className="mx-auto h-10 w-10 text-muted-foreground" aria-hidden="true" />
      <h3 className="mt-4 text-lg font-bold">{title}</h3>
      <p className="mx-auto mt-2 max-w-xl text-sm leading-7 text-muted-foreground">{description}</p>
    </div>
  );
}

export function LoadingSkeleton() {
  return (
    <div className="rounded-3xl border border-border bg-card p-5" aria-label="جار التحميل">
      <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" aria-hidden="true" />
      <div className="mt-4 grid gap-3 md:grid-cols-3">
        <div className="h-20 rounded-2xl bg-muted" />
        <div className="h-20 rounded-2xl bg-muted" />
        <div className="h-20 rounded-2xl bg-muted" />
      </div>
    </div>
  );
}

export function ErrorState() {
  return (
    <div className="rounded-3xl border border-danger/30 bg-danger/10 p-5 text-danger">
      <div className="flex items-center gap-3">
        <AlertTriangle className="h-5 w-5" aria-hidden="true" />
        <h3 className="font-bold">تعذر تحميل البيانات</h3>
      </div>
      <p className="mt-2 text-sm">هذه حالة واجهة فقط لحين ربط الخدمات الحقيقية.</p>
    </div>
  );
}

export function MoneyValue({ value, currency }: { value: number; currency: Currency }) {
  return <span className="font-semibold tabular-nums">{formatMoney(value, currency)}</span>;
}

export function PeriodFilter() {
  return (
    <label className="inline-flex flex-col gap-1 text-sm font-medium">
      الفترة
      <select className="h-11 rounded-xl border border-border bg-background px-3 outline-none focus-visible:ring-2 focus-visible:ring-primary" defaultValue="quarter">
        <option value="quarter">الربع الحالي</option>
        <option value="month">الشهر الحالي</option>
        <option value="year">السنة الحالية</option>
      </select>
    </label>
  );
}

export function RecordDetailDrawer() {
  return (
    <aside className="rounded-3xl border border-border bg-card p-5">
      <div className="flex items-center gap-3">
        <CircleDollarSign className="h-5 w-5 text-primary" aria-hidden="true" />
        <h3 className="text-lg font-bold">مسار التدقيق</h3>
      </div>
      <p className="mt-2 text-sm leading-7 text-muted-foreground">
        هذا المكان مخصص لاحقًا لعرض مصدر الرقم: السجل، المستند، الطرف، وتاريخ الاعتماد.
      </p>
    </aside>
  );
}

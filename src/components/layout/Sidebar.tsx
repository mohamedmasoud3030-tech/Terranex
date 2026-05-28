import { useRouter, useLocation } from '@tanstack/react-router';
import {
  Building2, Wheat, PawPrint, Banknote,
  FolderOpen, Users, Settings, LayoutDashboard,
} from 'lucide-react';
import { useI18n } from '../../core/i18n';
import { cn } from '../../core/lib/cn';

interface NavItem {
  id: string;
  label_ar: string;
  label_en: string;
  icon: React.ComponentType<{ className?: string }>;
  to: string;
}

const NAV_ITEMS: NavItem[] = [
  { id: 'dashboard',   label_ar: 'لوحة القيادة', label_en: 'Dashboard',   icon: LayoutDashboard, to: '/dashboard'   },
  { id: 'real-estate', label_ar: 'العقاري',        label_en: 'Real Estate', icon: Building2,       to: '/real-estate' },
  { id: 'agriculture', label_ar: 'الزراعي',        label_en: 'Agriculture', icon: Wheat,           to: '/agriculture' },
  { id: 'livestock',   label_ar: 'الحيواني',       label_en: 'Livestock',   icon: PawPrint,        to: '/livestock'   },
  { id: 'finance',     label_ar: 'المالية',         label_en: 'Finance',     icon: Banknote,        to: '/finance'     },
  { id: 'documents',   label_ar: 'المستندات',      label_en: 'Documents',   icon: FolderOpen,      to: '/documents'   },
  { id: 'partners',    label_ar: 'الشركاء',        label_en: 'Partners',    icon: Users,           to: '/partners'    },
  { id: 'settings',    label_ar: 'الإعدادات',      label_en: 'Settings',    icon: Settings,        to: '/settings'    },
];

export function Sidebar() {
  const { t, locale } = useI18n();
  const router = useRouter();
  const { pathname } = useLocation();

  return (
    <aside className="hidden w-72 shrink-0 border-s border-border bg-card px-4 py-5 lg:block">
      {/* Brand */}
      <div className="mb-8 rounded-2xl border border-border p-4">
        <p className="text-xs text-muted-foreground">{t('env_badge')}</p>
        <h1 className="mt-1 text-xl font-bold">{t('app_tagline')}</h1>
      </div>

      {/* Nav */}
      <nav aria-label={locale === 'ar' ? 'التنقل الرئيسي' : 'Main navigation'}>
        <ul className="space-y-1" role="list">
          {NAV_ITEMS.map((item) => {
            const Icon = item.icon;
            const isActive =
              pathname === item.to ||
              (item.to !== '/dashboard' && pathname.startsWith(item.to));
            return (
              <li key={item.id}>
                <button
                  onClick={() => router.navigate({ to: item.to })}
                  className={cn(
                    'flex w-full items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary',
                    isActive
                      ? 'bg-primary/10 text-primary'
                      : 'text-muted-foreground hover:bg-muted hover:text-foreground',
                  )}
                  aria-current={isActive ? 'page' : undefined}
                >
                  <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
                  <span>{locale === 'ar' ? item.label_ar : item.label_en}</span>
                </button>
              </li>
            );
          })}
        </ul>
      </nav>
    </aside>
  );
}

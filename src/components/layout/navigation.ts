import type { ComponentType } from 'react';
import {
  Activity,
  Banknote,
  BrainCircuit,
  BriefcaseBusiness,
  FileText,
  LayoutDashboard,
  Landmark,
  Package,
  ShieldCheck,
} from 'lucide-react';

import type { Locale } from '../../core/types';

export interface NavItem {
  id: string;
  label_ar: string;
  label_en: string;
  icon: ComponentType<{ className?: string }>;
  to: string;
}

export const NAV_ITEMS: NavItem[] = [
  { id: 'dashboard', label_ar: 'لوحة القيادة', label_en: 'Dashboard', icon: LayoutDashboard, to: '/dashboard' },
  { id: 'portfolio', label_ar: 'المحفظة', label_en: 'Portfolio', icon: BriefcaseBusiness, to: '/portfolio' },
  { id: 'banking', label_ar: 'البنوك والصناديق', label_en: 'Banking', icon: Landmark, to: '/banking' },
  { id: 'operations', label_ar: 'العمليات', label_en: 'Operations', icon: Activity, to: '/operations' },
  { id: 'inventory', label_ar: 'المخزون', label_en: 'Inventory', icon: Package, to: '/inventory' },
  { id: 'finance', label_ar: 'المالية', label_en: 'Finance', icon: Banknote, to: '/finance' },
  { id: 'invoicing', label_ar: 'الفواتير', label_en: 'Invoices', icon: FileText, to: '/invoicing' },
  { id: 'intelligence', label_ar: 'الذكاء', label_en: 'Intelligence', icon: BrainCircuit, to: '/intelligence' },
  { id: 'governance', label_ar: 'الحوكمة', label_en: 'Governance', icon: ShieldCheck, to: '/governance' },
];

export function getNavItemLabel(item: NavItem, locale: Locale) {
  return locale === 'ar' ? item.label_ar : item.label_en;
}

export function isNavItemActive(pathname: string, item: NavItem) {
  return pathname === item.to || (item.to !== '/dashboard' && pathname.startsWith(item.to));
}

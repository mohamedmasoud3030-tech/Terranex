import type { ComponentType } from 'react';
import {
  Banknote,
  Building2,
  FolderKanban,
  FolderOpen,
  LayoutDashboard,
  PackageOpen,
  PawPrint,
  ReceiptText,
  Settings,
  Users,
  Wheat,
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
  { id: 'projects', label_ar: 'المشاريع', label_en: 'Projects', icon: FolderKanban, to: '/projects' },
  { id: 'real-estate', label_ar: 'العقاري', label_en: 'Real Estate', icon: Building2, to: '/real-estate' },
  { id: 'agriculture', label_ar: 'الزراعي', label_en: 'Agriculture', icon: Wheat, to: '/agriculture' },
  { id: 'livestock', label_ar: 'الحيواني', label_en: 'Livestock', icon: PawPrint, to: '/livestock' },
  { id: 'finance', label_ar: 'المالية', label_en: 'Finance', icon: Banknote, to: '/finance' },
  { id: 'transactions', label_ar: 'المعاملات', label_en: 'Transactions', icon: ReceiptText, to: '/transactions' },
  { id: 'assets', label_ar: 'الأصول', label_en: 'Assets', icon: PackageOpen, to: '/assets' },
  { id: 'documents', label_ar: 'المستندات', label_en: 'Documents', icon: FolderOpen, to: '/documents' },
  { id: 'partners', label_ar: 'الشركاء', label_en: 'Partners', icon: Users, to: '/partners' },
  { id: 'settings', label_ar: 'الإعدادات', label_en: 'Settings', icon: Settings, to: '/settings' },
];

export function getNavItemLabel(item: NavItem, locale: Locale) {
  return locale === 'ar' ? item.label_ar : item.label_en;
}

export function isNavItemActive(pathname: string, item: NavItem) {
  return pathname === item.to || (item.to !== '/dashboard' && pathname.startsWith(item.to));
}

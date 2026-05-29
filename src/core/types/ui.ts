/**
 * UI types — component props, view models, form schemas.
 * Separate from domain.ts to keep business types clean.
 */

import type { ReactNode } from 'react';
import type { Currency, ObligationDirection, ObligationStatus, SectorId, TransactionDirection } from './domain';

// ─── Status display ──────────────────────────────────────────────────────────

export type StatusTone = 'neutral' | 'positive' | 'negative' | 'warning' | 'info';

export interface StatusConfig {
  tone: StatusTone;
  label_ar: string;
  label_en: string;
}

// ─── Table ───────────────────────────────────────────────────────────────────

export interface SortConfig {
  field: string;
  direction: 'asc' | 'desc';
}

export interface PaginationConfig {
  page: number;
  pageSize: number;
  total: number;
}

export interface TableFilter {
  field: string;
  value: string | string[];
  operator: 'eq' | 'in' | 'contains' | 'gte' | 'lte' | 'between';
}

// ─── Form ────────────────────────────────────────────────────────────────────

export interface FormField<T = string> {
  name: string;
  label_ar: string;
  label_en: string;
  placeholder_ar?: string;
  placeholder_en?: string;
  required: boolean;
  defaultValue?: T;
}

// ─── Navigation ──────────────────────────────────────────────────────────────

export interface NavItem {
  id: string;
  label_ar: string;
  label_en: string;
  icon: string;
  href: string;
  badge?: number;
  children?: NavItem[];
}

// ─── Drawer / Modal ─────────────────────────────────────────────────────────

export interface DrawerProps {
  isOpen: boolean;
  onClose: () => void;
  title_ar: string;
  title_en: string;
  children: ReactNode;
}

// ─── KPI card view model ─────────────────────────────────────────────────────

export interface KpiCardVM {
  id: string;
  title_ar: string;
  title_en: string;
  value: number;
  currency?: Currency;
  unit_ar?: string;
  unit_en?: string;
  period_ar: string;
  period_en: string;
  trend_ar: string;
  trend_en: string;
  status: StatusTone;
  source_ar: string;
  source_en: string;
  drill_route?: string;
}

// ─── Sector card view model ──────────────────────────────────────────────────

export interface SectorCardVM {
  id: SectorId;
  name_ar: string;
  name_en: string;
  description_ar: string;
  description_en: string;
  metric_label_ar: string;
  metric_label_en: string;
  metric_value: string;
  status: 'active' | 'review' | 'stable' | 'inactive';
  href: string;
}

// ─── Obligation row view model ────────────────────────────────────────────────

export interface ObligationRowVM {
  id: string;
  date: string;
  direction: ObligationDirection;
  sector_ar: string;
  sector_en: string;
  counterparty_ar: string;
  counterparty_en?: string;
  amount: number;
  currency: Currency;
  amount_egp: number;
  status: ObligationStatus;
  document_title?: string;
  project_name_ar?: string;
}

// ─── Asset row view model (macro investment level) ────────────────────────────

export type AssetRowType = 'land' | 'building' | 'mixed_property' | 'farm' | 'equipment' | 'crop' | 'herd' | 'animal_group' | 'vehicle' | 'other';
export type AssetRowStatus = 'owned' | 'under_development' | 'for_sale' | 'sold' | 'leased_out' | 'disposed';

export interface AssetRowVM {
  id: string;
  project_name_ar: string;
  project_name_en?: string;
  name_ar: string;
  name_en?: string;
  type: AssetRowType;
  status: AssetRowStatus;
  location?: string;
  acquisition_cost_egp: number;
  development_cost_egp: number;
  current_valuation_egp: number;
  sale_price_egp?: number;
  profit_loss_egp: number;
  profit_loss_pct: number;
  document_count: number;
  sector_id: SectorId;
}

// ─── Transaction row view model ───────────────────────────────────────────────

export interface TransactionRowVM {
  id: string;
  date: string;
  direction: TransactionDirection;
  category_ar: string;
  category_en: string;
  counterparty_ar?: string;
  amount: number;
  currency: Currency;
  amount_egp: number;
  document_title?: string;
  notes?: string;
}

// ─── Period filter ─────────────────────────────────────────────────────────

export type PeriodOption = 'month' | 'quarter' | 'year' | 'all';

export interface PeriodFilterState {
  option: PeriodOption;
  custom_from?: string;
  custom_to?: string;
}

// ─── Error / loading states ──────────────────────────────────────────────────

export interface AsyncState<T> {
  data: T | null;
  isLoading: boolean;
  error: string | null;
}

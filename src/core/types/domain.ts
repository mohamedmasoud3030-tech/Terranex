/**
 * Terranex Domain Types — single source of truth.
 * ADR-001 through ADR-003 are encoded here.
 * Every interface maps directly to a future Supabase table.
 */

// ─── Primitives ─────────────────────────────────────────────────────────────

export type Currency = 'EGP' | 'USD' | 'SAR' | 'AED' | 'EUR' | 'GBP';

export type Locale = 'ar' | 'en';

export type Direction = 'rtl' | 'ltr';

export type PeriodFilter = 'month' | 'quarter' | 'year' | 'all' | 'custom';

export interface DateRange {
  from: string; // ISO 8601
  to: string;
}

// ─── Sector ─────────────────────────────────────────────────────────────────

export type SectorId = 'real-estate' | 'agriculture' | 'livestock';

export interface Sector {
  id: SectorId;
  name_ar: string;
  name_en: string;
  description_ar: string;
  description_en: string;
  icon: string; // lucide icon name
  status: 'active' | 'review' | 'stable' | 'inactive';
}

// ─── Project ─────────────────────────────────────────────────────────────────

export type ProjectStatus =
  | 'planning'
  | 'active'
  | 'on_hold'
  | 'completed'
  | 'cancelled';

export interface Project {
  id: string;
  sector_id: SectorId;
  name_ar: string;
  name_en: string;
  description_ar?: string;
  description_en?: string;
  status: ProjectStatus;
  start_date: string;
  end_date?: string;
  base_currency: Currency; // operating currency of this project
  created_at: string;
  updated_at: string;
}

// ─── Asset ──────────────────────────────────────────────────────────────────

export type AssetType =
  | 'land'
  | 'building'
  | 'farm'
  | 'equipment'
  | 'herd'
  | 'animal_group'
  | 'crop'
  | 'other';

export type AssetStatus = 'owned' | 'leased' | 'sold' | 'disposed';

export interface Asset {
  id: string;
  project_id: string;
  sector_id: SectorId;
  type: AssetType;
  name_ar: string;
  name_en: string;
  acquisition_date: string;
  acquisition_cost: number;
  acquisition_currency: Currency;
  acquisition_cost_egp: number;
  current_value_egp?: number;
  status: AssetStatus;
  quantity?: number; // for livestock / crops
  unit?: string; // 'رأس' | 'طن' | 'فدان' etc.
  notes?: string;
  created_at: string;
}

// ─── Partner ─────────────────────────────────────────────────────────────────
// ADR-002: hybrid equity partner + counterparty

export type PartnerCategory = 'equity_partner' | 'counterparty';

export type PartnerCounterpartyRole =
  | 'supplier'
  | 'client'
  | 'service_provider'
  | 'lender'
  | 'government'
  | 'other';

export interface Partner {
  id: string;
  name_ar: string;
  name_en?: string;
  category: PartnerCategory;
  counterparty_role?: PartnerCounterpartyRole; // required when category = 'counterparty'
  phone?: string;
  email?: string;
  address?: string;
  notes?: string;
  created_at: string;
}

/** Join table: equity partners per project, with ownership percentage */
export interface ProjectPartner {
  id: string;
  project_id: string;
  partner_id: string;
  equity_pct: number; // 0–100, must sum to ≤100 across all ProjectPartners for a project
  effective_from: string;
  effective_to?: string;
  notes?: string;
}

// ─── Exchange Rate ────────────────────────────────────────────────────────────
// ADR-001: rates captured at transaction time

export interface ExchangeRate {
  id: string;
  from_currency: Currency;
  to_currency: 'EGP'; // always converting TO EGP
  rate: number; // 1 unit of from_currency = rate EGP
  effective_date: string;
  source: 'manual' | 'api';
  created_at: string;
}

// ─── Transaction ─────────────────────────────────────────────────────────────

export type TransactionDirection = 'income' | 'expense';

export type TransactionCategory =
  // General
  | 'acquisition'
  | 'sale'
  | 'development_cost'
  | 'maintenance'
  | 'salary'
  | 'tax'
  | 'legal_fee'
  | 'transport'
  | 'utility'
  // Agriculture-specific
  | 'seed_input'
  | 'fertilizer'
  | 'harvest_revenue'
  | 'irrigation'
  // Livestock-specific
  | 'feed'
  | 'veterinary'
  | 'vaccination'
  | 'livestock_purchase'
  | 'livestock_sale'
  // Finance
  | 'loan_disbursement'
  | 'loan_repayment'
  | 'interest'
  | 'dividend'
  | 'other';

export interface Transaction {
  id: string;
  project_id: string;
  asset_id?: string;
  partner_id?: string;
  operational_event_id?: string; // links to OperationalEvent if auto-generated
  direction: TransactionDirection;
  category: TransactionCategory;
  amount: number;
  currency: Currency;
  fx_rate: number; // 1 unit of currency = fx_rate EGP at time of transaction
  amount_egp: number; // amount * fx_rate — computed, stored for performance
  transaction_date: string;
  document_id?: string;
  description?: string;
  notes?: string;
  created_at: string;
  updated_at: string;
}

// ─── Obligation ───────────────────────────────────────────────────────────────

export type ObligationDirection = 'receivable' | 'payable';

export type ObligationStatus = 'open' | 'partial' | 'settled' | 'disputed' | 'written_off';

export interface Obligation {
  id: string;
  project_id?: string;
  partner_id: string;
  direction: ObligationDirection;
  amount: number;
  currency: Currency;
  amount_egp: number;
  due_date?: string;
  status: ObligationStatus;
  amount_settled_egp: number; // running total of active settlements
  source_transaction_id?: string; // originating transaction
  document_id?: string;
  notes?: string;
  created_at: string;
  updated_at: string;
}

// ─── Document ─────────────────────────────────────────────────────────────────

export type DocumentType =
  | 'contract'
  | 'invoice'
  | 'receipt'
  | 'ownership_deed'
  | 'veterinary_record'
  | 'sales_agreement'
  | 'permit'
  | 'court_document'
  | 'other';

export interface Document {
  id: string;
  project_id?: string;
  asset_id?: string;
  partner_id?: string;
  transaction_id?: string;
  type: DocumentType;
  title_ar: string;
  title_en?: string;
  file_url?: string;
  file_name?: string;
  file_mime_type?: string;
  file_size_bytes?: number;
  file_sha256?: string;
  issue_date?: string;
  expiry_date?: string;
  notes?: string;
  created_at: string;
}

// ─── Operational Events (Event Sourcing track) ─────────────────────────────
// ADR-003: deep event sourcing for livestock / agriculture

export type OperationalEventType =
  // Livestock
  | 'birth'
  | 'death'
  | 'purchase'
  | 'sale'
  | 'vaccination'
  | 'treatment'
  | 'feed_consumption'
  | 'weighing'
  | 'transfer'
  // Agriculture
  | 'planting'
  | 'irrigation'
  | 'fertilization'
  | 'pest_control'
  | 'harvest'
  | 'crop_loss';

export interface OperationalEvent {
  id: string;
  asset_id: string; // herd or farm asset
  project_id: string;
  type: OperationalEventType;
  event_date: string;
  quantity_delta?: number; // +births, -deaths, +purchases, -sales
  weight_kg?: number; // for weighing events
  unit_cost_egp?: number; // optional cost per unit
  total_cost_egp?: number; // total cost if financial
  description?: string;
  document_id?: string;
  linked_transaction_id?: string; // auto-created transaction if financial
  created_at: string;
}

// ─── Stock Adjustment (Direct adjustment track) ────────────────────────────
// ADR-003: escape hatch for opening balances and manual corrections

export type AdjustmentReason =
  | 'opening_balance'
  | 'data_correction'
  | 'external_audit'
  | 'reconciliation'
  | 'other';

export interface StockAdjustment {
  id: string;
  asset_id: string;
  project_id: string;
  adjustment_date: string;
  quantity_before: number;
  quantity_after: number;
  value_egp_before: number;
  value_egp_after: number;
  reason: AdjustmentReason;
  notes?: string;
  created_at: string;
}

// ─── Computed / View Types ────────────────────────────────────────────────────

/** Profitability computed for a project — from v_project_profitability view */
export interface ProjectProfitability {
  project_id: string;
  project_name_ar: string;
  project_name_en: string;
  sector_id: SectorId;
  total_income_egp: number;
  total_expense_egp: number;
  gross_profit_egp: number;
  open_obligations_egp: number;
  open_receivables_egp: number;
  open_payables_egp: number;
  cash_exposure_egp: number;
  net_profit_egp: number; // gross_profit - open provisions
  partner_splits: PartnerProfitSplit[];
  period: DateRange;
}

export interface PartnerProfitSplit {
  partner_id: string;
  partner_name_ar: string;
  equity_pct: number;
  share_egp: number;
}

/** Dashboard KPI — computed aggregate */
export interface DashboardKpi {
  id: string;
  title_ar: string;
  title_en: string;
  value_egp: number;
  period: string;
  trend_label_ar: string;
  trend_label_en: string;
  status: 'neutral' | 'positive' | 'negative' | 'warning';
  source_label_ar: string;
  source_label_en: string;
  drill_down_route?: string;
}

/** Asset balance — derived from events + adjustments */
export interface AssetBalance {
  asset_id: string;
  asset_name_ar: string;
  quantity: number;
  unit: string;
  estimated_value_egp: number;
  last_event_date: string;
}

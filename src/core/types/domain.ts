/**
 * Terranex Domain Types — single source of truth.
 * ADR-001 through ADR-003 are encoded here.
 * Every interface maps directly to a future Supabase table.
 */

// ─── Primitives ─────────────────────────────────────────────────────────────

export type Currency = 'EGP' | 'USD' | 'OMR' | 'SAR' | 'AED' | 'EUR' | 'GBP';

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
  bank_account_id?: string; // payment method / source of funds (cash/bank/wallet)
  direction: TransactionDirection;
  category: TransactionCategory;
  amount: number;
  currency: Currency;
  fx_rate: number; // 1 unit of currency = fx_rate BASE (legacy name, was EGP) at time of transaction
  amount_egp: number; // amount * fx_rate — computed, stored for performance; equals amount_base when base currency is EGP
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
  fx_rate: number;
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

// ─── Equity Change History (Effective-dated ownership) ──────────────────────
// ADR-011: time-based project ownership
// Records every change in a partner's equity percentage with effective dates.
// Immutable: corrections are modeled as new entries, not updates.

export type EquityChangeType = 'entry' | 'increase' | 'decrease' | 'exit' | 'correction';

export interface EquityChangeEvent {
  id: string;
  project_id: string;
  partner_id: string;
  effective_date: string;
  previous_pct: number;
  new_pct: number;
  change_type: EquityChangeType;
  consideration_amount?: number;
  consideration_currency?: Currency;
  frozen_amount_egp?: number;
  supporting_document_id?: string;
  reason?: string;
  notes?: string;
  created_by: string;
  created_at: string;
  reversal_of_id?: string; // references another EquityChangeEvent for corrections
}

// ─── Partner Ledger Entry (Append-only financial record) ────────────────────
// ADR-012: append-only partner ledger
// Every financial movement for a partner within a project. Immutable: reversals
// are modeled as new entries referencing the original.

export type PartnerLedgerEntryType =
  | 'capital_contribution'
  | 'withdrawal'
  | 'distribution_entitlement'
  | 'distribution_payment'
  | 'correction'
  | 'reversal';

export interface PartnerLedgerEntry {
  id: string;
  project_id: string;
  partner_id: string;
  entry_type: PartnerLedgerEntryType;
  amount: number;
  currency: Currency;
  fx_rate: number;
  amount_egp: number;
  posting_date: string;
  supporting_document_id?: string;
  related_equity_event_id?: string;
  related_distribution_id?: string;
  notes?: string;
  reversal_of_id?: string; // references another PartnerLedgerEntry
  created_by: string;
  created_at: string;
}

// ─── Distribution Record (Profit distribution header) ───────────────────────
// ADR-013: immutable distribution snapshots
// A distribution cycle for a project. Snapshots the ownership percentages and
// amounts at the time of creation. Not recalculated from current state.

export type DistributionStatus = 'draft' | 'approved' | 'paid' | 'reversed';

export interface Distribution {
  id: string;
  project_id: string;
  distribution_date: string;
  ownership_as_of_date: string;
  total_amount: number;
  currency: Currency;
  fx_rate: number;
  total_amount_egp: number;
  status: DistributionStatus;
  notes?: string;
  supporting_document_id?: string;
  created_by: string;
  created_at: string;
}

// ─── Distribution Allocation (Per-partner share) ────────────────────────────
// ADR-013: immutable distribution snapshots
// Each partner's share of a distribution. The equity_pct_snapshot and amounts
// are frozen at creation time and never recalculated.

export type DistributionAllocationStatus = 'due' | 'paid' | 'reversed';

export interface DistributionAllocation {
  id: string;
  distribution_id: string;
  partner_id: string;
  equity_pct_snapshot: number; // frozen at distribution creation
  allocated_amount: number;
  allocated_amount_egp: number;
  status: DistributionAllocationStatus;
  payment_date?: string;
  payment_document_id?: string;
  related_ledger_entry_id?: string; // links to PartnerLedgerEntry when paid
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
  net_realized_profit_egp: number;
  open_obligations_egp: number;
  open_receivables_egp: number;
  open_payables_egp: number;
  cash_exposure_egp: number;
  net_profit_egp: number; // gross_profit - open provisions
  distributed_profit_egp: number;
  undistributed_profit_egp: number;
  partner_entitlement_egp: number;
  paid_distribution_amounts_egp: number;
  unpaid_distribution_amounts_egp: number;
  partner_ledger_position_egp: number;
  as_of_date: string;
  temporal_rule_ar: string;
  temporal_rule_en: string;
  partner_splits: PartnerProfitSplit[];
  period: DateRange;
}

export interface PartnerProfitSplit {
  partner_id: string;
  partner_name_ar: string;
  equity_pct: number;
  share_egp: number;
  distributed_egp?: number;
  paid_egp?: number;
  unpaid_egp?: number;
  ledger_balance_egp?: number;
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

// ─── Company Settings ──────────────────────────────────────────────────────

export type CompanyCountry = 'EG' | 'OM' | 'SA' | 'AE' | 'OTHER';

export interface CompanySettings {
  owner_id: string;
  company_name_ar: string;
  company_name_en?: string;
  commercial_register?: string;
  tax_number?: string;
  phone?: string;
  email?: string;
  address?: string;
  city?: string;
  country: CompanyCountry;
  fiscal_year_start: string;
  base_currency: Currency;
  vat_enabled: boolean;
  vat_rate: number;
  vat_number?: string;
  logo_url?: string;
  odoo_url?: string;
  odoo_db?: string;
  odoo_username?: string;
  odoo_api_key?: string;
  odoo_enabled: boolean;
  created_at: string;
  updated_at: string;
}

// ─── Bank / Cash Accounts ──────────────────────────────────────────────────

export type BankAccountType = 'bank' | 'cash' | 'wallet';
export type BankTransactionDirection = 'deposit' | 'withdrawal';
export type BankTransactionRefType =
  | 'transaction'
  | 'settlement'
  | 'distribution_payment'
  | 'transfer'
  | 'manual'
  | 'opening_balance';

export interface BankAccount {
  id: string;
  owner_id: string;
  name_ar: string;
  name_en?: string;
  account_type: BankAccountType;
  currency: Currency;
  opening_balance: number;
  opening_date: string;
  bank_name?: string;
  account_number?: string;
  iban?: string;
  is_archived: boolean;
  odoo_res_id?: number;
  created_at: string;
  updated_at: string;
}

export interface BankTransaction {
  id: string;
  owner_id: string;
  bank_account_id: string;
  direction: BankTransactionDirection;
  amount: number;
  currency: Currency;
  fx_rate_to_base: number;
  amount_base: number;
  transaction_date: string;
  reference_type: BankTransactionRefType;
  reference_id?: string;
  counterparty_account_id?: string;
  partner_id?: string;
  memo?: string;
  document_id?: string;
  is_reconciled: boolean;
  odoo_res_id?: number;
  created_at: string;
  updated_at: string;
}

/** Computed view — balance per bank/cash account */
export interface BankAccountBalance {
  id: string;
  owner_id: string;
  name_ar: string;
  account_type: BankAccountType;
  currency: Currency;
  balance: number;
  balance_base: number;
}

// ─── Invoicing ───────────────────────────────────────────────────────────────

export type InvoiceStatus = 'draft' | 'issued' | 'paid' | 'partial' | 'void' | 'overdue';

export interface SalesInvoiceLine {
  id: string;
  owner_id: string;
  invoice_id: string;
  line_no: number;
  description_ar?: string;
  description_en?: string;
  quantity: number;
  unit_price: number;
  line_total: number;
  created_at: string;
}

export interface SalesInvoice {
  id: string;
  owner_id: string;
  invoice_number: string;
  project_id?: string;
  partner_id?: string;
  bank_account_id?: string;
  issue_date: string;
  due_date?: string;
  currency: Currency;
  fx_rate_to_base: number;
  subtotal: number;
  vat_rate: number;
  vat_amount: number;
  total: number;
  amount_paid: number;
  status: InvoiceStatus;
  notes?: string;
  odoo_res_id?: number;
  created_at: string;
  updated_at: string;
}

// ─── Inventory ───────────────────────────────────────────────────────────────

export type InventoryCategory = 'feed' | 'fertilizer' | 'seed' | 'medicine' | 'vaccine' | 'supply' | 'other';
export type InventoryMovementType = 'purchase' | 'consume' | 'adjustment' | 'transfer_in' | 'transfer_out' | 'waste';

export interface InventoryItem {
  id: string;
  owner_id: string;
  name_ar: string;
  name_en?: string;
  sku?: string;
  category: InventoryCategory;
  unit: string;
  project_id?: string;
  reorder_level: number;
  default_unit_cost: number;
  currency: Currency;
  is_archived: boolean;
  created_at: string;
  updated_at: string;
}

export interface InventoryMovement {
  id: string;
  owner_id: string;
  item_id: string;
  movement_type: InventoryMovementType;
  quantity: number;
  unit_cost: number;
  currency: Currency;
  fx_rate_to_base: number;
  total_cost_base: number;
  movement_date: string;
  reference_type?: string;
  reference_id?: string;
  notes?: string;
  created_at: string;
  updated_at: string;
}

export interface InventoryStockRow extends InventoryItem {
  quantity_on_hand: number;
}

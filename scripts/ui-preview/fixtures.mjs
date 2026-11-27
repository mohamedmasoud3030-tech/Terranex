/**
 * Synthetic, clearly-labelled fixture rows for the offline UI preview mock.
 * Every reference starts with DEMO-UI so the in-app DemoBanner renders and
 * nothing here can be mistaken for customer evidence.
 *
 * Only the read models the pages actually query are populated; any view not
 * listed resolves to an empty array, which exercises the empty states.
 */
const ORG = '11111111-1111-4111-8111-111111111111';
const USER = '22222222-2222-4222-8222-222222222222';
const RE = '33333333-3333-4333-8333-333333333331';
const AG = '33333333-3333-4333-8333-333333333332';
const LS = '33333333-3333-4333-8333-333333333333';
const PF = '44444444-4444-4444-8444-444444444441';
const NOW = '2026-09-01T09:00:00.000Z';

export const DEMO_USER = {
  id: USER,
  aud: 'authenticated',
  role: 'authenticated',
  email: 'preview@terranex.local',
  email_confirmed_at: NOW,
  app_metadata: { provider: 'email', providers: ['email'] },
  user_metadata: {},
  created_at: NOW,
  updated_at: NOW,
};

const projects = [
  { id: RE, organization_id: ORG, name: 'مشروع النخيل السكني', internal_reference: 'DEMO-UI-RE-001', description: 'تطوير وبيع وحدات سكنية في القاهرة الجديدة.', lifecycle_state: 'FUNDING', reporting_currency: 'EGP', sector: 'REAL_ESTATE', created_at: '2026-03-01T09:00:00.000Z' },
  { id: AG, organization_id: ORG, name: 'مزرعة الوادي — قمح وذرة', internal_reference: 'DEMO-UI-AG-001', description: null, lifecycle_state: 'DRAFT', reporting_currency: 'EGP', sector: 'AGRICULTURE', created_at: '2026-04-01T09:00:00.000Z' },
  { id: LS, organization_id: ORG, name: 'مشروع تسمين العجول', internal_reference: 'DEMO-UI-LS-001', description: 'دورة تسمين موسمية.', lifecycle_state: 'DRAFT', reporting_currency: 'EGP', sector: 'LIVESTOCK', created_at: '2026-05-01T09:00:00.000Z' },
];

const populated = {
  organizations: [{ id: ORG, name: 'شركة تيرانكس للاستثمار (معاينة)', reporting_currency: 'EGP', created_at: NOW }],
  memberships: [{ id: 'm1', organization_id: ORG, user_id: USER, role: 'OWNER', status: 'ACTIVE', created_at: NOW }],
  investment_projects: projects,
  investment_portfolios_read: [
    { id: PF, organization_id: ORG, name: 'محفظة الدلتا', description: 'مشاريع الوجه البحري تحت إدارة واحدة', status: 'ACTIVE', responsible_manager_id: USER, created_by: USER, created_at: NOW, updated_at: NOW },
  ],
  investment_portfolio_state_history_read: [
    { id: 'h1', organization_id: ORG, portfolio_id: PF, previous_status: null, new_status: 'DRAFT', reason: null, changed_by: USER, changed_at: '2026-06-01T09:00:00.000Z' },
    { id: 'h2', organization_id: ORG, portfolio_id: PF, previous_status: 'DRAFT', new_status: 'ACTIVE', reason: 'اعتماد الإدارة', changed_by: USER, changed_at: '2026-06-05T09:00:00.000Z' },
  ],
  portfolio_project_assignments_read: [
    { id: 'a1', organization_id: ORG, portfolio_id: PF, investment_project_id: RE, project_name: projects[0].name, project_sector: 'REAL_ESTATE', project_internal_reference: 'DEMO-UI-RE-001', project_lifecycle_state: 'FUNDING', assigned_by: USER, assigned_at: '2026-06-06T09:00:00.000Z', removed_by: null, removed_at: null, removal_reason: null },
    { id: 'a2', organization_id: ORG, portfolio_id: PF, investment_project_id: AG, project_name: projects[1].name, project_sector: 'AGRICULTURE', project_internal_reference: 'DEMO-UI-AG-001', project_lifecycle_state: 'DRAFT', assigned_by: USER, assigned_at: '2026-06-07T09:00:00.000Z', removed_by: null, removed_at: null, removal_reason: null },
  ],
  project_cash_position_read: [
    { cash_account_id: 'c1', organization_id: ORG, project_id: RE, name: 'البنك الأهلي — حساب المشروع', currency: 'EGP', balance_minor_units: '1250000000', last_posting_date: '2026-08-28' },
    { cash_account_id: 'c2', organization_id: ORG, project_id: RE, name: 'صندوق الموقع', currency: 'EGP', balance_minor_units: '4500000', last_posting_date: '2026-08-30' },
  ],
  cost_obligation_position_read: [
    { obligation_id: 'o1', organization_id: ORG, project_id: RE, party_id: 'p1', description: 'مقاول الهيكل الخرساني — الدفعة الثانية', amount_minor_units: '850000000', currency: 'EGP', transaction_date: '2026-08-10', cost_treatment: 'CAPITALIZABLE_WIP', status: 'AUTHORIZED', prepared_by: USER, authorized_by: USER, authorized_at: '2026-08-11T09:00:00.000Z', created_at: '2026-08-10T09:00:00.000Z', paid_minor_units: '300000000', outstanding_minor_units: '550000000', is_posted: true, is_reversed: false, authorization_batch_id: 'b1', reversal_batch_id: null },
    { obligation_id: 'o2', organization_id: ORG, project_id: RE, party_id: 'p2', description: 'استشاري التصميم — أتعاب', amount_minor_units: '12000000', currency: 'EGP', transaction_date: '2026-08-20', cost_treatment: 'EXPENSE', status: 'DRAFT', prepared_by: USER, authorized_by: null, authorized_at: null, created_at: '2026-08-20T09:00:00.000Z', paid_minor_units: '0', outstanding_minor_units: '12000000', is_posted: false, is_reversed: false, authorization_batch_id: null, reversal_batch_id: null },
  ],
  parties: [
    { id: 'p1', organization_id: ORG, legal_name: 'شركة البناء الحديث', party_type: 'ORGANIZATION' },
    { id: 'p2', organization_id: ORG, legal_name: 'م. أحمد عبد الرحمن', party_type: 'PERSON' },
    { id: 'p3', organization_id: ORG, legal_name: 'مستثمر خاص — محمد علي', party_type: 'PERSON' },
  ],
  project_participants: [
    { id: 'pp1', project_id: RE, party_id: 'p3', role: 'INVESTOR', created_at: NOW, parties: { legal_name: 'مستثمر خاص — محمد علي' } },
  ],
  agreement_versions: [
    { id: 'av1', project_id: RE, version_no: 1, status: 'ACTIVE', effective_date: '2026-03-15', activated_at: '2026-03-15T09:00:00.000Z', terms_hash: 'demo' },
  ],
  project_capital_position_read: [
    { project_id: RE, currency: 'EGP', committed_minor_units: '5000000000', called_minor_units: '2000000000', contributed_minor_units: '1500000000', receivable_minor_units: '500000000' },
  ],
  partner_capital_position_read: [
    { participant_id: 'pp1', agreement_version_id: 'av1', commitment_minor_units: '5000000000', called_minor_units: '2000000000', contributed_minor_units: '1500000000', receivable_minor_units: '500000000', currency: 'EGP' },
  ],
  commitment_terms_read: [
    { id: 'ct1', participant_id: 'pp1', agreement_version_id: 'av1', commitment_minor_units: '5000000000', currency: 'EGP' },
  ],
  capital_calls: [
    { id: 'cc1', project_id: RE, status: 'ISSUED', reference: 'CALL-1', due_date: '2026-07-01', issued_at: '2026-06-01T09:00:00.000Z', agreement_version_id: 'av1' },
  ],
  capital_call_lines_read: [
    { id: 'cl1', capital_call_id: 'cc1', participant_id: 'pp1', amount_minor_units: '2000000000', currency: 'EGP' },
  ],
  contributions_read: [
    { id: 'cn1', project_id: RE, capital_call_id: 'cc1', participant_id: 'pp1', agreement_version_id: 'av1', contribution_minor_units: '1500000000', currency: 'EGP', occurred_on: '2026-06-20', created_at: '2026-06-20T09:00:00.000Z' },
  ],
  accounting_periods_read: [
    { period_id: 'pd1', organization_id: ORG, project_id: RE, reporting_currency: 'EGP', start_date: '2026-07-01', end_date: '2026-09-30', status: 'OPEN', version: 1, supersedes_period_id: null, opened_at: '2026-07-01T09:00:00.000Z', opened_by: USER, closed_at: null, closed_by: null, source_close_run_id: null, source_close_version: null, source_close_snapshot_id: null },
    { period_id: 'pd0', organization_id: ORG, project_id: RE, reporting_currency: 'EGP', start_date: '2026-04-01', end_date: '2026-06-30', status: 'CLOSED', version: 1, supersedes_period_id: null, opened_at: '2026-04-01T09:00:00.000Z', opened_by: USER, closed_at: '2026-07-05T09:00:00.000Z', closed_by: USER, source_close_run_id: 'cr0', source_close_version: 1, source_close_snapshot_id: 'sn0' },
  ],
  real_estate_project_profiles: [
    { id: 'rp1', organization_id: ORG, project_id: RE, strategy: 'DEVELOP_SELL', jurisdiction: 'EG' },
  ],
  property_asset_workspace_read: [
    { property_asset_id: 'pa1', organization_id: ORG, project_id: RE, name: 'قطعة 12 — النخيل', asset_reference: 'DEMO-UI-PA-12', strategy: 'DEVELOP_SELL', jurisdiction: 'EG', operational_state: 'DEVELOPING', state_changed_at: '2026-05-01T09:00:00.000Z', title_status: 'REGISTERED', title_effective_date: '2026-04-10', title_evidence_reference: 'DEED-DEMO', possession_status: 'IN_POSSESSION', possession_effective_date: '2026-04-15', possession_evidence_reference: null, acquisition_id: 'acq1', acquisition_state: 'COMPLETED', contract_reference: 'CT-DEMO-1', contract_date: '2026-04-01', consideration_minor_units: '3000000000', closing_costs_minor_units: '50000000', acquisition_currency: 'EGP', consideration_obligation_id: null, acquisition_payment_status: 'PAID' },
    { property_asset_id: 'pa2', organization_id: ORG, project_id: RE, name: 'قطعة 13 — النخيل', asset_reference: 'DEMO-UI-PA-13', strategy: 'DEVELOP_SELL', jurisdiction: 'EG', operational_state: 'CANDIDATE', state_changed_at: '2026-08-01T09:00:00.000Z', title_status: null, title_effective_date: null, title_evidence_reference: null, possession_status: null, possession_effective_date: null, possession_evidence_reference: null, acquisition_id: null, acquisition_state: 'NOT_STARTED', contract_reference: null, contract_date: null, consideration_minor_units: null, closing_costs_minor_units: null, acquisition_currency: null, consideration_obligation_id: null, acquisition_payment_status: 'NONE' },
  ],
  cross_sector_asset_register_read: [
    { organization_id: ORG, project_id: RE, project_name: projects[0].name, project_sector: 'REAL_ESTATE', project_currency: 'EGP', portfolio_id: PF, portfolio_name: 'محفظة الدلتا', asset_kind: 'PROPERTY_ASSET', asset_id: 'pa1', asset_name: 'قطعة 12 — النخيل', asset_reference: 'DEMO-UI-PA-12', asset_classification: 'DEVELOPMENT', operational_state: 'DEVELOPING', operational_state_basis: 'LIFECYCLE', acquisition_cost_minor_units: '3050000000', acquisition_cost_currency: 'EGP', acquisition_cost_status: 'RECORDED', latest_approved_valuation_minor_units: null, latest_approved_valuation_currency: null, latest_approved_valuation_date: null, latest_approved_valuation_status: 'NOT_RECORDED', realized_result_minor_units: null, realized_result_currency: null, realized_result_status: 'NOT_DISPOSED', registered_by: USER, registered_at: '2026-04-01T09:00:00.000Z' },
    { organization_id: ORG, project_id: AG, project_name: projects[1].name, project_sector: 'AGRICULTURE', project_currency: 'EGP', portfolio_id: PF, portfolio_name: 'محفظة الدلتا', asset_kind: 'FARM', asset_id: 'f1', asset_name: 'مزرعة الوادي الشرقية', asset_reference: null, asset_classification: null, operational_state: 'ACTIVE', operational_state_basis: 'FARM_STATUS', acquisition_cost_minor_units: null, acquisition_cost_currency: null, acquisition_cost_status: 'NOT_APPLICABLE', latest_approved_valuation_minor_units: null, latest_approved_valuation_currency: null, latest_approved_valuation_date: null, latest_approved_valuation_status: 'NOT_APPLICABLE', realized_result_minor_units: null, realized_result_currency: null, realized_result_status: 'NOT_APPLICABLE', registered_by: USER, registered_at: '2026-04-20T09:00:00.000Z' },
  ],
  sector_performance_read: [
    { organization_id: ORG, sector: 'REAL_ESTATE', currency: 'EGP', org_reporting_currency: 'EGP', project_count: 1, asset_count: 2, fx_status: 'SAME_CURRENCY', fx_rate_snapshot_id: null, fx_rate_date: null, cash_balance_minor_units: '1254500000', revenue_recognized_minor_units: '0', cost_of_sale_minor_units: '0', expense_posted_minor_units: '0', wip_posted_minor_units: '850000000', contributions_received_minor_units: '1500000000', receivable_open_minor_units: '0', payable_open_minor_units: '550000000', realized_result_minor_units: '0', converted_cash_balance_minor_units: '1254500000', converted_revenue_recognized_minor_units: '0', converted_contributions_received_minor_units: '1500000000', converted_realized_result_minor_units: '0' },
  ],
  // -------------------------------------------------------------------------
  // H1 qualified-result and by-currency read models (ADR 0034).
  //
  // These were absent from this harness after the H1 tranche landed, so every
  // H1 consumer — the project brief's Capital and Result panels, the project
  // position summary, and the Home sector table — silently rendered its empty
  // state here. The interface looked finished while the domain contract was
  // never exercised in a browser.
  //
  // The real-estate project deliberately holds TWO currencies, and they differ
  // in minor-unit scale (EGP has 2 decimals, OMR has 3). That is the exact
  // shape of the defect the per-currency contracts exist to prevent:
  // 12,545,000.00 EGP and 5,000,000.000 OMR must never surface as one figure.
  // `unclassified_eligible_minor_units` is non-zero so the "not yet classified"
  // disclosure is visible too, not just present in CSS.
  // -------------------------------------------------------------------------
  project_cash_by_currency_read: [
    { organization_id: ORG, project_id: RE, currency: 'EGP', account_count: 2, cash_balance_minor_units: '1254500000', posted_line_count: 34, currency_mismatch_line_count: 0, has_active_posted_movement: true },
    { organization_id: ORG, project_id: RE, currency: 'OMR', account_count: 1, cash_balance_minor_units: '5000000000', posted_line_count: 6, currency_mismatch_line_count: 1, has_active_posted_movement: true },
    { organization_id: ORG, project_id: AG, currency: 'EGP', account_count: 1, cash_balance_minor_units: '240000000', posted_line_count: 12, currency_mismatch_line_count: 0, has_active_posted_movement: true },
    { organization_id: ORG, project_id: LS, currency: 'EGP', account_count: 1, cash_balance_minor_units: '88000000', posted_line_count: 8, currency_mismatch_line_count: 0, has_active_posted_movement: false },
  ],
  project_capital_by_currency_read: [
    { organization_id: ORG, project_id: RE, currency: 'EGP', committed_minor_units: '150000000000', called_minor_units: '150000000000', contributed_minor_units: '150000000000', receivable_minor_units: '0', uncalled_minor_units: '0', call_line_count: 3 },
    { organization_id: ORG, project_id: RE, currency: 'USD', committed_minor_units: '20000000', called_minor_units: '10000000', contributed_minor_units: '10000000', receivable_minor_units: '10000000', uncalled_minor_units: '10000000', call_line_count: 2 },
    { organization_id: ORG, project_id: AG, currency: 'EGP', committed_minor_units: '40000000000', called_minor_units: '25000000000', contributed_minor_units: '25000000000', receivable_minor_units: '15000000000', uncalled_minor_units: '15000000000', call_line_count: 2 },
  ],
  project_result_by_currency_read: [
    {
      project_id: RE, organization_id: ORG, sector: 'REAL_ESTATE', currency: 'EGP',
      result_basis: 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
      cost_classification_status: 'PARTIAL',
      evidence_status: 'COMPLETE',
      management_result: {
        amount_minor_units: '480000000', currency: 'EGP',
        basis: 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
        cost_classification_status: 'PARTIAL', evidence_status: 'COMPLETE',
        policy_availability: ['BD-006', 'BD-008'], as_of: '2026-09-01',
      },
      sale_revenue_minor_units: '900000000', rental_revenue_minor_units: '150000000',
      cogs_derecognized_minor_units: '420000000', realized_disposal_minor_units: '500000000',
      selling_costs_minor_units: '20000000', attributed_operating_cost_minor_units: '520000000',
      selling_cost_attributed_minor_units: '20000000', project_overhead_minor_units: '120000000',
      excluded_from_result_minor_units: '20000000', unclassified_eligible_minor_units: '35000000',
      expense_outside_classification_scope_minor_units: '0',
      result_revenue_minor_units: '1050000000', result_deducted_cost_minor_units: '570000000',
      evidence_evidenced_count: 4, evidence_subject_count: 4, as_of: '2026-09-01',
    },
    {
      project_id: RE, organization_id: ORG, sector: 'REAL_ESTATE', currency: 'OMR',
      result_basis: 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
      cost_classification_status: 'COMPLETE',
      evidence_status: 'COMPLETE',
      management_result: {
        amount_minor_units: '185000000', currency: 'OMR',
        basis: 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
        cost_classification_status: 'COMPLETE', evidence_status: 'COMPLETE',
        policy_availability: ['BD-006', 'BD-008'], as_of: '2026-09-01',
      },
      sale_revenue_minor_units: '400000000', rental_revenue_minor_units: '0',
      cogs_derecognized_minor_units: '200000000', realized_disposal_minor_units: '200000000',
      selling_costs_minor_units: '15000000', attributed_operating_cost_minor_units: '215000000',
      selling_cost_attributed_minor_units: '15000000', project_overhead_minor_units: '0',
      excluded_from_result_minor_units: '0', unclassified_eligible_minor_units: '0',
      expense_outside_classification_scope_minor_units: '0',
      result_revenue_minor_units: '400000000', result_deducted_cost_minor_units: '215000000',
      evidence_evidenced_count: 2, evidence_subject_count: 2, as_of: '2026-09-01',
    },
    {
      project_id: AG, organization_id: ORG, sector: 'AGRICULTURE', currency: 'EGP',
      result_basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
      cost_classification_status: 'PARTIAL',
      evidence_status: 'PARTIAL',
      management_result: {
        amount_minor_units: '62000000', currency: 'EGP',
        basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
        cost_classification_status: 'PARTIAL', evidence_status: 'PARTIAL',
        policy_availability: ['BD-006', 'BD-008'], as_of: '2026-09-01',
      },
      sale_revenue_minor_units: '210000000', rental_revenue_minor_units: '0',
      cogs_derecognized_minor_units: '0', realized_disposal_minor_units: '0',
      selling_costs_minor_units: '0', attributed_operating_cost_minor_units: '148000000',
      selling_cost_attributed_minor_units: '0', project_overhead_minor_units: '0',
      excluded_from_result_minor_units: '0', unclassified_eligible_minor_units: '9000000',
      expense_outside_classification_scope_minor_units: '0',
      result_revenue_minor_units: '210000000', result_deducted_cost_minor_units: '148000000',
      evidence_evidenced_count: 3, evidence_subject_count: 5, as_of: '2026-09-01',
    },
  ],
  sector_management_result_read: [
    {
      organization_id: ORG, sector: 'REAL_ESTATE', currency: 'EGP', project_count: 1,
      result_basis: 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
      cost_classification_status: 'PARTIAL', evidence_status: 'COMPLETE',
      management_result: {
        amount_minor_units: '480000000', currency: 'EGP',
        basis: 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
        cost_classification_status: 'PARTIAL', evidence_status: 'COMPLETE',
        policy_availability: ['BD-006', 'BD-008'], as_of: '2026-09-01',
      },
      sale_revenue_minor_units: '900000000', rental_revenue_minor_units: '150000000',
      realized_disposal_minor_units: '500000000', selling_costs_minor_units: '20000000',
      attributed_operating_cost_minor_units: '520000000',
      selling_cost_attributed_minor_units: '20000000', project_overhead_minor_units: '120000000',
      excluded_from_result_minor_units: '20000000', unclassified_eligible_minor_units: '35000000',
      expense_outside_classification_scope_minor_units: '0',
      result_deducted_cost_minor_units: '570000000',
      evidence_evidenced_count: 4, evidence_subject_count: 4, as_of: '2026-09-01',
    },
    {
      organization_id: ORG, sector: 'AGRICULTURE', currency: 'EGP', project_count: 1,
      result_basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
      cost_classification_status: 'PARTIAL', evidence_status: 'PARTIAL',
      management_result: {
        amount_minor_units: '62000000', currency: 'EGP',
        basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
        cost_classification_status: 'PARTIAL', evidence_status: 'PARTIAL',
        policy_availability: ['BD-006', 'BD-008'], as_of: '2026-09-01',
      },
      sale_revenue_minor_units: '210000000', rental_revenue_minor_units: '0',
      realized_disposal_minor_units: '0', selling_costs_minor_units: '0',
      attributed_operating_cost_minor_units: '148000000',
      selling_cost_attributed_minor_units: '0', project_overhead_minor_units: '0',
      excluded_from_result_minor_units: '0', unclassified_eligible_minor_units: '9000000',
      expense_outside_classification_scope_minor_units: '0',
      result_deducted_cost_minor_units: '148000000',
      evidence_evidenced_count: 3, evidence_subject_count: 5, as_of: '2026-09-01',
    },
  ],
  organization_financial_consolidation_read: [
    { organization_id: ORG, level: 'CONSOLIDATED', currency: null, org_reporting_currency: 'EGP', project_count: 3, cash_balance_minor_units: '1254500000', receivable_open_minor_units: '0', revenue_recognized_minor_units: '0', cost_of_sale_minor_units: '0', expense_posted_minor_units: '0', wip_posted_minor_units: '850000000', contributions_received_minor_units: '1500000000', payable_open_minor_units: '550000000', paid_minor_units: '300000000', retention_held_minor_units: '0', disputed_obligations: 0, overdue_obligations: 1, fx_status: 'CONSOLIDATED_AT_RATE', converted_cash_balance_minor_units: '1254500000', converted_payable_open_minor_units: '550000000', converted_paid_minor_units: '300000000' },
  ],
  financial_integrity_signals_read: [
    { organization_id: ORG, project_id: RE, signal_code: 'OBLIGATION_OVERDUE', signal_label_ar: 'التزامات متأخرة السداد', severity: 'WARNING', subject_count: 1, amount_minor_units: '550000000', currency: 'EGP' },
    { organization_id: ORG, project_id: RE, signal_code: 'BANK_LINES_UNRECONCILED', signal_label_ar: 'سطور بنكية غير مطابقة', severity: 'CRITICAL', subject_count: 3, amount_minor_units: null, currency: 'EGP' },
  ],
  bank_statement_line_status_read: [
    { line_id: 'bl1', organization_id: ORG, project_id: RE, cash_account_id: 'c1', transaction_date: '2026-08-29', amount_minor_units: '150000000', currency: 'EGP', description: 'تحويل وارد — دفعة من مشترٍ', provider_reference: 'DEMO-UI-BANK-001', is_reconciled: false },
    { line_id: 'bl2', organization_id: ORG, project_id: RE, cash_account_id: 'c1', transaction_date: '2026-08-31', amount_minor_units: '25000000', currency: 'EGP', description: 'إيداع نقدي فرع التجمع', provider_reference: 'DEMO-UI-BANK-002', is_reconciled: false },
  ],
  // --- Cost control, per currency -----------------------------------------
  // `property_cost_control_read` unions budget lines and cost items into `keys`
  // keyed by (organization, project, asset, parcel, phase, category, currency),
  // so a category that has both an EGP obligation and an OMR obligation is TWO
  // rows. That is the shape that makes the `/operations` summary unsafe if it
  // reduces the rows into one scalar, so the fixture must contain it.
  property_cost_control_read: [
    { organization_id: ORG, project_id: RE, property_asset_id: 'pa1', parcel_id: null, phase_id: null, cost_category: 'CONSTRUCTION', currency: 'EGP', budget_minor_units: '900000000', committed_minor_units: '600000000', actual_minor_units: '350000000', variance_minor_units: '550000000' },
    { organization_id: ORG, project_id: RE, property_asset_id: 'pa1', parcel_id: null, phase_id: null, cost_category: 'CONSTRUCTION', currency: 'OMR', budget_minor_units: '12000000', committed_minor_units: '8000000', actual_minor_units: '4000000', variance_minor_units: '8000000' },
    { organization_id: ORG, project_id: RE, property_asset_id: 'pa1', parcel_id: null, phase_id: null, cost_category: 'DESIGN', currency: 'EGP', budget_minor_units: '40000000', committed_minor_units: '40000000', actual_minor_units: '40000000', variance_minor_units: '0' },
  ],
  property_cost_drilldown_read: [
    { property_cost_item_id: 'pci1', organization_id: ORG, project_id: RE, property_asset_id: 'pa1', parcel_id: null, phase_id: null, cost_category: 'CONSTRUCTION', policy_reference: 'POL-CONST-01', obligation_id: 'ob1', description: 'أعمال خرسانة — المقاول الرئيسي', cost_treatment: 'CAPITALIZABLE_WIP', obligation_status: 'AUTHORIZED', obligation_minor_units: '600000000', currency: 'EGP', committed_minor_units: '600000000', actual_minor_units: '350000000', originating_batch_id: 'jb1', is_reversed: false, authorized_at: '2026-05-10T09:00:00.000Z', classified_at: '2026-05-12T09:00:00.000Z' },
    { property_cost_item_id: 'pci2', organization_id: ORG, project_id: RE, property_asset_id: 'pa1', parcel_id: null, phase_id: null, cost_category: 'CONSTRUCTION', policy_reference: 'POL-CONST-01', obligation_id: 'ob2', description: 'توريد حديد — أمر شراء خارجي', cost_treatment: 'CAPITALIZABLE_WIP', obligation_status: 'AUTHORIZED', obligation_minor_units: '8000000', currency: 'OMR', committed_minor_units: '8000000', actual_minor_units: '4000000', originating_batch_id: 'jb2', is_reversed: false, authorized_at: '2026-06-02T09:00:00.000Z', classified_at: '2026-06-03T09:00:00.000Z' },
  ],
  // --- Official project position ------------------------------------------
  // One row per project: the view is driven by `investment_projects` and joins
  // each CTE on `currency = reporting_currency`, so the row is the reporting
  // currency's slice. A second currency here would contradict the contract.
  project_financial_position_read: [
    { project_id: RE, organization_id: ORG, project_name: 'مشروع النخيل السكني', sector: 'REAL_ESTATE', currency: 'EGP', cash_balance_minor_units: '1254500000', receivable_open_minor_units: '0', revenue_recognized_minor_units: '0', cost_of_sale_minor_units: '0', expense_posted_minor_units: '0', wip_posted_minor_units: '850000000', contributions_received_minor_units: '1500000000', payable_open_minor_units: '550000000', paid_minor_units: '300000000', retention_held_minor_units: '0', retention_declared_minor_units: '0', disputed_obligations: 0, overdue_obligations: 1, overdue_outstanding_minor_units: '550000000', budget_expense_minor_units: '0', budget_wip_minor_units: '900000000', committed_expense_minor_units: '0', committed_wip_minor_units: '600000000', available_expense_minor_units: '0', available_wip_minor_units: '300000000' },
  ],
  // --- Approval exception registry ----------------------------------------
  approval_exception_registry_read: [
    { exception_id: 'ex1', organization_id: ORG, project_id: RE, domain: 'PROCUREMENT_TOLERANCE', subject_type: 'supplier_invoice', subject_id: 'inv1', exception_kind: 'PRICE_TOLERANCE_EXCEEDED', amount_minor_units: '1250000', currency: 'EGP', status: 'OPEN', opened_by: USER, opened_at: '2026-08-20T09:00:00.000Z', decided_by: null, decided_at: null, reason: 'تجاوز سعر الفاتورة حد التسامح المعتمد.', severity: 'MEDIUM', owner_id: USER, due_date: '2026-09-20', replaces_exception_id: null },
  ],
  s7_pilot_acceptance_report_read: [
    { project_id: RE, organization_id: ORG, reporting_currency: 'EGP', posted_opening_imports: 1, opening_import_rejected_rows: 0, opening_control_totals_match: true, reconciliation_checkpoints: 2, reconciliation_non_zero_variances: 0, reconciliation_max_abs_variance_minor_units: '0', unresolved_exceptions: 0, unresolved_critical_exceptions: 0, unreconciled_bank_statement_lines: 3, unbalanced_journal_batches: 0, end_to_end_result: 'PASS', backup_restore_result: 'NOT_RUN', access_revocation_result: 'PASS', uat_total_tasks: 0, uat_accepted_tasks: 0, uat_rejected_tasks: 0, human_uat_status: 'NOT_STARTED' },
  ],
};

const empty = {
  organizations: populated.organizations,
  memberships: populated.memberships,
};

export const fixtures = { populated, empty };

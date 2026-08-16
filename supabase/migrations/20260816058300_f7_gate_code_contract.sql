-- F7 gate-code contract widening: the OPEN_APPROVAL_EXCEPTIONS gate joins
-- the canonical close-gate vocabulary. The CHECK on close_run_gates.gate_code
-- is widened in place; no existing row or gate is weakened.

alter table public.close_run_gates
  drop constraint close_run_gates_gate_code_check;

alter table public.close_run_gates
  add constraint close_run_gates_gate_code_check check (gate_code in (
    'JOURNAL_BATCHES_BALANCED',
    'BANK_RECONCILIATION_COVERAGE',
    'SUSPENSE_CONTROL_ACCOUNTS',
    'RECEIVABLE_PAYABLE_AGING',
    'ASSET_SECTOR_ROLLFORWARDS',
    'EVIDENCE_AND_APPROVALS',
    'POSTING_CURRENCY_RULES',
    'SECTOR_CUT_OFF',
    'PARTNER_CAPITAL_ROLLFORWARD',
    'OPEN_APPROVAL_EXCEPTIONS',
    'CLOSE_REPORT_AND_EXCEPTIONS'
  ));

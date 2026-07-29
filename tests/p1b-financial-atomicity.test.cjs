const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

test('finance write boundary calls the registered Supabase client and never flushes local writes', () => {
  const boundary = read('src/features/finance/financeWriteBoundary.ts');

  assert.match(boundary, /requireClient\(\)/);
  assert.match(boundary, /client\.rpc\(rpc,/);
  assert.match(boundary, /crypto\.randomUUID\(\)/);
  assert.match(boundary, /rehydrateFinanceStores/);
  assert.match(boundary, /rehydrateStockStores/);
  assert.doesNotMatch(boundary, /\.flush\(\)/);
});

test('all six P1B RPCs are reached from production workflows', () => {
  const transactions = read('src/features/transactions/deferredExpenseWorkflow.ts');
  const settlements = read('src/features/settlements/posting.ts');
  const stock = read('src/features/events/stockAdjustmentWorkflow.ts');
  const financeHub = read('src/features/finance/FinanceHub.tsx');
  const operationsHub = read('src/features/operations/OperationsHub.tsx');

  for (const index of [0, 1, 2]) {
    assert.match(transactions, new RegExp(`P1B_ATOMIC_RPC_NAMES\\[${index}\\]`));
  }
  for (const index of [3, 4]) {
    assert.match(settlements, new RegExp(`P1B_ATOMIC_RPC_NAMES\\[${index}\\]`));
  }
  assert.match(stock, /P1B_ATOMIC_RPC_NAMES\[5\]/);
  assert.match(transactions, /invokeFinanceRpc/);
  assert.match(settlements, /invokeFinanceRpc/);
  assert.match(stock, /invokeFinanceRpc/);
  assert.match(financeHub, /createTransactionWithOptionalPayableAtomic/);
  assert.match(financeHub, /recordSettlementWithAllocationsAtomic/);
  assert.match(financeHub, /reverseSettlementAtomic/);
  assert.match(operationsHub, /recordStockAdjustmentAtomic/);
});

test('database boundary is owner-scoped, append-only and concurrency-safe', () => {
  const foundation = read('supabase/migrations/20260729000100_p1b_financial_rpcs_and_audit.sql');
  const functions = read('supabase/migrations/20260729000200_p1b_financial_rpc_hardening.sql');
  const retry = read('supabase/migrations/20260729000300_p1b_idempotency_preflight.sql');

  assert.match(foundation, /unique \(owner_id, request_id\)/i);
  assert.match(foundation, /for insert\s+with check \(false\)/i);
  assert.match(foundation, /for update\s+using \(false\)\s+with check \(false\)/i);
  assert.match(foundation, /for delete\s+using \(false\)/i);
  assert.match(foundation, /revoke insert, update, delete/i);
  assert.match(functions, /pg_advisory_xact_lock/);
  assert.match(functions, /terranex_assert_owner/);
  assert.match(functions, /unsupported transaction update field/);
  assert.match(retry, /record_transaction_atomic_core/);
  assert.match(retry, /terranex_audit_check_idempotent\(p_request_id\)/);

  for (const rpc of [
    'record_transaction_atomic',
    'update_transaction_atomic',
    'delete_transaction_atomic',
    'record_settlement_atomic',
    'reverse_settlement_atomic',
    'record_stock_adjustment_atomic',
  ]) {
    assert.match(`${functions}\n${retry}`, new RegExp(`function public\\.${rpc}\\(`));
  }
});

test('real PostgreSQL suite covers every RPC plus rollback and owner isolation', () => {
  const suite = read('supabase/tests/05_p1b_financial_rpcs.sql');

  for (const rpc of [
    'record_transaction_atomic',
    'update_transaction_atomic',
    'delete_transaction_atomic',
    'record_settlement_atomic',
    'reverse_settlement_atomic',
    'record_stock_adjustment_atomic',
  ]) {
    assert.match(suite, new RegExp(`public\\.${rpc}\\(`));
  }

  assert.match(suite, /atomic rollback/i);
  assert.match(suite, /owner isolation/i);
  assert.match(suite, /append-only audit/i);
  assert.match(suite, /search_path/i);
});

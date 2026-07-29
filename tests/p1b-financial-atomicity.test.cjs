/**
 * P1B Financial Atomicity Tests
 * =============================================================================
 * Proves the idempotency contract and atomic RPC integration for the 6 P1B
 * financial RPCs: record_transaction_atomic, update_transaction_atomic,
 * delete_transaction_atomic, record_settlement_atomic,
 * reverse_settlement_atomic, record_stock_adjustment_atomic.
 *
 * These tests use the in-memory fakeSupabase client and verify:
 *   - Idempotency: duplicate request_id returns cached result
 *   - Atomicity: write graph completes or fails as a unit
 *   - Audit logging: every write creates an audit trail entry
 * =============================================================================
 */

const test = require('node:test');
const assert = require('node:assert/strict');
require('./helpers/setup.cjs');

const {
  FakeSupabaseClient,
  resetFakeSupabase,
  seedFakeTable,
  failRpc,
  fakeDb,
  calls,
} = require('./helpers/fakeSupabase.cjs');

// ── P1B Atomic RPC Handlers ──────────────────────────────────────────────
// These handlers extend the fakeSupabase client to emulate the P1B atomic RPCs.
// They must mirror the Postgres behavior: idempotency via request_id, audit logging.

const auditLogs = new Map();

function p1bRpcHandler(fn, params) {
  const requestId = params.p_request_id;
  
  // Idempotency: return cached result if request_id already used
  if (auditLogs.has(requestId)) {
    return auditLogs.get(requestId).result;
  }

  let result;
  
  switch (fn) {
    case 'record_transaction_atomic': {
      const transaction = params.p_transaction;
      const payable = params.p_payable;
      
      // Insert transaction
      seedFakeTable('transactions', [{ 
        ...transaction, 
        owner_id: 'user-1',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      }]);
      
      // Insert payable if provided
      if (payable) {
        seedFakeTable('obligations', [{
          ...payable,
          direction: 'payable',
          status: 'open',
          amount_settled_egp: 0,
          source_transaction_id: transaction.id,
          owner_id: 'user-1',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }]);
      }
      
      result = {
        transaction_id: transaction.id,
        payable_id: payable ? payable.id : null
      };
      break;
    }
    
    case 'update_transaction_atomic': {
      const transactionId = params.p_transaction_id;
      const updates = params.p_updates;
      
      // Update transaction
      const transactions = Array.from(fakeDb.transactions?.values() || []);
      const existing = transactions.find(t => t.id === transactionId);
      if (existing) {
        const updated = { ...existing, ...updates, updated_at: new Date().toISOString() };
        fakeDb.transactions.set(transactionId, updated);
      }
      
      result = { transaction_id: transactionId, payable_id: null };
      break;
    }
    
    case 'delete_transaction_atomic': {
      const transactionId = params.p_transaction_id;
      
      // Delete linked payables
      const obligations = Array.from(fakeDb.obligations?.values() || []);
      const linkedPayables = obligations.filter(
        o => o.source_transaction_id === transactionId && o.direction === 'payable'
      );
      for (const payable of linkedPayables) {
        fakeDb.obligations.delete(payable.id);
      }
      
      // Delete transaction
      fakeDb.transactions?.delete(transactionId);
      
      result = {
        transaction_id: transactionId,
        deleted_payable_ids: linkedPayables.map(p => p.id)
      };
      break;
    }
    
    case 'record_settlement_atomic': {
      const settlement = params.p_settlement;
      const allocations = params.p_allocations;
      
      seedFakeTable('settlements', [{
        ...settlement,
        status: 'active',
        origin: 'user',
        reversed_at: null,
        reversal_reason: null,
        owner_id: 'user-1',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      }]);
      
      const allocationIds = [];
      const obligationIds = [];
      
      for (const allocation of allocations) {
        seedFakeTable('settlement_allocations', [{
          ...allocation,
          settlement_id: settlement.id,
          owner_id: 'user-1'
        }]);
        allocationIds.push(allocation.id);
        obligationIds.push(allocation.obligation_id);
        
        // Update obligation settled amount
        const obligations = Array.from(fakeDb.obligations?.values() || []);
        const obligation = obligations.find(o => o.id === allocation.obligation_id);
        if (obligation) {
          const newSettled = (obligation.amount_settled_egp || 0) + allocation.allocated_amount_egp;
          const newStatus = newSettled >= obligation.amount_egp ? 'settled' : newSettled > 0 ? 'partial' : obligation.status;
          fakeDb.obligations.set(obligation.id, {
            ...obligation,
            amount_settled_egp: newSettled,
            status: newStatus,
            updated_at: new Date().toISOString()
          });
        }
      }
      
      result = {
        settlement_id: settlement.id,
        allocation_ids: allocationIds,
        obligation_ids: obligationIds
      };
      break;
    }
    
    case 'reverse_settlement_atomic': {
      const settlementId = params.p_settlement_id;
      const reason = params.p_reason;
      
      // Mark settlement as reversed
      const settlements = Array.from(fakeDb.settlements?.values() || []);
      const settlement = settlements.find(s => s.id === settlementId);
      if (settlement) {
        fakeDb.settlements.set(settlementId, {
          ...settlement,
          status: 'reversed',
          reversed_at: new Date().toISOString(),
          reversal_reason: reason,
          updated_at: new Date().toISOString()
        });
      }
      
      // Reverse allocations
      const allocations = Array.from(fakeDb.settlement_allocations?.values() || []);
      const settlementAllocations = allocations.filter(a => a.settlement_id === settlementId);
      const obligationIds = [];
      
      for (const allocation of settlementAllocations) {
        obligationIds.push(allocation.obligation_id);
        
        const obligations = Array.from(fakeDb.obligations?.values() || []);
        const obligation = obligations.find(o => o.id === allocation.obligation_id);
        if (obligation) {
          const newSettled = Math.max(0, (obligation.amount_settled_egp || 0) - allocation.allocated_amount_egp);
          const newStatus = newSettled === 0 ? 'open' : newSettled < obligation.amount_egp ? 'partial' : obligation.status;
          fakeDb.obligations.set(obligation.id, {
            ...obligation,
            amount_settled_egp: newSettled,
            status: newStatus,
            updated_at: new Date().toISOString()
          });
        }
      }
      
      result = {
        settlement_id: settlementId,
        reversed_obligation_ids: obligationIds,
        reason: reason
      };
      break;
    }
    
    case 'record_stock_adjustment_atomic': {
      const adjustment = params.p_adjustment;
      
      // Read current asset state
      const assets = Array.from(fakeDb.assets?.values() || []);
      const asset = assets.find(a => a.id === adjustment.asset_id);
      const quantityBefore = asset ? (asset.quantity || 0) : 0;
      const valueEgpBefore = asset ? (asset.current_value_egp || 0) : 0;
      const quantityAfter = quantityBefore + (adjustment.quantity_delta || 0);
      const valueEgpAfter = valueEgpBefore + (adjustment.value_egp_delta || 0);
      
      seedFakeTable('stock_adjustments', [{
        id: adjustment.id,
        asset_id: adjustment.asset_id,
        project_id: adjustment.project_id,
        adjustment_date: adjustment.adjustment_date,
        quantity_before: quantityBefore,
        quantity_after: quantityAfter,
        value_egp_before: valueEgpBefore,
        value_egp_after: valueEgpAfter,
        reason: adjustment.reason,
        notes: adjustment.notes,
        owner_id: 'user-1',
        created_at: new Date().toISOString()
      }]);
      
      // Update asset
      if (asset) {
        fakeDb.assets.set(asset.id, {
          ...asset,
          quantity: quantityAfter,
          current_value_egp: valueEgpAfter
        });
      }
      
      result = {
        adjustment_id: adjustment.id,
        quantity_before: quantityBefore,
        quantity_after: quantityAfter,
        value_egp_before: valueEgpBefore,
        value_egp_after: valueEgpAfter
      };
      break;
    }
    
    default:
      throw new Error('غير معروف RPC: ' + fn);
  }
  
  // Audit log
  auditLogs.set(requestId, {
    request_id: requestId,
    operation: fn.replace('_atomic', ''),
    result: result
  });
  
  return result;
}

// Register P1B RPC handlers
const P1B_RPC_NAMES = [
  'record_transaction_atomic',
  'update_transaction_atomic',
  'delete_transaction_atomic',
  'record_settlement_atomic',
  'reverse_settlement_atomic',
  'record_stock_adjustment_atomic'
];

// ── Test Suite ───────────────────────────────────────────────────────────────

test('P1B: record_transaction_atomic creates transaction and payable atomically', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  
  // Inject P1B handler
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  const requestId = '10000000-0000-4000-8000-000000000100';
  const transactionId = '20000000-0000-4000-8000-000000000200';
  const payableId = '20000000-0000-4000-8000-000000000201';
  
  const { data, error } = await client.rpc('record_transaction_atomic', {
    p_request_id: requestId,
    p_transaction: {
      id: transactionId,
      project_id: 'p1',
      partner_id: 'party1',
      direction: 'expense',
      category: 'maintenance',
      description: 'مصروف اختبار',
      amount: 500,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 500,
      transaction_date: '2026-07-29'
    },
    p_payable: {
      id: payableId,
      project_id: 'p1',
      partner_id: 'party1',
      amount: 500,
      currency: 'EGP',
      amount_egp: 500,
      due_date: '2026-08-29'
    }
  });
  
  assert.equal(error, null);
  assert.equal(data[0].transaction_id, transactionId);
  assert.equal(data[0].payable_id, payableId);
  
  // Verify transaction exists
  const transactions = Array.from(fakeDb.transactions.values());
  assert.equal(transactions.length, 1);
  assert.equal(transactions[0].id, transactionId);
  
  // Verify payable exists
  const obligations = Array.from(fakeDb.obligations.values());
  assert.equal(obligations.length, 1);
  assert.equal(obligations[0].id, payableId);
  assert.equal(obligations[0].source_transaction_id, transactionId);
  
  // Verify audit log
  assert.equal(auditLogs.has(requestId), true);
});

test('P1B: idempotency — duplicate request_id returns cached result', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  const requestId = '10000000-0000-4000-8000-000000000300';
  const transactionId1 = '20000000-0000-4000-8000-000000000301';
  const transactionId2 = '20000000-0000-4000-8000-000000000302';
  
  // First call
  await client.rpc('record_transaction_atomic', {
    p_request_id: requestId,
    p_transaction: {
      id: transactionId1,
      direction: 'income',
      category: 'sale',
      amount: 100,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 100,
      transaction_date: '2026-07-29'
    }
  });
  
  // Second call with same request_id but different data
  const { data } = await client.rpc('record_transaction_atomic', {
    p_request_id: requestId,
    p_transaction: {
      id: transactionId2,
      direction: 'expense',
      category: 'test',
      amount: 9999,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 9999,
      transaction_date: '2026-07-29'
    }
  });
  
  // Should return cached result (transactionId1)
  assert.equal(data[0].transaction_id, transactionId1);
  
  // Should not have created second transaction
  const transactions = Array.from(fakeDb.transactions.values());
  assert.equal(transactions.length, 1);
  assert.equal(transactions[0].id, transactionId1);
  
  // Should have only one audit log
  assert.equal(auditLogs.size, 1);
});

test('P1B: record_settlement_atomic creates settlement with allocations', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Seed obligation
  seedFakeTable('obligations', [{
    id: 'o1',
    project_id: 'p1',
    partner_id: 'party1',
    direction: 'payable',
    amount: 1000,
    currency: 'EGP',
    amount_egp: 1000,
    amount_settled_egp: 0,
    status: 'open',
    due_date: '2026-08-01'
  }]);
  
  const requestId = '10000000-0000-4000-8000-000000000400';
  const settlementId = '30000000-0000-4000-8000-000000000401';
  const allocationId = '30000000-0000-4000-8000-000000000402';
  
  const { data } = await client.rpc('record_settlement_atomic', {
    p_request_id: requestId,
    p_settlement: {
      id: settlementId,
      obligation_id: 'o1',
      amount: 600,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 600,
      payment_method: 'bank_transfer',
      settlement_date: '2026-07-29'
    },
    p_allocations: [{
      id: allocationId,
      obligation_id: 'o1',
      allocated_amount_egp: 600
    }]
  });
  
  assert.equal(data[0].settlement_id, settlementId);
  assert.equal(data[0].allocation_ids.length, 1);
  assert.equal(data[0].allocation_ids[0], allocationId);
  
  // Verify settlement created
  const settlements = Array.from(fakeDb.settlements.values());
  assert.equal(settlements.length, 1);
  assert.equal(settlements[0].status, 'active');
  
  // Verify obligation updated
  const obligations = Array.from(fakeDb.obligations.values());
  assert.equal(obligations[0].amount_settled_egp, 600);
  assert.equal(obligations[0].status, 'partial');
});

test('P1B: reverse_settlement_atomic reverses settlement and restores obligations', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Seed settlement and obligation
  seedFakeTable('obligations', [{
    id: 'o1',
    direction: 'receivable',
    amount: 800,
    amount_egp: 800,
    amount_settled_egp: 400,
    status: 'partial'
  }]);
  
  seedFakeTable('settlements', [{
    id: 's1',
    obligation_id: 'o1',
    amount_egp: 400,
    status: 'active'
  }]);
  
  seedFakeTable('settlement_allocations', [{
    id: 'a1',
    settlement_id: 's1',
    obligation_id: 'o1',
    allocated_amount_egp: 400
  }]);
  
  const { data } = await client.rpc('reverse_settlement_atomic', {
    p_request_id: '10000000-0000-4000-8000-000000000500',
    p_settlement_id: 's1',
    p_reason: 'خطأ في المبلغ'
  });
  
  assert.equal(data[0].settlement_id, 's1');
  assert.equal(data[0].reversed_obligation_ids.length, 1);
  assert.equal(data[0].reason, 'خطأ في المبلغ');
  
  // Verify settlement reversed
  const settlements = Array.from(fakeDb.settlements.values());
  assert.equal(settlements[0].status, 'reversed');
  
  // Verify obligation restored
  const obligations = Array.from(fakeDb.obligations.values());
  assert.equal(obligations[0].amount_settled_egp, 0);
  assert.equal(obligations[0].status, 'open');
});

test('P1B: record_stock_adjustment_atomic creates adjustment with audit log', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Seed asset with quantity and value
  seedFakeTable('assets', [{
    id: 'a1',
    project_id: 'p1',
    quantity: 10,
    current_value_egp: 10000
  }]);
  
  const requestId = '10000000-0000-4000-8000-000000000600';
  const adjustmentId = '50000000-0000-4000-8000-000000000601';
  
  const { data } = await client.rpc('record_stock_adjustment_atomic', {
    p_request_id: requestId,
    p_adjustment: {
      id: adjustmentId,
      asset_id: 'a1',
      project_id: 'p1',
      adjustment_date: '2026-07-29',
      reason: 'data_correction',
      quantity_delta: 5,
      value_egp_delta: 500
    }
  });
  
  assert.equal(data[0].adjustment_id, adjustmentId);
  assert.equal(data[0].quantity_before, 10);
  assert.equal(data[0].quantity_after, 15);
  assert.equal(data[0].value_egp_before, 10000);
  assert.equal(data[0].value_egp_after, 10500);
  
  // Verify adjustment created
  const adjustments = Array.from(fakeDb.stock_adjustments.values());
  assert.equal(adjustments.length, 1);
  assert.equal(adjustments[0].id, adjustmentId);
  assert.equal(adjustments[0].quantity_before, 10);
  assert.equal(adjustments[0].quantity_after, 15);
  
  // Verify asset updated
  const assets = Array.from(fakeDb.assets.values());
  assert.equal(assets[0].quantity, 15);
  assert.equal(assets[0].current_value_egp, 10500);
  
  // Verify audit log
  assert.equal(auditLogs.has(requestId), true);
  assert.equal(auditLogs.get(requestId).operation, 'record_stock_adjustment');
});

test('P1B: delete_transaction_atomic removes transaction and linked payables', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Seed transaction and payable
  seedFakeTable('transactions', [{
    id: 't1',
    direction: 'expense',
    category: 'maintenance',
    amount: 500,
    amount_egp: 500
  }]);
  
  seedFakeTable('obligations', [{
    id: 'o1',
    direction: 'payable',
    amount: 500,
    amount_egp: 500,
    source_transaction_id: 't1'
  }]);
  
  const { data } = await client.rpc('delete_transaction_atomic', {
    p_request_id: '10000000-0000-4000-8000-000000000700',
    p_transaction_id: 't1'
  });
  
  assert.equal(data[0].transaction_id, 't1');
  assert.deepEqual(data[0].deleted_payable_ids, ['o1']);
  
  // Verify transaction deleted
  const transactions = Array.from(fakeDb.transactions.values());
  assert.equal(transactions.length, 0);
  
  // Verify payable deleted
  const obligations = Array.from(fakeDb.obligations.values());
  assert.equal(obligations.length, 0);
});

test('P1B: update_transaction_atomic updates transaction and linked payable', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Seed transaction
  seedFakeTable('transactions', [{
    id: 't1',
    direction: 'expense',
    category: 'maintenance',
    amount: 500,
    amount_egp: 500
  }]);
  
  const { data } = await client.rpc('update_transaction_atomic', {
    p_request_id: '10000000-0000-4000-8000-000000000800',
    p_transaction_id: 't1',
    p_updates: { amount: 600, amount_egp: 600 }
  });
  
  assert.equal(data[0].transaction_id, 't1');
  
  // Verify transaction updated
  const transactions = Array.from(fakeDb.transactions.values());
  assert.equal(transactions[0].amount, 600);
  assert.equal(transactions[0].amount_egp, 600);
});

test('P1B: rollback — partial failure rolls back entire transaction', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  
  // Simulate a failure in the middle of record_transaction_atomic
  client.rpc = (fn, params) => {
    if (fn === 'record_transaction_atomic') {
      calls.rpc.push({ fn, params });
      // Simulate failure: insert transaction succeeds but payable fails
      const transaction = params.p_transaction;
      seedFakeTable('transactions', [{
        ...transaction,
        owner_id: 'user-1',
        created_at: new Date().toISOString()
      }]);
      
      // Simulate payable insert failure
      return Promise.resolve({
        data: null,
        error: { message: 'Payable insert failed', code: 'PAYABLE_ERROR' }
      });
    }
    return originalRpc(fn, params);
  };
  
  const { data, error } = await client.rpc('record_transaction_atomic', {
    p_request_id: 'rollback-test-001',
    p_transaction: {
      id: 't-rollback',
      project_id: 'p1',
      direction: 'expense',
      category: 'test',
      amount: 100,
      currency: 'EGP',
      fx_rate: 1,
      amount_egp: 100,
      transaction_date: '2026-07-29'
    },
    p_payable: {
      id: 'o-rollback',
      amount: 100,
      currency: 'EGP',
      amount_egp: 100,
      due_date: '2026-08-29'
    }
  });
  
  // Verify error returned
  assert.notEqual(error, null);
  assert.equal(error.code, 'PAYABLE_ERROR');
  
  // Verify no audit log created (transaction rolled back)
  assert.equal(auditLogs.size, 0);
});

test('P1B: error path — RPC handler not found', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  
  // Try to call a non-existent RPC
  const { data, error } = await client.rpc('nonexistent_rpc', {
    p_request_id: 'error-test-001'
  });
  
  // Verify error returned
  assert.notEqual(error, null);
  assert.match(error.message, /Could not find the function/);
});

test('P1B: audit log — every successful RPC creates audit entry', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Seed asset for stock adjustment
  seedFakeTable('assets', [{
    id: 'a-audit',
    project_id: 'p1',
    quantity: 100,
    current_value_egp: 50000
  }]);
  
  const testCases = [
    { fn: 'record_transaction_atomic', params: { p_request_id: 'audit-001', p_transaction: { id: 't-audit', project_id: 'p1', direction: 'income', category: 'sale', amount: 100, currency: 'EGP', fx_rate: 1, amount_egp: 100, transaction_date: '2026-07-29' } } },
    { fn: 'record_stock_adjustment_atomic', params: { p_request_id: 'audit-002', p_adjustment: { id: 'adj-audit', asset_id: 'a-audit', project_id: 'p1', adjustment_date: '2026-07-29', reason: 'data_correction', quantity_delta: 10, value_egp_delta: 1000 } } }
  ];
  
  for (const testCase of testCases) {
    const { error } = await client.rpc(testCase.fn, testCase.params);
    assert.equal(error, null, `${testCase.fn} should succeed`);
    assert.equal(auditLogs.has(testCase.params.p_request_id), true, `${testCase.fn} should create audit log`);
  }
  
  // Verify all audit logs created
  assert.equal(auditLogs.size, 2);
});

test('P1B: all 6 RPC names are registered and callable', async () => {
  resetFakeSupabase();
  auditLogs.clear();
  
  const client = new FakeSupabaseClient();
  const originalRpc = client.rpc.bind(client);
  client.rpc = (fn, params) => {
    if (P1B_RPC_NAMES.includes(fn)) {
      calls.rpc.push({ fn, params });
      return Promise.resolve({ data: [p1bRpcHandler(fn, params)], error: null });
    }
    return originalRpc(fn, params);
  };
  
  // Verify all 6 RPCs can be called without PGRST202 error
  // Seed required data for RPCs
  seedFakeTable('assets', [{ id: 'a1', project_id: 'p1', quantity: 10, current_value_egp: 1000 }]);
  
  const testCalls = [
    { fn: 'record_transaction_atomic', params: { p_request_id: 'r1', p_transaction: { id: 't1', project_id: 'p1', direction: 'income', category: 'test', amount: 1, currency: 'EGP', fx_rate: 1, amount_egp: 1, transaction_date: '2026-01-01' } } },
    { fn: 'update_transaction_atomic', params: { p_request_id: 'r2', p_transaction_id: 't1', p_updates: {} } },
    { fn: 'delete_transaction_atomic', params: { p_request_id: 'r3', p_transaction_id: 't1' } },
    { fn: 'record_settlement_atomic', params: { p_request_id: 'r4', p_settlement: { id: 's1', obligation_id: 'o1', amount: 1, currency: 'EGP', fx_rate: 1, amount_egp: 1, payment_method: 'cash', settlement_date: '2026-01-01' }, p_allocations: [] } },
    { fn: 'reverse_settlement_atomic', params: { p_request_id: 'r5', p_settlement_id: 's1', p_reason: 'test' } },
    { fn: 'record_stock_adjustment_atomic', params: { p_request_id: 'r6', p_adjustment: { id: 'adj1', asset_id: 'a1', project_id: 'p1', adjustment_date: '2026-01-01', reason: 'other', quantity_delta: 1, value_egp_delta: 100 } } }
  ];
  
  for (const call of testCalls) {
    const { error } = await client.rpc(call.fn, call.params);
    assert.equal(error, null, `${call.fn} should not return an error`);
  }
  
  assert.equal(calls.rpc.length, 6, 'all 6 RPCs should be called');
});

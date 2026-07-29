-- The P1B base rollback removes record_transaction_atomic and the one-argument
-- idempotency helper after this corrective layer is rolled back.
\echo '=== ROLLBACK P1B IDEMPOTENCY PREFLIGHT: COMPLETE ==='

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { runAppStorageMigrations } from './migrations';

const LEGACY_KEY = 'terranex.financialRecords.v1';
const AUDIT_KEY = 'terranex.legacyFinancialRecords.audit.v1';
const MIGRATION_KEY = 'terranex.migrations.v1';
const TRANSACTIONS_KEY = 'terranex.transactions.v2';
const OBLIGATIONS_KEY = 'terranex.obligations.v1';
const MIGRATION_ID = 'legacy-financial-records-to-ledger-v1';

function readArray(key: string) {
  return JSON.parse(localStorage.getItem(key) ?? '[]') as unknown[];
}

describe('legacy financial-record migration', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it('successfully converts mappable legacy records', () => {
    localStorage.setItem(LEGACY_KEY, JSON.stringify([
      { id: 'income-1', date: '2026-01-01', type: 'income', title: 'Sale', amount: 500, currency: 'EGP', project_id: 'project-1' },
      { id: 'receivable-1', date: '2026-01-02', type: 'receivable', title: 'Invoice', amount: 300, currency: 'EGP', partner_id: 'partner-1' },
    ]));

    runAppStorageMigrations();

    expect(readArray(TRANSACTIONS_KEY)).toMatchObject([{ id: 'migrated-income-1', project_id: 'project-1', amount_egp: 500 }]);
    expect(readArray(OBLIGATIONS_KEY)).toMatchObject([{ id: 'migrated-receivable-1', partner_id: 'partner-1', amount_egp: 300 }]);
    expect(JSON.parse(localStorage.getItem(MIGRATION_KEY) ?? '{}')).toEqual({ completed: [MIGRATION_ID] });
    expect(localStorage.getItem(LEGACY_KEY)).toBeNull();
  });

  it('is idempotent when migration runs more than once', () => {
    localStorage.setItem(LEGACY_KEY, JSON.stringify([
      { id: 'income-1', date: '2026-01-01', type: 'income', title: 'Sale', amount: 500, currency: 'EGP', project_id: 'project-1' },
    ]));

    runAppStorageMigrations();
    runAppStorageMigrations();

    expect(readArray(TRANSACTIONS_KEY)).toHaveLength(1);
    expect(readArray(TRANSACTIONS_KEY)[0]).toMatchObject({ id: 'migrated-income-1' });
    expect(JSON.parse(localStorage.getItem(MIGRATION_KEY) ?? '{}')).toEqual({ completed: [MIGRATION_ID] });
  });

  it('preserves unsafe or unmappable records in the audit store', () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const invalidRecord = { id: 'bad-1', date: '2026-01-01', type: 'income', title: 'Bad', amount: Number.NaN, currency: 'EGP', project_id: 'project-1' };
    const unmappableRecord = { id: 'expense-1', date: '2026-01-02', type: 'expense', title: 'No project', amount: 200, currency: 'EGP' };
    localStorage.setItem(LEGACY_KEY, JSON.stringify([invalidRecord, unmappableRecord]));

    runAppStorageMigrations();

    const audit = readArray(AUDIT_KEY);
    expect(audit).toHaveLength(2);
    expect(audit).toEqual(expect.arrayContaining([
      expect.objectContaining({ migration_id: MIGRATION_ID, record: expect.objectContaining({ id: 'bad-1' }) }),
      expect.objectContaining({ migration_id: MIGRATION_ID, record: expect.objectContaining({ id: 'expense-1' }) }),
    ]));
    expect(localStorage.getItem(LEGACY_KEY)).not.toBeNull();
    expect(readArray(TRANSACTIONS_KEY)).toEqual([]);
    expect(readArray(OBLIGATIONS_KEY)).toEqual([]);
  });
});

import { useHydratedSnapshot } from '../../core/hooks';
import { emptyRecords, hydratedSources, readRecords, type Records } from '../storeRegistry';

const stores = [
  'projects', 'assets', 'partners', 'projectPartners', 'documents', 'events',
  'transactions', 'obligations', 'settlements', 'allocations',
  'equityChangeEvents', 'partnerLedgerEntries', 'distributions', 'distributionAllocations',
] as const;

export type FinanceData = Records<(typeof stores)[number]>;

const sources = hydratedSources(stores);
const empty = emptyRecords(stores);
const snapshot = () => readRecords(stores);

export function useFinanceData() {
  const { data, status, error, retry } = useHydratedSnapshot(sources, snapshot, empty);
  return { data, status, error: error?.message ?? null, retry };
}

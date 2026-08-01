import { useHydratedSnapshot } from '../../core/hooks';
import { emptyRecords, hydratedSources, readRecords, type Records } from '../storeRegistry';

const stores = [
  'projects', 'assets', 'events', 'adjustments', 'documents',
  'transactions', 'obligations', 'partners', 'projectPartners',
] as const;

export type OperationsData = Records<(typeof stores)[number]>;

const sources = hydratedSources(stores);
const empty = emptyRecords(stores);
const snapshot = () => readRecords(stores);

export function useOperationsData() {
  const { data, status, error, retry } = useHydratedSnapshot(sources, snapshot, empty);
  return { data, status, error: error?.message ?? null, retry };
}

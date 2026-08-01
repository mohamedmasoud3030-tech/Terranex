import { useHydratedSnapshot } from '../../core/hooks';
import { emptyRecords, hydratedSources, readRecords } from '../storeRegistry';

const stores = [
  'projects', 'assets', 'partners', 'projectPartners',
  'transactions', 'obligations', 'documents', 'events',
] as const;

const sources = hydratedSources(stores);
const empty = emptyRecords(stores);
const snapshot = () => readRecords(stores);

export function usePortfolioData() {
  const { data: rows, status, error, retry } = useHydratedSnapshot(sources, snapshot, empty);
  return { ...rows, status, error, retry };
}

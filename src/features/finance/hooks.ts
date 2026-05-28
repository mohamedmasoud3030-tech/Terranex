import { useSyncExternalStore } from 'react';
import {
  createFinancialRecord,
  deleteFinancialRecord,
  financialRecordsStore,
  resetFinancialRecords,
  updateFinancialRecord,
} from './storage';

export function useFinancialRecords() {
  const records = useSyncExternalStore(
    financialRecordsStore.subscribe,
    financialRecordsStore.getSnapshot,
    financialRecordsStore.getSnapshot,
  );

  return {
    records,
    createRecord: createFinancialRecord,
    updateRecord: updateFinancialRecord,
    deleteRecord: deleteFinancialRecord,
    resetRecords: resetFinancialRecords,
  };
}

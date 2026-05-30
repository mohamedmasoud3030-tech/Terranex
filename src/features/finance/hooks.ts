import { useState, useEffect, useCallback } from 'react';
import {
  createFinancialRecord,
  deleteFinancialRecord,
  financialRecordsStore,
  resetFinancialRecords,
  updateFinancialRecord,
} from './storage';
import type { FinancialRecordInput } from './types';

export function useFinancialRecords() {
  const [records, setRecords] = useState(() => financialRecordsStore.get());

  useEffect(() => financialRecordsStore.subscribe(setRecords), []);

  const createRecord = useCallback((input: FinancialRecordInput) => createFinancialRecord(input), []);
  const updateRecord = useCallback((id: string, input: FinancialRecordInput) => updateFinancialRecord(id, input), []);
  const deleteRecord = useCallback((id: string) => deleteFinancialRecord(id), []);
  const resetRecords = useCallback(() => resetFinancialRecords(), []);

  return {
    records,
    createRecord,
    updateRecord,
    deleteRecord,
    resetRecords,
  };
}

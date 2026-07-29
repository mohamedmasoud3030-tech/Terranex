import { useCallback, useEffect, useState } from 'react';
import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  Transaction,
} from '../../core/types/domain';
import { assetsReady, assetsStore } from '../assets/storage';
import { documentsHydration, documentsReady, documentsStore } from '../documents/storage';
import { operationalEventsReady, operationalEventsStore } from '../events/storage';
import { obligationsHydration, obligationsReady, obligationsStore } from '../obligations/storage';
import { partnersHydration, partnersReady, partnersStore } from '../partners/storage';
import { projectsHydration, projectsReady, projectsStore } from '../projects/storage';
import {
  settlementAllocationsHydration,
  settlementAllocationsReady,
  settlementAllocationsStore,
} from '../settlement-allocations/storage';
import type { SettlementAllocation } from '../settlement-allocations/types';
import { settlementsHydration, settlementsReady, settlementsStore } from '../settlements/storage';
import type { Settlement } from '../settlements/types';
import { transactionsHydration, transactionsReady, transactionsStore } from '../transactions/storage';

export interface FinanceData {
  projects: Project[];
  assets: Asset[];
  partners: Partner[];
  documents: Document[];
  events: OperationalEvent[];
  transactions: Transaction[];
  obligations: Obligation[];
  settlements: Settlement[];
  allocations: SettlementAllocation[];
}

const empty: FinanceData = {
  projects: [], assets: [], partners: [], documents: [], events: [],
  transactions: [], obligations: [], settlements: [], allocations: [],
};

function snapshot(): FinanceData {
  return {
    projects: projectsStore.getAll(),
    assets: assetsStore.getAll(),
    partners: partnersStore.getAll(),
    documents: documentsStore.getAll(),
    events: operationalEventsStore.getAll(),
    transactions: transactionsStore.getAll(),
    obligations: obligationsStore.getAll(),
    settlements: settlementsStore.getAll(),
    allocations: settlementAllocationsStore.getAll(),
  };
}

const ready = Promise.all([
  projectsReady, assetsReady, partnersReady, documentsReady, operationalEventsReady,
  transactionsReady, obligationsReady, settlementsReady, settlementAllocationsReady,
]);

export function useFinanceData() {
  const [data, setData] = useState<FinanceData>(empty);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    setStatus('loading');
    await ready;
    const loadError = [
      projectsHydration, partnersHydration, documentsHydration, transactionsHydration,
      obligationsHydration, settlementsHydration, settlementAllocationsHydration,
    ].map((store) => store.getLoadError()).find(Boolean);
    if (loadError) {
      setError(loadError.message);
      setStatus('error');
      return;
    }
    setData(snapshot());
    setError(null);
    setStatus('ready');
  }, []);
  useEffect(() => {
    void load();
    const unsubscribers = [
      projectsStore.subscribe(() => setData(snapshot())),
      assetsStore.subscribe(() => setData(snapshot())),
      partnersStore.subscribe(() => setData(snapshot())),
      documentsStore.subscribe(() => setData(snapshot())),
      operationalEventsStore.subscribe(() => setData(snapshot())),
      transactionsStore.subscribe(() => setData(snapshot())),
      obligationsStore.subscribe(() => setData(snapshot())),
      settlementsStore.subscribe(() => setData(snapshot())),
      settlementAllocationsStore.subscribe(() => setData(snapshot())),
    ];
    return () => unsubscribers.forEach((unsubscribe) => unsubscribe());
  }, [load]);
  const retry = useCallback(async () => {
    await Promise.all([
      projectsHydration.rehydrate(), partnersHydration.rehydrate(), documentsHydration.rehydrate(),
      transactionsHydration.rehydrate(), obligationsHydration.rehydrate(), settlementsHydration.rehydrate(),
      settlementAllocationsHydration.rehydrate(),
    ]);
    await load();
  }, [load]);
  return { data, status, error, retry };
}

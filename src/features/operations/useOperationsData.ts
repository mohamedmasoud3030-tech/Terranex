import { useCallback, useEffect, useState } from 'react';
import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  ProjectPartner,
  StockAdjustment,
  Transaction,
} from '../../core/types/domain';
import { assetsReady, assetsStore } from '../assets/storage';
import { documentsHydration, documentsReady, documentsStore } from '../documents/storage';
import {
  operationalEventsHydration,
  operationalEventsReady,
  operationalEventsStore,
  stockAdjustmentsHydration,
  stockAdjustmentsReady,
  stockAdjustmentsStore,
} from '../events/storage';
import { obligationsHydration, obligationsReady, obligationsStore } from '../obligations/storage';
import {
  partnersHydration,
  partnersReady,
  partnersStore,
  projectPartnersReady,
  projectPartnersStore,
} from '../partners/storage';
import { projectsHydration, projectsReady, projectsStore } from '../projects/storage';
import { transactionsHydration, transactionsReady, transactionsStore } from '../transactions/storage';

export interface OperationsData {
  projects: Project[];
  assets: Asset[];
  events: OperationalEvent[];
  adjustments: StockAdjustment[];
  documents: Document[];
  transactions: Transaction[];
  obligations: Obligation[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
}

const empty: OperationsData = {
  projects: [],
  assets: [],
  events: [],
  adjustments: [],
  documents: [],
  transactions: [],
  obligations: [],
  partners: [],
  projectPartners: [],
};

function snapshot(): OperationsData {
  return {
    projects: projectsStore.getAll(),
    assets: assetsStore.getAll(),
    events: operationalEventsStore.getAll(),
    adjustments: stockAdjustmentsStore.getAll(),
    documents: documentsStore.getAll(),
    transactions: transactionsStore.getAll(),
    obligations: obligationsStore.getAll(),
    partners: partnersStore.getAll(),
    projectPartners: projectPartnersStore.getAll(),
  };
}

const ready = Promise.all([
  projectsReady,
  assetsReady,
  operationalEventsReady,
  stockAdjustmentsReady,
  documentsReady,
  transactionsReady,
  obligationsReady,
  partnersReady,
  projectPartnersReady,
]);

export function useOperationsData() {
  const [data, setData] = useState<OperationsData>(empty);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await ready;
    const loadError = [
      projectsHydration.getLoadError(),
      operationalEventsHydration.getLoadError(),
      stockAdjustmentsHydration.getLoadError(),
      documentsHydration.getLoadError(),
      transactionsHydration.getLoadError(),
      obligationsHydration.getLoadError(),
      partnersHydration.getLoadError(),
    ].find(Boolean);
    if (loadError) {
      setError(loadError.message);
      setStatus('error');
      return;
    }
    setData(snapshot());
    setStatus('ready');
  }, []);

  useEffect(() => {
    void load();
    const subscriptions = [
      projectsStore.subscribe(() => setData(snapshot())),
      assetsStore.subscribe(() => setData(snapshot())),
      operationalEventsStore.subscribe(() => setData(snapshot())),
      stockAdjustmentsStore.subscribe(() => setData(snapshot())),
      documentsStore.subscribe(() => setData(snapshot())),
      transactionsStore.subscribe(() => setData(snapshot())),
      obligationsStore.subscribe(() => setData(snapshot())),
      partnersStore.subscribe(() => setData(snapshot())),
      projectPartnersStore.subscribe(() => setData(snapshot())),
    ];
    return () => subscriptions.forEach((unsubscribe) => unsubscribe());
  }, [load]);

  const retry = useCallback(async () => {
    await Promise.all([
      projectsHydration.rehydrate(),
      operationalEventsHydration.rehydrate(),
      stockAdjustmentsHydration.rehydrate(),
      documentsHydration.rehydrate(),
      transactionsHydration.rehydrate(),
      obligationsHydration.rehydrate(),
      partnersHydration.rehydrate(),
    ]);
    await load();
  }, [load]);

  return { data, status, error, retry };
}

import { useEffect, useState } from 'react';
import { assetsHydration, assetsReady, assetsStore } from '../assets/storage';
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
  projectPartnersHydration,
  projectPartnersReady,
  projectPartnersStore,
} from '../partners/storage';
import { projectsHydration, projectsReady, projectsStore } from '../projects/storage';
import {
  settlementAllocationsHydration,
  settlementAllocationsReady,
  settlementAllocationsStore,
} from '../settlement-allocations/storage';
import { settlementsHydration, settlementsReady, settlementsStore } from '../settlements/storage';
import { transactionsHydration, transactionsReady, transactionsStore } from '../transactions/storage';
import { inspectStore, type GovernanceRecords } from './dataHealth';

const empty: GovernanceRecords = {
  projects: [], assets: [], partners: [], projectPartners: [], transactions: [],
  obligations: [], settlements: [], allocations: [], events: [], adjustments: [], documents: [],
};

function snapshot(): GovernanceRecords {
  return {
    projects: projectsStore.getAll(),
    assets: assetsStore.getAll(),
    partners: partnersStore.getAll(),
    projectPartners: projectPartnersStore.getAll(),
    transactions: transactionsStore.getAll(),
    obligations: obligationsStore.getAll(),
    settlements: settlementsStore.getAll(),
    allocations: settlementAllocationsStore.getAll(),
    events: operationalEventsStore.getAll(),
    adjustments: stockAdjustmentsStore.getAll(),
    documents: documentsStore.getAll(),
  };
}

const storeDiagnostics = [
  ['projects', projectsHydration],
  ['assets', assetsHydration],
  ['partners', partnersHydration],
  ['project partners', projectPartnersHydration],
  ['transactions', transactionsHydration],
  ['obligations', obligationsHydration],
  ['settlements', settlementsHydration],
  ['settlement allocations', settlementAllocationsHydration],
  ['operational events', operationalEventsHydration],
  ['stock adjustments', stockAdjustmentsHydration],
  ['documents', documentsHydration],
] as const;

const ready = Promise.all([
  projectsReady, assetsReady, partnersReady, projectPartnersReady, transactionsReady,
  obligationsReady, settlementsReady, settlementAllocationsReady, operationalEventsReady,
  stockAdjustmentsReady, documentsReady,
]);

export function useGovernanceData() {
  const [records, setRecords] = useState<GovernanceRecords>(empty);
  const [loading, setLoading] = useState(true);
  const refresh = () => setRecords(snapshot());

  useEffect(() => {
    void ready.then(() => {
      refresh();
      setLoading(false);
    });
    const unsubscribers = [
      projectsStore.subscribe(refresh),
      assetsStore.subscribe(refresh),
      partnersStore.subscribe(refresh),
      projectPartnersStore.subscribe(refresh),
      transactionsStore.subscribe(refresh),
      obligationsStore.subscribe(refresh),
      settlementsStore.subscribe(refresh),
      operationalEventsStore.subscribe(refresh),
      stockAdjustmentsStore.subscribe(refresh),
      documentsStore.subscribe(refresh),
    ];
    return () => unsubscribers.forEach((unsubscribe) => unsubscribe());
  }, []);

  return {
    records,
    loading,
    diagnostics: storeDiagnostics.map(([name, store]) => inspectStore(name, store)),
  };
}

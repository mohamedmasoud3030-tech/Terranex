import { useEffect, useState } from 'react';
import { assetsReady, assetsStore } from '../assets/storage';
import { documentsReady, documentsStore } from '../documents/storage';
import { operationalEventsReady, operationalEventsStore, stockAdjustmentsReady, stockAdjustmentsStore } from '../events/storage';
import { obligationsReady, obligationsStore } from '../obligations/storage';
import { partnersReady, partnersStore, projectPartnersReady, projectPartnersStore } from '../partners/storage';
import { projectsReady, projectsStore } from '../projects/storage';
import { settlementAllocationsReady, settlementAllocationsStore } from '../settlement-allocations/storage';
import { settlementsReady, settlementsStore } from '../settlements/storage';
import { transactionsReady, transactionsStore } from '../transactions/storage';
import type { IntelligenceRecords } from './reportModel';

const empty: IntelligenceRecords = {
  projects: [], assets: [], partners: [], projectPartners: [], transactions: [],
  obligations: [], settlements: [], allocations: [], events: [], adjustments: [],
  documents: [],
};

function snapshot(): IntelligenceRecords {
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

const ready = Promise.all([
  projectsReady, assetsReady, partnersReady, projectPartnersReady, transactionsReady,
  obligationsReady, settlementsReady, settlementAllocationsReady, operationalEventsReady, stockAdjustmentsReady, documentsReady,
]);

export function useIntelligenceData() {
  const [records, setRecords] = useState<IntelligenceRecords>(empty);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    void ready.then(() => {
      setRecords(snapshot());
      setLoading(false);
    });
    const unsubscribers = [
      projectsStore.subscribe(() => setRecords(snapshot())),
      assetsStore.subscribe(() => setRecords(snapshot())),
      partnersStore.subscribe(() => setRecords(snapshot())),
      projectPartnersStore.subscribe(() => setRecords(snapshot())),
      transactionsStore.subscribe(() => setRecords(snapshot())),
      obligationsStore.subscribe(() => setRecords(snapshot())),
      settlementsStore.subscribe(() => setRecords(snapshot())),
      operationalEventsStore.subscribe(() => setRecords(snapshot())),
      stockAdjustmentsStore.subscribe(() => setRecords(snapshot())),
      documentsStore.subscribe(() => setRecords(snapshot())),
    ];
    return () => unsubscribers.forEach((unsubscribe) => unsubscribe());
  }, []);
  return { records, loading };
}

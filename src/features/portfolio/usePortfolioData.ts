import { useCallback, useEffect, useState } from 'react';
import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  ProjectPartner,
  Transaction,
} from '../../core/types/domain';
import { assetsHydration, assetsStore } from '../assets/storage';
import { documentsHydration, documentsStore } from '../documents/storage';
import { operationalEventsHydration, operationalEventsStore } from '../events/storage';
import { obligationsHydration, obligationsStore } from '../obligations/storage';
import {
  partnersHydration,
  partnersStore,
  projectPartnersHydration,
  projectPartnersStore,
} from '../partners/storage';
import { projectsHydration, projectsStore } from '../projects/storage';
import { transactionsHydration, transactionsStore } from '../transactions/storage';

interface PortfolioRows {
  projects: Project[];
  assets: Asset[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  transactions: Transaction[];
  obligations: Obligation[];
  documents: Document[];
  events: OperationalEvent[];
}

const EMPTY: PortfolioRows = {
  projects: [],
  assets: [],
  partners: [],
  projectPartners: [],
  transactions: [],
  obligations: [],
  documents: [],
  events: [],
};

const hydrations = [
  projectsHydration,
  assetsHydration,
  partnersHydration,
  projectPartnersHydration,
  transactionsHydration,
  obligationsHydration,
  documentsHydration,
  operationalEventsHydration,
] as const;

function readRows(): PortfolioRows {
  return {
    projects: projectsStore.getAll(),
    assets: assetsStore.getAll(),
    partners: partnersStore.getAll(),
    projectPartners: projectPartnersStore.getAll(),
    transactions: transactionsStore.getAll(),
    obligations: obligationsStore.getAll(),
    documents: documentsStore.getAll(),
    events: operationalEventsStore.getAll(),
  };
}

function firstLoadError() {
  return hydrations.map((hydration) => hydration.getLoadError()).find(Boolean) ?? null;
}

export function usePortfolioData() {
  const [rows, setRows] = useState<PortfolioRows>(EMPTY);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    const sync = () => {
      if (active) setRows(readRows());
    };
    const unsubscribers = [
      projectsStore.subscribe(sync),
      assetsStore.subscribe(sync),
      partnersStore.subscribe(sync),
      projectPartnersStore.subscribe(sync),
      transactionsStore.subscribe(sync),
      obligationsStore.subscribe(sync),
      documentsStore.subscribe(sync),
      operationalEventsStore.subscribe(sync),
    ];
    void Promise.all(hydrations.map((hydration) => hydration.ready)).then(() => {
      if (!active) return;
      const loadError = firstLoadError();
      setRows(readRows());
      setError(loadError);
      setStatus(loadError ? 'error' : 'ready');
    });
    return () => {
      active = false;
      unsubscribers.forEach((unsubscribe) => unsubscribe());
    };
  }, []);

  const retry = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await Promise.all(hydrations.map((hydration) => hydration.rehydrate()));
    const loadError = firstLoadError();
    setRows(readRows());
    setError(loadError);
    setStatus(loadError ? 'error' : 'ready');
  }, []);

  return { ...rows, status, error, retry };
}

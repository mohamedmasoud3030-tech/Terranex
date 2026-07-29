import { useState, useEffect, useCallback } from 'react';
import {
  partnersHydration,
  partnersStore,
  projectPartnersHydration,
  projectPartnersStore,
  type PartnerInput,
} from './storage';
import type { Partner } from '../../core/types/domain';

export function usePartners() {
  const [partners, setPartners] = useState<Partner[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    const unsubscribe = partnersStore.subscribe((next) => {
      if (active) setPartners(next);
    });
    void partnersHydration.ready.then(() => {
      if (!active) return;
      const loadError = partnersHydration.getLoadError();
      setPartners(partnersStore.getAll());
      setError(loadError);
      setStatus(loadError ? 'error' : 'ready');
    });
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  const createPartner = useCallback(async (input: PartnerInput) => {
    const partner = partnersStore.create(input);
    await partnersHydration.flush();
    return partner;
  }, []);
  const updatePartner = useCallback(async (id: string, input: Partial<PartnerInput>) => {
    partnersStore.update(id, input);
    await partnersHydration.flush();
  }, []);
  const deletePartner = useCallback(async (id: string) => {
    await partnersStore.remove(id);
    await partnersHydration.flush();
  }, []);
  const retry = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await partnersHydration.rehydrate();
    const loadError = partnersHydration.getLoadError();
    setPartners(partnersStore.getAll());
    setError(loadError);
    setStatus(loadError ? 'error' : 'ready');
  }, []);

  return { partners, createPartner, updatePartner, deletePartner, status, error, retry };
}

export function useProjectPartners(projectId: string) {
  const { partners } = usePartners();
  const [pps, setPps] = useState<ReturnType<typeof projectPartnersStore.getByProject>>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    const unsubscribe = projectPartnersStore.subscribe((all) => {
      if (active) setPps(all.filter((pp) => pp.project_id === projectId));
    });
    void projectPartnersHydration.ready.then(() => {
      if (!active) return;
      const loadError = projectPartnersHydration.getLoadError();
      setPps(projectPartnersStore.getByProject(projectId));
      setError(loadError);
      setStatus(loadError ? 'error' : 'ready');
    });
    return () => {
      active = false;
      unsubscribe();
    };
  }, [projectId]);

  const equityPartners = pps.map((pp) => ({
    ...pp,
    partner: partners.find((p) => p.id === pp.partner_id),
  }));

  return { equityPartners, status, error };
}

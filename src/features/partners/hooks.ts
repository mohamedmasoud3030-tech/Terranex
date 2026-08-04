import { useCallback } from 'react';
import { useHydratedCollection } from '../../core/hooks';
import { syncPartnerToOdoo } from '../../core/odoo/hooks';
import {
  partnersHydration,
  partnersStore,
  projectPartnersHydration,
  projectPartnersStore,
  type PartnerInput,
} from './storage';
import type { Partner, ProjectPartner } from '../../core/types/domain';

export function usePartners() {
  const { items: partners, status, error, retry } = useHydratedCollection<Partner>(
    partnersStore,
    partnersHydration,
  );

  const createPartner = useCallback(async (input: PartnerInput) => {
    const partner = partnersStore.create(input);
    await partnersHydration.flush();
    void syncPartnerToOdoo(partner);
    return partner;
  }, []);
  const updatePartner = useCallback(async (id: string, input: Partial<PartnerInput>) => {
    const partner = partnersStore.update(id, input);
    await partnersHydration.flush();
    void syncPartnerToOdoo(partner);
  }, []);
  const deletePartner = useCallback(async (id: string) => {
    await partnersStore.remove(id);
    await partnersHydration.flush();
  }, []);

  return { partners, createPartner, updatePartner, deletePartner, status, error, retry };
}

export function useProjectPartners(projectId: string) {
  const { partners } = usePartners();
  const { items: pps, status, error } = useHydratedCollection<ProjectPartner>(
    projectPartnersStore,
    projectPartnersHydration,
    (all) => all.filter((pp) => pp.project_id === projectId),
    [projectId],
  );

  const equityPartners = pps.map((pp) => ({
    ...pp,
    partner: partners.find((p) => p.id === pp.partner_id),
  }));

  return { equityPartners, status, error };
}

import { useState, useEffect, useCallback } from 'react';
import { partnersStore, projectPartnersStore, type PartnerInput } from './storage';
import type { Partner } from '../../core/types/domain';

export function usePartners() {
  const [partners, setPartners] = useState<Partner[]>(() => partnersStore.getAll());

  useEffect(() => partnersStore.subscribe(setPartners), []);

  const createPartner = useCallback((input: PartnerInput) => partnersStore.create(input), []);
  const updatePartner = useCallback((id: string, input: Partial<PartnerInput>) => partnersStore.update(id, input), []);
  const deletePartner = useCallback((id: string) => partnersStore.remove(id), []);

  return { partners, createPartner, updatePartner, deletePartner };
}

export function useProjectPartners(projectId: string) {
  const { partners } = usePartners();
  const [pps, setPps] = useState(() => projectPartnersStore.getByProject(projectId));

  useEffect(() =>
    projectPartnersStore.subscribe((all) =>
      setPps(all.filter((pp) => pp.project_id === projectId)),
    ), [projectId],
  );

  const equityPartners = pps.map((pp) => ({
    ...pp,
    partner: partners.find((p) => p.id === pp.partner_id),
  }));

  return { equityPartners };
}

import { useCallback, useEffect, useState } from 'react';
import type { Asset, Obligation, OperationalEvent, Partner, Project } from '../../core/types/domain';
import type { FinanceContext } from './contracts';

function read(): FinanceContext {
  if (typeof window === 'undefined') return {};
  const search = new URL(window.location.href).searchParams;
  return {
    projectId: search.get('project') || undefined,
    assetId: search.get('asset') || undefined,
    partnerId: search.get('partner') || undefined,
    eventId: search.get('event') || undefined,
    obligationId: search.get('obligation') || undefined,
  };
}

function validate(
  requested: FinanceContext,
  projects: Project[],
  assets: Asset[],
  partners: Partner[],
  events: OperationalEvent[],
  obligations: Obligation[],
): FinanceContext {
  const project = projects.find((item) => item.id === requested.projectId);
  const asset = assets.find((item) => item.id === requested.assetId);
  const partner = partners.find((item) => item.id === requested.partnerId);
  const event = events.find((item) => item.id === requested.eventId);
  const obligation = obligations.find((item) => item.id === requested.obligationId);
  const projectId = project?.id ?? asset?.project_id ?? event?.project_id ?? obligation?.project_id;
  return {
    projectId,
    assetId: asset && (!projectId || asset.project_id === projectId) ? asset.id : undefined,
    partnerId: partner?.id ?? (obligation?.partner_id && partners.some((item) => item.id === obligation.partner_id) ? obligation.partner_id : undefined),
    eventId: event && (!projectId || event.project_id === projectId) ? event.id : undefined,
    obligationId: obligation?.id,
  };
}

export function useFinanceContext(
  projects: Project[],
  assets: Asset[],
  partners: Partner[],
  events: OperationalEvent[],
  obligations: Obligation[],
) {
  const [context, setContext] = useState<FinanceContext>(read);
  const commit = useCallback((requested: FinanceContext) => {
    const next = validate(requested, projects, assets, partners, events, obligations);
    const url = new URL(window.location.href);
    for (const key of ['project', 'asset', 'partner', 'event', 'obligation']) url.searchParams.delete(key);
    const mapping = { project: next.projectId, asset: next.assetId, partner: next.partnerId, event: next.eventId, obligation: next.obligationId };
    for (const [key, value] of Object.entries(mapping)) if (value) url.searchParams.set(key, value);
    window.history.replaceState(window.history.state, '', url);
    setContext(next);
  }, [assets, events, obligations, partners, projects]);
  useEffect(() => {
    const sync = () => setContext(validate(read(), projects, assets, partners, events, obligations));
    window.addEventListener('popstate', sync);
    return () => window.removeEventListener('popstate', sync);
  }, [assets, events, obligations, partners, projects]);
  return [context, commit] as const;
}

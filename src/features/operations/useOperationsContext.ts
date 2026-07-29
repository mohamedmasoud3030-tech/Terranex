import { useCallback, useEffect, useState } from 'react';
import type { Asset, Project, SectorId } from '../../core/types/domain';
import { resolveOperationsContext, type OperationsContext } from './model';

const sectors: Array<SectorId | 'all'> = ['all', 'real-estate', 'agriculture', 'livestock'];

function readContext(): OperationsContext {
  if (typeof window === 'undefined') return { sector: 'all' };
  const search = new URL(window.location.href).searchParams;
  const requestedSector = search.get('sector');
  return {
    sector: sectors.includes(requestedSector as SectorId | 'all')
      ? requestedSector as SectorId | 'all'
      : 'all',
    projectId: search.get('project') || undefined,
    assetId: search.get('asset') || undefined,
  };
}

function same(first: OperationsContext, second: OperationsContext) {
  return first.sector === second.sector
    && first.projectId === second.projectId
    && first.assetId === second.assetId;
}

export function useOperationsContext(projects: Project[], assets: Asset[]) {
  const [context, setContextState] = useState<OperationsContext>(readContext);

  const commit = useCallback((requested: OperationsContext) => {
    const next = resolveOperationsContext(requested, projects, assets);
    const url = new URL(window.location.href);
    if (next.sector === 'all') url.searchParams.delete('sector');
    else url.searchParams.set('sector', next.sector);
    if (next.projectId) url.searchParams.set('project', next.projectId);
    else url.searchParams.delete('project');
    if (next.assetId) url.searchParams.set('asset', next.assetId);
    else url.searchParams.delete('asset');
    window.history.replaceState(window.history.state, '', url);
    setContextState(next);
  }, [assets, projects]);

  useEffect(() => {
    if (!projects.length && !assets.length) return;
    const validated = resolveOperationsContext(context, projects, assets);
    if (!same(validated, context)) commit(validated);
  }, [assets, commit, context, projects]);

  useEffect(() => {
    const sync = () => setContextState(resolveOperationsContext(readContext(), projects, assets));
    window.addEventListener('popstate', sync);
    return () => window.removeEventListener('popstate', sync);
  }, [assets, projects]);

  return [context, commit] as const;
}

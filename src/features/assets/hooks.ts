import { useState, useEffect, useCallback } from 'react';
import { assetsHydration, assetsStore, type AssetInput } from './storage';
import type { Asset } from '../../core/types/domain';

export function useAssets(projectId?: string) {
  const [assets, setAssets] = useState<Asset[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    const select = (all: Asset[]) =>
      projectId ? all.filter((asset) => asset.project_id === projectId) : all;
    const unsubscribe = assetsStore.subscribe((all) => {
      if (active) setAssets(select(all));
    });
    void assetsHydration.ready.then(() => {
      if (!active) return;
      const loadError = assetsHydration.getLoadError();
      setAssets(select(assetsStore.getAll()));
      setError(loadError);
      setStatus(loadError ? 'error' : 'ready');
    });
    return () => {
      active = false;
      unsubscribe();
    };
  }, [projectId]);

  const createAsset = useCallback(async (input: AssetInput) => {
    const asset = assetsStore.create(input);
    await assetsHydration.flush();
    return asset;
  }, []);
  const updateAsset = useCallback(async (id: string, input: Partial<AssetInput>) => {
    assetsStore.update(id, input);
    await assetsHydration.flush();
  }, []);
  const deleteAsset = useCallback(async (id: string) => {
    await assetsStore.remove(id);
    await assetsHydration.flush();
  }, []);
  const retry = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await assetsHydration.rehydrate();
    const loadError = assetsHydration.getLoadError();
    const all = assetsStore.getAll();
    setAssets(projectId ? all.filter((asset) => asset.project_id === projectId) : all);
    setError(loadError);
    setStatus(loadError ? 'error' : 'ready');
  }, [projectId]);

  return { assets, createAsset, updateAsset, deleteAsset, status, error, retry };
}

import { useCallback } from 'react';
import { useHydratedCollection } from '../../core/hooks';
import { assetsHydration, assetsStore, type AssetInput } from './storage';
import type { Asset } from '../../core/types/domain';

export function useAssets(projectId?: string) {
  const { items: assets, status, error, retry } = useHydratedCollection<Asset>(
    assetsStore,
    assetsHydration,
    (all) => (projectId ? all.filter((asset) => asset.project_id === projectId) : all),
    [projectId],
  );

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

  return { assets, createAsset, updateAsset, deleteAsset, status, error, retry };
}

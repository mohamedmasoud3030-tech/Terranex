import { useState, useEffect, useCallback } from 'react';
import { assetsStore, type AssetInput } from './storage';
import type { Asset } from '../../core/types/domain';

export function useAssets(projectId?: string) {
  const [assets, setAssets] = useState<Asset[]>(() =>
    projectId ? assetsStore.getByProject(projectId) : assetsStore.getAll(),
  );

  useEffect(() =>
    assetsStore.subscribe((all) =>
      setAssets(projectId ? all.filter((a) => a.project_id === projectId) : all),
    ), [projectId],
  );

  const createAsset = useCallback((input: AssetInput) => assetsStore.create(input), []);
  const updateAsset = useCallback((id: string, input: Partial<AssetInput>) => assetsStore.update(id, input), []);
  const deleteAsset = useCallback((id: string) => assetsStore.remove(id), []);

  return { assets, createAsset, updateAsset, deleteAsset };
}

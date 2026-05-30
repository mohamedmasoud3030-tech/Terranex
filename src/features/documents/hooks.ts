import { useState, useEffect, useCallback } from 'react';
import { documentsStore, type DocumentInput } from './storage';
import type { Document } from '../../core/types/domain';

export function useDocuments(projectId?: string) {
  const [documents, setDocuments] = useState<Document[]>(() =>
    projectId ? documentsStore.getByProject(projectId) : documentsStore.getAll(),
  );

  useEffect(() =>
    documentsStore.subscribe((all) =>
      setDocuments(projectId ? all.filter((d) => d.project_id === projectId) : all),
    ), [projectId],
  );

  const createDocument = useCallback((input: DocumentInput) => documentsStore.create(input), []);
  const updateDocument = useCallback((id: string, input: Partial<DocumentInput>) => documentsStore.update(id, input), []);
  const deleteDocument = useCallback((id: string) => documentsStore.remove(id), []);

  return { documents, createDocument, updateDocument, deleteDocument };
}

import type { OperationalEventType, SectorId } from '../../core/types/domain';

export type OperationsHandoff =
  | {
      destination: 'finance';
      intent: 'create-or-link-transaction';
      projectId: string;
      assetId: string;
      eventId: string;
      eventType: OperationalEventType;
      amountEgp?: number;
    }
  | {
      destination: 'governance';
      intent: 'attach-document';
      projectId: string;
      assetId: string;
      eventId?: string;
    }
  | {
      destination: 'operations';
      intent: 'open-context';
      sector: SectorId;
      projectId?: string;
      assetId?: string;
    };

export function operationsContextSearch(handoff: Extract<OperationsHandoff, { destination: 'operations' }>) {
  const search = new URLSearchParams({ sector: handoff.sector });
  if (handoff.projectId) search.set('project', handoff.projectId);
  if (handoff.assetId) search.set('asset', handoff.assetId);
  return search.toString();
}

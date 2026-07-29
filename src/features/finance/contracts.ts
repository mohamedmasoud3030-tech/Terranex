export interface FinanceContext {
  projectId?: string;
  assetId?: string;
  partnerId?: string;
  eventId?: string;
  obligationId?: string;
}

export type FinanceHandoff =
  | ({ destination: 'finance'; intent: 'open-context' } & FinanceContext)
  | { destination: 'portfolio' | 'operations' | 'governance'; intent: 'inspect-related'; entityId: string; entityType: 'project' | 'asset' | 'partner' | 'event' | 'document' };

export function financeContextSearch(context: FinanceContext) {
  const search = new URLSearchParams();
  if (context.projectId) search.set('project', context.projectId);
  if (context.assetId) search.set('asset', context.assetId);
  if (context.partnerId) search.set('partner', context.partnerId);
  if (context.eventId) search.set('event', context.eventId);
  if (context.obligationId) search.set('obligation', context.obligationId);
  return search.toString();
}

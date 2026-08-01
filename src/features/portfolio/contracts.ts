import type { SectorId } from '../../core/types/domain';

export type PortfolioTargetHub = 'operations' | 'finance' | 'governance' | 'intelligence';

export interface PortfolioHandoff {
  target: PortfolioTargetHub;
  workspace?: string;
  context: {
    projectId?: string;
    assetId?: string;
    partnerId?: string;
    sector?: SectorId;
  };
  intent:
    | 'create-event'
    | 'create-transaction'
    | 'create-distribution'
    | 'attach-document'
    | 'open-statement'
    | 'open-obligations'
    | 'inspect-operations';
}

export interface PortfolioActionHandlers {
  onHandoff?: (handoff: PortfolioHandoff) => void;
}

export function projectHandoff(
  projectId: string,
  sector: SectorId,
  intent: PortfolioHandoff['intent'],
): PortfolioHandoff {
  if (intent === 'attach-document') {
    return { target: 'governance', workspace: 'documents', context: { projectId, sector }, intent };
  }
  if (intent === 'create-transaction') {
    return { target: 'finance', workspace: 'transactions', context: { projectId, sector }, intent };
  }
  if (intent === 'create-distribution') {
    return { target: 'finance', workspace: 'distributions', context: { projectId, sector }, intent };
  }
  return { target: 'operations', workspace: 'events', context: { projectId, sector }, intent };
}

export function assetHandoff(
  projectId: string,
  assetId: string,
  sector: SectorId,
  intent: PortfolioHandoff['intent'],
): PortfolioHandoff {
  const base = { projectId, assetId, sector };
  if (intent === 'attach-document') {
    return { target: 'governance', workspace: 'documents', context: base, intent };
  }
  if (intent === 'create-transaction') {
    return { target: 'finance', workspace: 'transactions', context: base, intent };
  }
  return { target: 'operations', workspace: 'events', context: base, intent };
}

export function partnerHandoff(
  partnerId: string,
  intent: PortfolioHandoff['intent'],
): PortfolioHandoff {
  if (intent === 'attach-document') {
    return { target: 'governance', workspace: 'documents', context: { partnerId }, intent };
  }
  if (intent === 'open-statement') {
    return { target: 'intelligence', workspace: 'partner-statement', context: { partnerId }, intent };
  }
  return { target: 'finance', workspace: 'obligations', context: { partnerId }, intent };
}

import type { GovernanceHandoff } from '../governance/contracts';
import type { ReportContext } from '../intelligence/reportModel';
import type { FinanceHandoff } from '../finance/contracts';
import type { OperationsHandoff } from '../operations/contracts';
import type { PortfolioHandoff } from '../portfolio/contracts';

export type CanonicalHubPath = '/portfolio' | '/operations' | '/finance' | '/intelligence' | '/governance';
export interface HandoffTarget {
  to: CanonicalHubPath;
  search: Record<string, string | undefined>;
}

function portfolioContext(context: PortfolioHandoff['context']) {
  return {
    project: context.projectId,
    asset: context.assetId,
    partner: context.partnerId,
    sector: context.sector,
  };
}

export function portfolioHandoffTarget(handoff: PortfolioHandoff): HandoffTarget {
  const workspace = handoff.workspace === 'partner-statement' ? 'statement' : handoff.workspace;
  return {
    to: `/${handoff.target}` as CanonicalHubPath,
    search: { workspace, ...portfolioContext(handoff.context), intent: handoff.intent },
  };
}

export function operationsHandoffTarget(handoff: OperationsHandoff): HandoffTarget {
  if (handoff.destination === 'finance') {
    return {
      to: '/finance',
      search: {
        workspace: 'transactions',
        project: handoff.projectId,
        asset: handoff.assetId,
        event: handoff.eventId,
        intent: handoff.intent,
      },
    };
  }
  if (handoff.destination === 'governance') {
    return {
      to: '/governance',
      search: {
        workspace: 'documents',
        project: handoff.projectId,
        asset: handoff.assetId,
        event: handoff.eventId,
        intent: handoff.intent,
      },
    };
  }
  return {
    to: '/operations',
    search: {
      workspace: 'events',
      sector: handoff.sector,
      project: handoff.projectId,
      asset: handoff.assetId,
      intent: handoff.intent,
    },
  };
}

export function financeHandoffTarget(handoff: FinanceHandoff): HandoffTarget {
  if (handoff.destination === 'finance') {
    return {
      to: '/finance',
      search: {
        workspace: handoff.obligationId ? 'obligations' : 'overview',
        project: handoff.projectId,
        asset: handoff.assetId,
        partner: handoff.partnerId,
        event: handoff.eventId,
        obligation: handoff.obligationId,
        intent: handoff.intent,
      },
    };
  }
  if (handoff.destination === 'portfolio') {
    const workspace = handoff.entityType === 'partner' ? 'partners'
      : handoff.entityType === 'asset' ? 'assets'
        : 'projects';
    return { to: '/portfolio', search: { workspace, inspect: handoff.entityId, intent: handoff.intent } };
  }
  if (handoff.destination === 'operations') {
    return { to: '/operations', search: { workspace: 'events', inspect: handoff.entityId, intent: handoff.intent } };
  }
  return { to: '/governance', search: { workspace: 'documents', inspect: handoff.entityId, intent: handoff.intent } };
}

export function governanceHandoffTarget(handoff: GovernanceHandoff): HandoffTarget {
  if (handoff.destination === 'finance') {
    return { to: '/finance', search: { workspace: 'overview', inspect: handoff.entityId, relation: handoff.relationship } };
  }
  if (handoff.destination === 'operations') {
    return { to: '/operations', search: { workspace: 'events', inspect: handoff.entityId, relation: handoff.relationship } };
  }
  return { to: '/portfolio', search: { workspace: 'projects', inspect: handoff.entityId, relation: handoff.relationship } };
}

export function intelligenceFinanceTarget(context: ReportContext): HandoffTarget {
  return {
    to: '/finance',
    search: {
      workspace: 'obligations',
      project: context.projectId,
      asset: context.assetId,
      partner: context.partnerId,
      from: context.dateFrom,
      to: context.dateTo,
    },
  };
}

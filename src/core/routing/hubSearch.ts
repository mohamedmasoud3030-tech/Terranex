import type { SectorId } from '../types/domain';

const sectors: SectorId[] = ['real-estate', 'agriculture', 'livestock'];
const portfolioWorkspaces = ['overview', 'projects', 'assets', 'partners'];
const operationsWorkspaces = ['overview', 'events', 'balances', 'sector'];
const financeWorkspaces = ['overview', 'transactions', 'obligations', 'settlements'];
const intelligenceWorkspaces = ['executive', 'profitability', 'sectors', 'aging', 'statement', 'assets'];
const governanceWorkspaces = ['documents', 'settings', 'exchange-rates', 'data-health'];

function text(value: unknown) {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function oneOf(value: unknown, allowed: readonly string[]) {
  const candidate = text(value);
  return candidate && allowed.includes(candidate) ? candidate : undefined;
}

function common(search: Record<string, unknown>) {
  const result: Record<string, string> = {};
  for (const key of ['project', 'asset', 'partner', 'event', 'obligation', 'inspect', 'intent', 'relation', 'from', 'to', 'type', 'expiry', 'status', 'category']) {
    const value = text(search[key]);
    if (value) result[key] = value;
  }
  return result;
}

export function validatePortfolioSearch(search: Record<string, unknown>) {
  const workspace = oneOf(search.workspace, portfolioWorkspaces);
  return { ...(workspace ? { workspace } : {}), ...common(search) };
}

export function validateOperationsSearch(search: Record<string, unknown>) {
  const workspace = oneOf(search.workspace, operationsWorkspaces);
  const sector = oneOf(search.sector, sectors) as SectorId | undefined;
  return {
    ...(workspace ? { workspace } : {}),
    ...(sector ? { sector } : {}),
    ...common(search),
  };
}

export function validateFinanceSearch(search: Record<string, unknown>) {
  const workspace = oneOf(search.workspace, financeWorkspaces);
  return { ...(workspace ? { workspace } : {}), ...common(search) };
}

export function validateIntelligenceSearch(search: Record<string, unknown>) {
  const workspace = oneOf(search.workspace, intelligenceWorkspaces);
  const sector = oneOf(search.sector, sectors);
  return { ...(workspace ? { workspace } : {}), ...(sector ? { sector } : {}), ...common(search) };
}

export function validateGovernanceSearch(search: Record<string, unknown>) {
  const workspace = oneOf(search.workspace, governanceWorkspaces);
  return { ...(workspace ? { workspace } : {}), ...common(search) };
}

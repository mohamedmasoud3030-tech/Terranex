import type { DateRange, SectorId } from '../types';

/**
 * Centralized query key factory.
 * Hierarchy: entity → list/detail → filters
 * This prevents cache collisions and makes invalidation surgical.
 */
export const queryKeys = {
  // ─── Sectors ──────────────────────────────────────────────────────────────
  sectors: {
    all: () => ['sectors'] as const,
    list: () => ['sectors', 'list'] as const,
  },

  // ─── Projects ─────────────────────────────────────────────────────────────
  projects: {
    all: () => ['projects'] as const,
    list: (sectorId?: SectorId) => ['projects', 'list', { sectorId }] as const,
    detail: (id: string) => ['projects', 'detail', id] as const,
    profitability: (id: string, range?: DateRange) =>
      ['projects', 'profitability', id, range] as const,
  },

  // ─── Assets ───────────────────────────────────────────────────────────────
  assets: {
    all: () => ['assets'] as const,
    list: (projectId?: string) => ['assets', 'list', { projectId }] as const,
    detail: (id: string) => ['assets', 'detail', id] as const,
    balances: (projectId: string) => ['assets', 'balances', projectId] as const,
  },

  // ─── Transactions ─────────────────────────────────────────────────────────
  transactions: {
    all: () => ['transactions'] as const,
    list: (filters?: { projectId?: string; range?: DateRange }) =>
      ['transactions', 'list', filters] as const,
    detail: (id: string) => ['transactions', 'detail', id] as const,
  },

  // ─── Obligations ──────────────────────────────────────────────────────────
  obligations: {
    all: () => ['obligations'] as const,
    list: (filters?: { projectId?: string; status?: string }) =>
      ['obligations', 'list', filters] as const,
    detail: (id: string) => ['obligations', 'detail', id] as const,
  },

  // ─── Partners ─────────────────────────────────────────────────────────────
  partners: {
    all: () => ['partners'] as const,
    list: () => ['partners', 'list'] as const,
    detail: (id: string) => ['partners', 'detail', id] as const,
  },

  // ─── Documents ────────────────────────────────────────────────────────────
  documents: {
    all: () => ['documents'] as const,
    list: (filters?: { projectId?: string; assetId?: string }) =>
      ['documents', 'list', filters] as const,
    detail: (id: string) => ['documents', 'detail', id] as const,
  },

  // ─── Operational Events ───────────────────────────────────────────────────
  events: {
    all: () => ['events'] as const,
    list: (assetId: string) => ['events', 'list', assetId] as const,
  },

  // ─── Exchange Rates ───────────────────────────────────────────────────────
  exchangeRates: {
    all: () => ['exchange-rates'] as const,
    latest: () => ['exchange-rates', 'latest'] as const,
    onDate: (date: string) => ['exchange-rates', 'on-date', date] as const,
  },

  // ─── Dashboard ────────────────────────────────────────────────────────────
  dashboard: {
    kpis: (range?: DateRange) => ['dashboard', 'kpis', range] as const,
    summary: () => ['dashboard', 'summary'] as const,
  },
} as const;

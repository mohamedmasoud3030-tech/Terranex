import type { PortfolioStatus } from './schema';

/** Arabic operator labels for the narrow R1 portfolio lifecycle. */
export const PORTFOLIO_STATUS_LABEL: Record<PortfolioStatus, string> = {
  DRAFT: 'مسودة',
  ACTIVE: 'نشطة',
  ARCHIVED: 'مؤرشفة',
};

export const PORTFOLIO_STATUS_BADGE_CLASS: Record<PortfolioStatus, string> = {
  DRAFT: 'status status-draft',
  ACTIVE: 'status status-active',
  ARCHIVED: 'status status-archived',
};

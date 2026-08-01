/**
 * Ownership domain — effective-dated project ownership, partner ledger, distributions.
 *
 * ADR-011: Effective-dated project ownership
 * ADR-012: Append-only partner ledger
 * ADR-013: Immutable distribution snapshots
 */

export {
  ownershipReady,
  equityChangeEventsStorage,
  partnerLedgerEntriesStorage,
  distributionsStorage,
  distributionAllocationsStorage,
  type EquityChangeEventInput,
  type PartnerLedgerEntryInput,
  type DistributionInput,
  type DistributionAllocationInput,
} from './storage';
export * from './model';
export * from './service';

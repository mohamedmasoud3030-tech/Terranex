import { requireDateOnly, toDateOnly } from '../../core/lib/dateOnly';
import type {
  Currency,
  Distribution,
  DistributionAllocation,
  EquityChangeEvent,
  EquityChangeType,
  Partner,
  PartnerLedgerEntry,
  PartnerLedgerEntryType,
  ProjectPartner,
} from '../../core/types/domain';

const MONEY_SCALE = 100;
const EPSILON = 0.000001;

export interface OwnershipSnapshotRow {
  project_partner_id: string;
  partner_id: string;
  equity_pct: number;
  effective_from: string;
  effective_to?: string;
}

export interface OwnershipSummary {
  rows: OwnershipSnapshotRow[];
  assigned_pct: number;
  remaining_pct: number;
  below_full: boolean;
  exceeds_full: boolean;
}

export interface OwnershipTimelineItem {
  id: string;
  project_id: string;
  partner_id: string;
  effective_date: string;
  previous_pct: number;
  new_pct: number;
  change_type: EquityChangeType;
  reason?: string;
  notes?: string;
  actor?: string;
  audit_reference?: string;
  source: 'equity_change_event' | 'project_partner_record';
}

export interface DistributionPreviewAllocation {
  partner_id: string;
  equity_pct_snapshot: number;
  raw_amount: number;
  rounded_amount: number;
  rounding_adjustment: number;
  final_amount: number;
  final_amount_egp: number;
  currency: Currency;
}

export interface DistributionPreview {
  allocations: DistributionPreviewAllocation[];
  total_amount: number;
  total_amount_egp: number;
  currency: Currency;
  fx_rate: number;
  allocation_total: number;
  rounding_difference: number;
  ownership_total_pct: number;
}

export interface LedgerEntryWithEffect extends PartnerLedgerEntry {
  active_effect_egp: number;
  active_effect_native: number;
  is_reversed_original: boolean;
}

export interface PartnerLedgerSummary {
  capital_contributed_egp: number;
  withdrawals_egp: number;
  profit_entitlements_egp: number;
  payments_made_egp: number;
  reversals_egp: number;
  current_balance_egp: number;
  distributed_unpaid_egp: number;
  paid_distributions_egp: number;
  historical_total_egp: number;
}

export interface PartnerDistributionPosition {
  distributed_egp: number;
  paid_egp: number;
  unpaid_egp: number;
}

export function normalizeDateOnly(value: string, label = 'التاريخ'): string {
  return requireDateOnly(value, label);
}

export function isOwnershipActiveOn(record: Pick<ProjectPartner, 'effective_from' | 'effective_to'>, asOfDate: string): boolean {
  const asOf = normalizeDateOnly(asOfDate, 'تاريخ الملكية');
  const from = normalizeDateOnly(record.effective_from, 'تاريخ بداية الملكية');
  const to = toDateOnly(record.effective_to);
  return from <= asOf && (!to || to >= asOf);
}

export function getOwnershipRowsAsOf(projectPartners: ProjectPartner[], projectId: string, asOfDate: string): OwnershipSnapshotRow[] {
  const asOf = normalizeDateOnly(asOfDate, 'تاريخ الملكية');
  return projectPartners
    .filter((record) => record.project_id === projectId && isOwnershipActiveOn(record, asOf))
    .map((record) => ({
      project_partner_id: record.id,
      partner_id: record.partner_id,
      equity_pct: Number(record.equity_pct),
      effective_from: normalizeDateOnly(record.effective_from, 'تاريخ بداية الملكية'),
      effective_to: toDateOnly(record.effective_to),
    }))
    .sort((a, b) => b.equity_pct - a.equity_pct || a.effective_from.localeCompare(b.effective_from));
}

export function summarizeOwnership(rows: OwnershipSnapshotRow[]): OwnershipSummary {
  const assigned = roundPct(rows.reduce((sum, row) => sum + row.equity_pct, 0));
  const remaining = roundPct(Math.max(0, 100 - assigned));
  return {
    rows,
    assigned_pct: assigned,
    remaining_pct: remaining,
    below_full: assigned < 100 - EPSILON,
    exceeds_full: assigned > 100 + EPSILON,
  };
}

export function getPartnerOwnershipPct(projectPartners: ProjectPartner[], projectId: string, partnerId: string, asOfDate: string): number {
  return getOwnershipRowsAsOf(projectPartners, projectId, asOfDate)
    .filter((row) => row.partner_id === partnerId)
    .reduce((sum, row) => sum + row.equity_pct, 0);
}

export function buildOwnershipTimeline(
  projectId: string,
  projectPartners: ProjectPartner[],
  equityChangeEvents: EquityChangeEvent[],
): OwnershipTimelineItem[] {
  const eventItems: OwnershipTimelineItem[] = equityChangeEvents
    .filter((event) => event.project_id === projectId)
    .map((event) => ({
      id: event.id,
      project_id: event.project_id,
      partner_id: event.partner_id,
      effective_date: normalizeDateOnly(event.effective_date, 'تاريخ تغيير الملكية'),
      previous_pct: Number(event.previous_pct),
      new_pct: Number(event.new_pct),
      change_type: event.change_type,
      reason: event.reason,
      notes: event.notes,
      actor: event.created_by,
      audit_reference: event.id,
      source: 'equity_change_event',
    }));

  const covered = new Set(eventItems.map((item) => `${item.partner_id}:${item.effective_date}:${item.new_pct}`));
  const fallbackItems: OwnershipTimelineItem[] = projectPartners
    .filter((record) => record.project_id === projectId)
    .filter((record) => !covered.has(`${record.partner_id}:${normalizeDateOnly(record.effective_from, 'تاريخ بداية الملكية')}:${Number(record.equity_pct)}`))
    .map((record) => ({
      id: record.id,
      project_id: record.project_id,
      partner_id: record.partner_id,
      effective_date: normalizeDateOnly(record.effective_from, 'تاريخ بداية الملكية'),
      previous_pct: 0,
      new_pct: Number(record.equity_pct),
      change_type: 'entry',
      notes: record.notes,
      audit_reference: record.id,
      source: 'project_partner_record',
    }));

  return [...eventItems, ...fallbackItems]
    .sort((a, b) => b.effective_date.localeCompare(a.effective_date) || b.id.localeCompare(a.id));
}

export function validateOwnershipChangeTotal(
  projectPartners: ProjectPartner[],
  projectId: string,
  partnerId: string,
  newPct: number,
  asOfDate: string,
): OwnershipSummary {
  const rows = getOwnershipRowsAsOf(projectPartners, projectId, asOfDate)
    .filter((row) => row.partner_id !== partnerId);
  const next = newPct > 0
    ? [...rows, { project_partner_id: 'preview', partner_id: partnerId, equity_pct: newPct, effective_from: asOfDate }]
    : rows;
  return summarizeOwnership(next);
}

export function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * MONEY_SCALE) / MONEY_SCALE;
}

export function roundPct(value: number): number {
  return Math.round((value + Number.EPSILON) * 10_000) / 10_000;
}

export function previewDistributionAllocations(
  totalAmount: number,
  currency: Currency,
  fxRate: number,
  ownershipRows: OwnershipSnapshotRow[],
): DistributionPreview {
  if (!Number.isFinite(totalAmount) || totalAmount <= 0) {
    throw new Error('مبلغ التوزيع يجب أن يكون أكبر من صفر.');
  }
  if (!Number.isFinite(fxRate) || fxRate <= 0) {
    throw new Error('سعر الصرف يجب أن يكون أكبر من صفر.');
  }
  if (ownershipRows.length === 0) {
    throw new Error('لا توجد ملكية فعالة في تاريخ التوزيع المختار.');
  }

  const ownershipTotal = summarizeOwnership(ownershipRows).assigned_pct;
  if (ownershipTotal <= 0) throw new Error('لا توجد نسب ملكية موجبة للتوزيع.');
  if (ownershipTotal > 100 + EPSILON) throw new Error('إجمالي الملكية يتجاوز 100% ولا يمكن إنشاء توزيع.');

  const initial = ownershipRows.map((row) => {
    const raw = totalAmount * row.equity_pct / 100;
    const rounded = roundMoney(raw);
    return {
      partner_id: row.partner_id,
      equity_pct_snapshot: row.equity_pct,
      raw_amount: raw,
      rounded_amount: rounded,
      rounding_adjustment: 0,
      final_amount: rounded,
      final_amount_egp: roundMoney(rounded * fxRate),
      currency,
    } satisfies DistributionPreviewAllocation;
  });

  const roundedTotal = roundMoney(initial.reduce((sum, allocation) => sum + allocation.rounded_amount, 0));
  const difference = roundMoney(totalAmount - roundedTotal);
  if (initial.length > 0 && Math.abs(difference) > 0) {
    let largestIndex = 0;
    for (let index = 1; index < initial.length; index += 1) {
      const allocation = initial[index];
      const largest = initial[largestIndex];
      if (
        allocation.equity_pct_snapshot > largest.equity_pct_snapshot
        || (allocation.equity_pct_snapshot === largest.equity_pct_snapshot && allocation.partner_id < largest.partner_id)
      ) {
        largestIndex = index;
      }
    }
    const target = initial[largestIndex];
    initial[largestIndex] = {
      ...target,
      rounding_adjustment: difference,
      final_amount: roundMoney(target.rounded_amount + difference),
      final_amount_egp: roundMoney((target.rounded_amount + difference) * fxRate),
    };
  }

  const allocationTotal = roundMoney(initial.reduce((sum, allocation) => sum + allocation.final_amount, 0));
  if (allocationTotal !== roundMoney(totalAmount)) {
    throw new Error('تعذر ضبط التقريب بحيث يساوي مجموع التخصيصات إجمالي التوزيع.');
  }

  return {
    allocations: initial,
    total_amount: roundMoney(totalAmount),
    total_amount_egp: roundMoney(totalAmount * fxRate),
    currency,
    fx_rate: fxRate,
    allocation_total: allocationTotal,
    rounding_difference: difference,
    ownership_total_pct: ownershipTotal,
  };
}

export function getDistributionAllocations(
  distribution: Distribution,
  allocations: DistributionAllocation[],
): DistributionAllocation[] {
  return allocations
    .filter((allocation) => allocation.distribution_id === distribution.id)
    .sort((a, b) => b.allocated_amount_egp - a.allocated_amount_egp || a.partner_id.localeCompare(b.partner_id));
}

export function getDistributionPaidAmount(distributionId: string, ledgerEntries: PartnerLedgerEntry[]): number {
  return sumLedgerEffects(
    ledgerEntries.filter((entry) => entry.related_distribution_id === distributionId && entry.entry_type === 'distribution_payment'),
  );
}

export function getPartnerDistributionPosition(
  partnerId: string,
  allocations: DistributionAllocation[],
  ledgerEntries: PartnerLedgerEntry[],
): PartnerDistributionPosition {
  const partnerAllocations = allocations.filter((allocation) => allocation.partner_id === partnerId && allocation.status !== 'reversed');
  const distributed = partnerAllocations.reduce((sum, allocation) => sum + allocation.allocated_amount_egp, 0);
  const paid = -sumLedgerEffects(
    ledgerEntries.filter((entry) => entry.partner_id === partnerId && entry.entry_type === 'distribution_payment'),
  );
  return {
    distributed_egp: distributed,
    paid_egp: paid,
    unpaid_egp: Math.max(0, distributed - paid),
  };
}

export function signedLedgerEffect(entry: PartnerLedgerEntry): number {
  switch (entry.entry_type) {
    case 'capital_contribution':
    case 'distribution_entitlement':
    case 'correction':
      return entry.amount_egp;
    case 'withdrawal':
    case 'distribution_payment':
      return -entry.amount_egp;
    case 'reversal':
      return 0;
  }
}

export function decorateLedgerEntries(entries: PartnerLedgerEntry[]): LedgerEntryWithEffect[] {
  const reversedIds = new Set(
    entries
      .filter((entry) => entry.entry_type === 'reversal' && entry.reversal_of_id)
      .map((entry) => entry.reversal_of_id as string),
  );
  return entries
    .map((entry) => {
      const isReversedOriginal = reversedIds.has(entry.id);
      const activeEffect = entry.entry_type === 'reversal' || isReversedOriginal ? 0 : signedLedgerEffect(entry);
      const nativeSign = entry.amount_egp === 0 ? 0 : activeEffect / entry.amount_egp;
      return {
        ...entry,
        active_effect_egp: roundMoney(activeEffect),
        active_effect_native: roundMoney(entry.amount * nativeSign),
        is_reversed_original: isReversedOriginal,
      };
    })
    .sort((a, b) => b.posting_date.localeCompare(a.posting_date) || b.created_at.localeCompare(a.created_at));
}

export function sumLedgerEffects(entries: PartnerLedgerEntry[]): number {
  return roundMoney(decorateLedgerEntries(entries).reduce((sum, entry) => sum + entry.active_effect_egp, 0));
}

export function calculatePartnerLedgerSummary(entries: PartnerLedgerEntry[]): PartnerLedgerSummary {
  const decorated = decorateLedgerEntries(entries);
  const sumType = (type: PartnerLedgerEntryType) => decorated
    .filter((entry) => entry.entry_type === type)
    .reduce((sum, entry) => sum + Math.abs(entry.active_effect_egp), 0);
  const historicalTotal = entries.reduce((sum, entry) => sum + entry.amount_egp, 0);
  const profitEntitlements = sumType('distribution_entitlement');
  const payments = sumType('distribution_payment');

  return {
    capital_contributed_egp: sumType('capital_contribution'),
    withdrawals_egp: sumType('withdrawal'),
    profit_entitlements_egp: profitEntitlements,
    payments_made_egp: payments,
    reversals_egp: entries.filter((entry) => entry.entry_type === 'reversal').reduce((sum, entry) => sum + entry.amount_egp, 0),
    current_balance_egp: roundMoney(decorated.reduce((sum, entry) => sum + entry.active_effect_egp, 0)),
    distributed_unpaid_egp: Math.max(0, profitEntitlements - payments),
    paid_distributions_egp: payments,
    historical_total_egp: roundMoney(historicalTotal),
  };
}

export function partnerName(partner: Partner | undefined, locale: 'ar' | 'en'): string {
  if (!partner) return locale === 'ar' ? 'شريك غير موجود' : 'Missing partner';
  return locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar;
}

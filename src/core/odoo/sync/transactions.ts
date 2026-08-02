/**
 * Transaction sync: Terranex Transaction → Odoo account.move (journal entry)
 *
 * Odoo's account.move is the universal journal entry for invoices, bills,
 * expenses and revenue. For Phase 1 we post miscellaneous journal entries
 * type = 'entry' attached to the correct journal (Cash/Bank/Sales/Expense).
 *
 * Default journals (IDs configurable in company settings later):
 *   - Sales Journal:   INV → income transactions
 *   - Purchase Journal: BILL → expense transactions that hit a supplier
 *   - Bank/Cash Journal: payments posted via Settlement, not directly here
 *   - Misc Journal (MISC): fallback for direct income/expense entries
 */
import type { Partner, Project, Transaction } from '../../types/domain';
import type { OdooClient } from '../client';

interface Context {
  partner?: Partner;
  project?: Project;
  defaultRevenueAccountId?: number; // chart of accounts income account
  defaultExpenseAccountId?: number; // chart of accounts expense account
  partnerReceivableAccountId?: number;
  partnerPayableAccountId?: number;
  miscJournalId: number;
  salesJournalId?: number;
  purchaseJournalId?: number;
  bankJournalId?: number;
  companyId?: number;
}

/**
 * Best-effort: maps a Terranex transaction category to an Odoo account ID.
 * Returns undefined if no mapping exists (caller should fall back to default).
 */
function categoryToAccount(tx: Transaction, ctx: Context): { debit: number; credit: number } | null {
  if (tx.direction === 'income') {
    const credit = ctx.defaultRevenueAccountId;
    if (!credit) return null;
    // If no specific bank/cash account is configured, post to a suspense
    // receivable account (fall back to the income account itself so the
    // entry is at least balanced until the accountant configures the chart).
    return { debit: ctx.partnerReceivableAccountId ?? credit, credit };
  }
  const debit = ctx.defaultExpenseAccountId;
  if (!debit) return null;
  return { debit, credit: ctx.partnerPayableAccountId ?? debit };
}

export async function syncTransactionAsMove(
  client: OdooClient,
  tx: Transaction,
  ctx: Context,
): Promise<number> {
  const accounts = categoryToAccount(tx, ctx);
  if (!accounts) {
    throw new Error(
      'لم يتم ضبط حسابات الإيرادات/المصروفات الافتراضية في Odoo بعد — راجع الإعدادات.',
    );
  }

  const lines = [
    // First line — debit or credit to the default account
    {
      account_id: tx.direction === 'income' ? accounts.debit : accounts.debit,
      name: tx.description || tx.category,
      debit: tx.direction === 'income' ? tx.amount_egp : 0,
      credit: tx.direction === 'expense' ? tx.amount_egp : 0,
      date: tx.transaction_date,
      partner_id: ctx.partner ? (ctx.partner as unknown as { odoo_res_id?: number }).odoo_res_id : false,
      analytic_distribution: ctx.project
        ? { [(ctx.project as unknown as { odoo_res_id?: number }).odoo_res_id ?? 0]: 100 }
        : false,
    },
    {
      account_id: accounts.credit,
      name: tx.description || tx.category,
      debit: tx.direction === 'expense' ? 0 : tx.amount_egp,
      credit: tx.direction === 'income' ? tx.amount_egp : 0,
      date: tx.transaction_date,
      partner_id: ctx.partner ? (ctx.partner as unknown as { odoo_res_id?: number }).odoo_res_id : false,
    },
  ].filter(l => l.debit !== 0 || l.credit !== 0);

  const moveId = await client.create('account.move', {
    ref: tx.id,
    date: tx.transaction_date,
    journal_id: ctx.miscJournalId,
    move_type: 'entry',
    line_ids: lines.map(l => [0, 0, l]),
    narr: tx.notes || tx.description,
    company_id: ctx.companyId || 1,
  });

  // Post immediately (Odoo requires moves to be posted to affect GL)
  await client.callKW({
    model: 'account.move',
    method: 'action_post',
    args: [[moveId]],
  });
  return moveId;
}

import { useState } from 'react';
import { BankAccountForm } from './BankAccountForm';
import { ManualTransactionForm, TransferForm } from './BankTransactionForm';
import { addBankAccount, addManualTransaction, archiveAccount, editBankAccount, transferBetweenAccounts, useBankAccounts, useBankTransactions } from './hooks';
import { markManuallyReviewed } from './storage';
import type { BankAccountInput, BankTransactionInput, TransferInput } from './types';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { formatMoney } from '../../core/lib/format';
import { ArrowLeftRight, Landmark, Plus, Trash2, Wallet, PiggyBank, ArrowDown, ArrowUp, CheckCheck, XCircle } from 'lucide-react';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import { useNavigate, useSearch } from '@tanstack/react-router';
import { bankingRoute } from '../../routes/banking';
import type { BankAccountWithBalance as BAWithBalance } from './types';

type DialogKind = null | 'add-account' | 'edit-account' | 'manual-transaction' | 'transfer';

const TYPE_ICON = {
  bank: Landmark,
  cash: Wallet,
  wallet: PiggyBank,
} as const;

const TYPE_LABEL_AR = {
  bank: 'بنك',
  cash: 'صندوق',
  wallet: 'محفظة',
} as const;

export function BankingPage() {
  const navigate = useNavigate();
  const search = useSearch({ from: '/banking' as never }) as { account?: string };
  const selectedId = search.account ?? undefined;

  const { accounts, loading: accountsLoading, error: accountsError, refresh: refreshAccounts } = useBankAccounts();
  const { transactions, loading: txLoading, refresh: refreshTx } = useBankTransactions(selectedId);
  const [dialog, setDialog] = useState<DialogKind>(null);
  const [editingAccountId, setEditingAccountId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const activeAccounts = accounts.filter(a => !a.is_archived);
  const totalBalanceBase = activeAccounts.reduce((sum, a) => sum + (a.balance_base ?? a.opening_balance ?? 0), 0);
  const selectedAccount = selectedId ? accounts.find(a => a.id === selectedId) : undefined;

  async function saveAccount(input: BankAccountInput) {
    setSaving(true); setError('');
    try {
      if (editingAccountId) {
        await editBankAccount(editingAccountId, input);
      } else {
        await addBankAccount(input);
      }
      await refreshAccounts();
      setDialog(null); setEditingAccountId(null);
      setSuccess('تم حفظ الحساب بنجاح.');
      setTimeout(() => setSuccess(''), 2500);
    } catch (e) { setError(translateServerError(e)); }
    finally { setSaving(false); }
  }

  async function addManualTx(input: BankTransactionInput) {
    setSaving(true); setError('');
    try {
      await addManualTransaction(input);
      await Promise.all([refreshAccounts(), refreshTx()]);
      setDialog(null);
      setSuccess('تم تسجيل الحركة بنجاح.');
      setTimeout(() => setSuccess(''), 2500);
    } catch (e) { setError(translateServerError(e)); }
    finally { setSaving(false); }
  }

  async function doTransfer(input: TransferInput) {
    setSaving(true); setError('');
    try {
      await transferBetweenAccounts(input);
      await Promise.all([refreshAccounts(), refreshTx()]);
      setDialog(null);
      setSuccess('تم تسجيل التحويل بنجاح.');
      setTimeout(() => setSuccess(''), 2500);
    } catch (e) { setError(translateServerError(e)); }
    finally { setSaving(false); }
  }

  async function handleArchive(id: string) {
    if (!confirm('هل أنت متأكد من أرشفة هذا الحساب؟')) return;
    setSaving(true);
    try {
      await archiveAccount(id);
      await refreshAccounts();
    } catch (e) { setError(translateServerError(e)); }
    finally { setSaving(false); }
  }

  async function handleManualReview(id: string, reviewed: boolean) {
    try {
      await markManuallyReviewed(id, reviewed);
      await refreshTx();
    } catch (e) { setError(translateServerError(e)); }
  }

  function openAccount(id: string) {
    navigate({ to: '/banking', search: { account: id } as never });
  }

  function closeAccount() {
    navigate({ to: '/banking', search: {} as never });
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold">البنوك والصناديق</h1>
          <p className="text-sm text-muted-foreground">إدارة الحسابات النقدية والبنكية ومحافظ الشركة.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="secondary" onClick={() => setDialog('manual-transaction')}>
            <ArrowUp className="h-4 w-4" /> إيداع/سحب يدوي
          </Button>
          <Button size="sm" variant="secondary" onClick={() => setDialog('transfer')}>
            <ArrowLeftRight className="h-4 w-4" /> تحويل بين الحسابات
          </Button>
          <Button size="sm" variant="primary" onClick={() => { setEditingAccountId(null); setDialog('add-account'); }}>
            <Plus className="h-4 w-4" /> حساب جديد
          </Button>
        </div>
      </div>

      {success && <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/30 px-4 py-2 text-sm text-emerald-600">{success}</div>}
      {error && <div className="rounded-xl bg-red-500/10 border border-red-500/30 px-4 py-2 text-sm text-red-600">{error}</div>}
      {(accountsError) && <div className="rounded-xl bg-amber-500/10 border border-amber-500/30 px-4 py-2 text-sm text-amber-700">{accountsError}</div>}

      {/* Summary card */}
      <div className="rounded-2xl bg-primary text-primary-foreground p-5 shadow-sm">
        <p className="text-xs opacity-80">إجمالي الأرصدة (بالعملة الأساس)</p>
        <p className="mt-1 text-3xl font-bold">{formatMoney(totalBalanceBase, 'EGP')}</p>
        <p className="mt-2 text-xs opacity-80">{activeAccounts.length} حساب نشط</p>
      </div>

      {/* Account cards */}
      {!selectedId && (
        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          {accountsLoading && <p className="text-sm text-muted-foreground">جارٍ تحميل الحسابات…</p>}
          {activeAccounts.map(acc => {
            const Icon = TYPE_ICON[acc.account_type];
            return (
              <Card key={acc.id} className="cursor-pointer transition hover:shadow-md" onClick={() => openAccount(acc.id)}>
                <CardContent className="p-4">
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-3">
                      <div className="rounded-xl bg-primary/10 p-2 text-primary"><Icon className="h-5 w-5" /></div>
                      <div>
                        <p className="font-semibold">{acc.name_ar}</p>
                        <p className="text-xs text-muted-foreground">
                          <Badge tone="neutral">{TYPE_LABEL_AR[acc.account_type]}</Badge>
                          {acc.bank_name && <span className="mx-1">· {acc.bank_name}</span>}
                        </p>
                      </div>
                    </div>
                    <button
                      type="button"
                      className="text-muted-foreground hover:text-red-500"
                      onClick={(e) => { e.stopPropagation(); void handleArchive(acc.id); }}
                      title="أرشفة"
                    ><Trash2 className="h-4 w-4" /></button>
                  </div>
                  <div className="mt-4">
                    <p className="text-xs text-muted-foreground">الرصيد الحالي</p>
                    <p className="text-2xl font-bold">{formatMoney(acc.balance ?? acc.opening_balance, acc.currency)}</p>
                  </div>
                </CardContent>
              </Card>
            );
          })}
          {!accountsLoading && activeAccounts.length === 0 && (
            <Card>
              <CardContent className="p-6 text-center text-sm text-muted-foreground">
                لا توجد حسابات بنكية بعد. ابدأ بإضافة أول حساب (بنك أو صندوق أو محفظة).
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Selected account details */}
      {selectedAccount && (
        <div className="space-y-3">
          <button type="button" onClick={closeAccount} className="text-sm text-primary hover:underline">← رجوع إلى قائمة الحسابات</button>
          <Card>
            <CardHeader>
              <div className="flex items-center gap-3">
                <div className="rounded-xl bg-primary/10 p-2 text-primary">
                  {(() => { const I = TYPE_ICON[selectedAccount.account_type]; return <I className="h-5 w-5" />; })()}
                </div>
                <div>
                  <h2 className="text-lg font-bold">{selectedAccount.name_ar}</h2>
                  <p className="text-xs text-muted-foreground">{TYPE_LABEL_AR[selectedAccount.account_type]} · {selectedAccount.currency}</p>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">{formatMoney(selectedAccount.balance ?? selectedAccount.opening_balance, selectedAccount.currency)}</p>
              {selectedAccount.bank_name && <p className="mt-1 text-xs text-muted-foreground">{selectedAccount.bank_name} · {selectedAccount.account_number}</p>}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <span className="text-sm font-semibold">حركات الحساب</span>
            </CardHeader>
            <CardContent>
              {txLoading ? <p className="text-sm text-muted-foreground">جارٍ التحميل…</p> : (
                <div className="divide-y divide-border">
                  {transactions.length === 0 && <p className="py-6 text-center text-sm text-muted-foreground">لا توجد حركات على هذا الحساب.</p>}
                  {transactions.map(tx => (
                    <div key={tx.id} className={`flex items-center justify-between gap-3 py-3 ${tx.is_reconciled ? 'opacity-70' : ''}`}>
                      <div className="flex items-center gap-3">
                        <div className={`rounded-full p-2 ${tx.direction === 'deposit' ? 'bg-emerald-500/10 text-emerald-600' : 'bg-red-500/10 text-red-600'}`}>
                          {tx.direction === 'deposit' ? <ArrowDown className="h-4 w-4" /> : <ArrowUp className="h-4 w-4" />}
                        </div>
                        <div>
                          <p className="text-sm font-medium">
                            {tx.memo ?? (tx.direction === 'deposit' ? 'إيداع' : 'سحب')}
                            {tx.is_reconciled && <span className="ms-2 rounded-full bg-success/10 px-2 py-0.5 text-[10px] text-success">تمت مراجعته يدويًا</span>}
                          </p>
                          <p className="text-xs text-muted-foreground">{tx.transaction_date} · {tx.reference_type}</p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <p className={`font-semibold ${tx.direction === 'deposit' ? 'text-emerald-600' : 'text-red-600'}`}>
                          {tx.direction === 'deposit' ? '+' : '-'}{formatMoney(tx.amount, tx.currency)}
                        </p>
                        {tx.is_reconciled ? (
                          <button type="button" onClick={() => handleManualReview(tx.id, false)} title="إلغاء علامة المراجعة اليدوية" className="rounded-lg p-1.5 text-muted-foreground hover:text-danger">
                            <XCircle className="h-4 w-4" />
                          </button>
                        ) : (
                          <button type="button" onClick={() => handleManualReview(tx.id, true)} title="وضع علامة تمت مراجعته يدويًا" className="rounded-lg p-1.5 text-muted-foreground hover:text-success">
                            <CheckCheck className="h-4 w-4" />
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* Dialogs */}
      {dialog === 'add-account' && (
        <Card><CardHeader><span className="text-sm font-semibold">إضافة حساب جديد</span></CardHeader>
          <CardContent><BankAccountForm onSubmit={saveAccount} onCancel={() => setDialog(null)} saving={saving} /></CardContent>
        </Card>
      )}
      {dialog === 'manual-transaction' && (
        <Card><CardHeader><span className="text-sm font-semibold">تسجيل حركة يدوية</span></CardHeader>
          <CardContent><ManualTransactionForm accounts={accounts} onSubmit={addManualTx} onCancel={() => setDialog(null)} saving={saving} /></CardContent>
        </Card>
      )}
      {dialog === 'transfer' && (
        <Card><CardHeader><span className="text-sm font-semibold">تحويل بين الحسابات</span></CardHeader>
          <CardContent><TransferForm accounts={accounts} onSubmit={doTransfer} onCancel={() => setDialog(null)} saving={saving} /></CardContent>
        </Card>
      )}
    </div>
  );
}

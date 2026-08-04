import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { CheckCircle2, CreditCard, HandCoins, Loader2 } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { Card, CardContent } from '../../components/ui/Card';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { formatEgp } from '../../core/lib/profitability';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import type {
  BankAccount,
  Distribution,
  DistributionAllocation,
  Partner,
} from '../../core/types/domain';
import { DistributionPaymentReversalAction } from './DistributionPaymentReversalAction';
import { partnerName } from './model';

interface DistributionLifecyclePanelProps {
  distributions: Distribution[];
  allocations: DistributionAllocation[];
  partners: Partner[];
  locale: 'ar' | 'en';
}

interface PaymentTarget {
  distribution: Distribution;
  allocation: DistributionAllocation;
}

interface DistributionPaymentCommand {
  allocation_id: string;
  bank_account_id: string;
  payment_date: string;
  notes?: string;
}

function readableError(error: unknown): string {
  if (
    error
    && typeof error === 'object'
    && 'message_ar' in error
    && typeof error.message_ar === 'string'
  ) {
    return error.message_ar;
  }
  return translateServerError(error);
}

async function loadEligibleBankAccounts(currency: Distribution['currency']): Promise<BankAccount[]> {
  const { listBankAccounts } = await import('../banking/storage');
  const accounts = await listBankAccounts();
  return accounts.filter((account) => !account.is_archived && account.currency === currency);
}

async function approveDistributionOnServer(distributionId: string): Promise<void> {
  const { approveProfitDistribution } = await import('./service');
  await approveProfitDistribution({ distribution_id: distributionId });
}

async function payAllocationOnServer(command: DistributionPaymentCommand): Promise<void> {
  const { payDistributionAllocation } = await import('./service');
  await payDistributionAllocation(command);
}

export function DistributionLifecyclePanel({
  distributions,
  allocations,
  partners,
  locale,
}: DistributionLifecyclePanelProps) {
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const partnerById = useMemo(
    () => new Map(partners.map((partner) => [partner.id, partner])),
    [partners],
  );
  const orderedDistributions = useMemo(
    () => [...distributions].sort((a, b) => b.distribution_date.localeCompare(a.distribution_date)),
    [distributions],
  );
  const [approvalTarget, setApprovalTarget] = useState<Distribution | null>(null);
  const [paymentTarget, setPaymentTarget] = useState<PaymentTarget | null>(null);
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([]);
  const [bankAccountId, setBankAccountId] = useState('');
  const [paymentDate, setPaymentDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [paymentNotes, setPaymentNotes] = useState('');
  const [pending, setPending] = useState(false);
  const [loadingAccounts, setLoadingAccounts] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!paymentTarget) return;
    let active = true;
    setLoadingAccounts(true);
    setError(null);
    setBankAccountId('');
    void loadEligibleBankAccounts(paymentTarget.distribution.currency)
      .then((eligible) => {
        if (!active) return;
        setBankAccounts(eligible);
        if (eligible.length === 1) setBankAccountId(eligible[0].id);
      })
      .catch((loadError) => {
        if (active) setError(readableError(loadError));
      })
      .finally(() => {
        if (active) setLoadingAccounts(false);
      });
    return () => {
      active = false;
    };
  }, [paymentTarget]);

  async function approveDistribution(): Promise<void> {
    if (!approvalTarget) return;
    setPending(true);
    setError(null);
    try {
      await approveDistributionOnServer(approvalTarget.id);
      setApprovalTarget(null);
    } catch (approvalError) {
      setApprovalTarget(null);
      setError(readableError(approvalError));
    } finally {
      setPending(false);
    }
  }

  async function submitPayment(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    if (!paymentTarget) return;
    if (!bankAccountId) {
      setError(label('اختر حساب البنك أو الخزينة.', 'Choose a bank or cash account.'));
      return;
    }
    if (!paymentDate) {
      setError(label('تاريخ الدفع مطلوب.', 'Payment date is required.'));
      return;
    }
    setPending(true);
    setError(null);
    try {
      await payAllocationOnServer({
        allocation_id: paymentTarget.allocation.id,
        bank_account_id: bankAccountId,
        payment_date: paymentDate,
        notes: paymentNotes.trim() || undefined,
      });
      setPaymentTarget(null);
      setBankAccountId('');
      setPaymentNotes('');
    } catch (paymentError) {
      setError(readableError(paymentError));
    } finally {
      setPending(false);
    }
  }

  if (orderedDistributions.length === 0) return null;

  return (
    <>
      <div className="mt-4 space-y-3" aria-label={label('دورة توزيعات المشروع', 'Project distribution lifecycle')}>
        {error && !paymentTarget && (
          <div role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">
            {error}
          </div>
        )}
        {orderedDistributions.slice(0, 8).map((distribution) => {
          const distributionAllocations = allocations.filter(
            (allocation) => allocation.distribution_id === distribution.id,
          );
          const paidAmount = distributionAllocations
            .filter((allocation) => allocation.status === 'paid')
            .reduce((sum, allocation) => sum + allocation.allocated_amount_egp, 0);
          const dueAllocations = distributionAllocations.filter((allocation) => allocation.status === 'due');
          const statusLabel = distribution.status === 'draft'
            ? label('مسودة', 'Draft')
            : distribution.status === 'approved'
              ? label('معتمد', 'Approved')
              : distribution.status === 'paid'
                ? label('مدفوع بالكامل', 'Fully paid')
                : label('ملغي', 'Cancelled');

          return (
            <Card key={distribution.id}>
              <CardContent className="p-4">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <HandCoins className="h-4 w-4 text-primary" />
                      <h5 className="font-extrabold">
                        {formatEgp(distribution.total_amount_egp, true)} EGP
                      </h5>
                      <span className="rounded-full border bg-muted px-2 py-1 text-xs font-semibold">
                        {statusLabel}
                      </span>
                    </div>
                    <p className="mt-2 text-xs text-muted-foreground">
                      {label('تاريخ التوزيع', 'Distribution date')}: {distribution.distribution_date}
                      {' · '}
                      {label('الملكية كما في', 'Ownership as of')}: {distribution.ownership_as_of_date}
                    </p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {label('المدفوع', 'Paid')}: {formatEgp(paidAmount, true)} EGP
                      {' · '}
                      {label('المتبقي', 'Remaining')}: {formatEgp(Math.max(0, distribution.total_amount_egp - paidAmount), true)} EGP
                    </p>
                  </div>
                  {distribution.status === 'draft' && (
                    <Button
                      size="sm"
                      onClick={() => {
                        setError(null);
                        setApprovalTarget(distribution);
                      }}
                      disabled={pending}
                    >
                      <CheckCircle2 className="h-4 w-4" />
                      {label('اعتماد التوزيع', 'Approve distribution')}
                    </Button>
                  )}
                </div>

                {distribution.status !== 'draft' && distributionAllocations.length > 0 && (
                  <div className="mt-4 grid gap-2 sm:grid-cols-2">
                    {distributionAllocations.map((allocation) => {
                      const partner = partnerById.get(allocation.partner_id);
                      return (
                        <div key={allocation.id} className="rounded-xl border bg-muted/10 p-3">
                          <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0">
                              <p className="truncate text-sm font-bold">{partnerName(partner, locale)}</p>
                              <p className="mt-1 text-xs text-muted-foreground">
                                {allocation.equity_pct_snapshot.toFixed(2)}% · {formatEgp(allocation.allocated_amount_egp, true)} EGP
                              </p>
                              <p className="mt-1 text-xs font-semibold">
                                {allocation.status === 'paid'
                                  ? label(`مدفوع في ${allocation.payment_date ?? ''}`, `Paid ${allocation.payment_date ?? ''}`)
                                  : allocation.status === 'reversed'
                                    ? label('معكوس', 'Reversed')
                                    : label('مستحق', 'Due')}
                              </p>
                            </div>
                            <div className="flex shrink-0 flex-col gap-2">
                              {distribution.status === 'approved' && allocation.status === 'due' && (
                                <Button
                                  variant="secondary"
                                  size="sm"
                                  onClick={() => {
                                    setError(null);
                                    setPaymentTarget({ distribution, allocation });
                                  }}
                                  disabled={pending}
                                >
                                  <CreditCard className="h-4 w-4" />
                                  {label('دفع الحصة', 'Pay share')}
                                </Button>
                              )}
                              {allocation.status === 'paid' && (
                                <DistributionPaymentReversalAction
                                  distribution={distribution}
                                  allocation={allocation}
                                  partner={partner}
                                  locale={locale}
                                  disabled={pending}
                                />
                              )}
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}

                {distribution.status === 'approved' && dueAllocations.length === 0 && (
                  <p role="status" className="mt-3 text-xs font-semibold text-success">
                    {label('لا توجد حصص مستحقة في هذا التوزيع.', 'No due allocations remain in this distribution.')}
                  </p>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>

      <ConfirmDialog
        open={Boolean(approvalTarget)}
        onOpenChange={(open) => {
          if (!open) {
            setApprovalTarget(null);
            setError(null);
          }
        }}
        title={label('اعتماد توزيع الأرباح', 'Approve profit distribution')}
        entityName={approvalTarget
          ? `${formatEgp(approvalTarget.total_amount_egp, true)} EGP`
          : ''}
        impact={label(
          'سيُنشئ الاعتماد استحقاقات ثابتة لكل شريك ويُرسل القيد المحاسبي إلى Odoo. لا يمكن تعديل التخصيصات بعد الاعتماد.',
          'Approval creates frozen partner entitlements and queues the accounting entry for Odoo. Allocations cannot be edited afterwards.',
        )}
        confirmLabel={label('اعتماد وإنشاء الاستحقاقات', 'Approve and create entitlements')}
        cancelLabel={label('إلغاء', 'Cancel')}
        onConfirm={approveDistribution}
        pending={pending}
        destructive={false}
      />

      <AdaptiveFormSurface
        open={Boolean(paymentTarget)}
        onOpenChange={(open) => {
          if (!open) {
            setPaymentTarget(null);
            setError(null);
            setBankAccountId('');
            setPaymentNotes('');
          }
        }}
        title={label('دفع حصة شريك', 'Pay partner allocation')}
        description={paymentTarget
          ? `${partnerName(partnerById.get(paymentTarget.allocation.partner_id), locale)} · ${formatEgp(paymentTarget.allocation.allocated_amount, true)} ${paymentTarget.distribution.currency}`
          : ''}
        pending={pending}
        formId="distribution-payment-form"
        submitLabel={label('تسجيل الدفع', 'Record payment')}
        cancelLabel={label('إلغاء', 'Cancel')}
        closeLabel={label('إغلاق نموذج الدفع', 'Close payment form')}
        error={<FormErrorSummary title={label('تعذر تسجيل الدفع', 'Could not record payment')} serverError={error} />}
      >
        <form id="distribution-payment-form" className="space-y-4" onSubmit={(event) => void submitPayment(event)}>
          <label className="block text-sm font-semibold">
            {label('حساب البنك أو الخزينة', 'Bank or cash account')}
            <select
              value={bankAccountId}
              onChange={(event) => setBankAccountId(event.target.value)}
              disabled={pending || loadingAccounts}
              required
              className="mt-1 min-h-11 w-full rounded-xl border bg-card px-3"
            >
              <option value="">
                {loadingAccounts
                  ? label('جار تحميل الحسابات...', 'Loading accounts...')
                  : label('اختر الحساب', 'Choose account')}
              </option>
              {bankAccounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {locale === 'ar' ? account.name_ar : account.name_en || account.name_ar} · {account.currency}
                </option>
              ))}
            </select>
          </label>
          {!loadingAccounts && bankAccounts.length === 0 && (
            <p role="alert" className="rounded-xl border border-warning/30 bg-warning/5 p-3 text-sm text-warning-foreground">
              {label(
                `لا يوجد حساب نشط بعملة ${paymentTarget?.distribution.currency ?? ''}. أنشئ حسابًا مطابقًا من مساحة البنوك أولًا.`,
                `No active ${paymentTarget?.distribution.currency ?? ''} account is available. Create a matching account in Banking first.`,
              )}
            </p>
          )}
          <label className="block text-sm font-semibold">
            {label('تاريخ الدفع', 'Payment date')}
            <input
              type="date"
              value={paymentDate}
              onChange={(event) => setPaymentDate(event.target.value)}
              disabled={pending}
              required
              className="mt-1 min-h-11 w-full rounded-xl border bg-card px-3"
            />
          </label>
          <label className="block text-sm font-semibold">
            {label('ملاحظات', 'Notes')}
            <textarea
              value={paymentNotes}
              onChange={(event) => setPaymentNotes(event.target.value)}
              disabled={pending}
              rows={3}
              className="mt-1 w-full rounded-xl border bg-card px-3 py-2"
            />
          </label>
          {(pending || loadingAccounts) && (
            <p role="status" className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              {pending
                ? label('جار تنفيذ العملية ذريًا...', 'Processing the atomic operation...')
                : label('جار تحميل الحسابات...', 'Loading accounts...')}
            </p>
          )}
        </form>
      </AdaptiveFormSurface>
    </>
  );
}

import { useState, type FormEvent } from 'react';
import { Loader2, RotateCcw } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { formatEgp } from '../../core/lib/profitability';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import type { Distribution, DistributionAllocation, Partner } from '../../core/types/domain';
import { partnerName } from './model';

interface DistributionPaymentReversalActionProps {
  distribution: Distribution;
  allocation: DistributionAllocation;
  partner?: Partner;
  locale: 'ar' | 'en';
  disabled?: boolean;
}

interface ReversePaymentCommand {
  entry_id: string;
  posting_date: string;
  reason: string;
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

async function reversePaymentOnServer(command: ReversePaymentCommand): Promise<void> {
  const { reversePartnerLedgerEntry } = await import('./service');
  await reversePartnerLedgerEntry(command);
}

export function DistributionPaymentReversalAction({
  distribution,
  allocation,
  partner,
  locale,
  disabled = false,
}: DistributionPaymentReversalActionProps) {
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const [open, setOpen] = useState(false);
  const [postingDate, setPostingDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [reason, setReason] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (allocation.status !== 'paid') return null;

  const ledgerEntryId = allocation.related_ledger_entry_id;
  const canReverse = Boolean(ledgerEntryId) && !disabled;

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    const normalizedReason = reason.trim();
    if (!ledgerEntryId) {
      setError(label(
        'لا يمكن عكس الدفعة لأن مرجع قيد الدفتر غير موجود.',
        'This payment cannot be reversed because its ledger reference is missing.',
      ));
      return;
    }
    if (!postingDate) {
      setError(label('تاريخ العكس مطلوب.', 'Reversal date is required.'));
      return;
    }
    if (!normalizedReason) {
      setError(label('سبب العكس إلزامي لحماية مسار التدقيق.', 'A reversal reason is required for the audit trail.'));
      return;
    }

    setPending(true);
    setError(null);
    try {
      await reversePaymentOnServer({
        entry_id: ledgerEntryId,
        posting_date: postingDate,
        reason: normalizedReason,
      });
      setOpen(false);
      setReason('');
    } catch (reversalError) {
      setError(readableError(reversalError));
    } finally {
      setPending(false);
    }
  }

  return (
    <>
      <Button
        variant="danger"
        size="sm"
        disabled={!canReverse}
        title={!ledgerEntryId
          ? label('مرجع قيد الدفتر غير متاح؛ العكس مقفول.', 'Ledger reference is unavailable; reversal is locked.')
          : undefined}
        onClick={() => {
          setError(null);
          setOpen(true);
        }}
      >
        <RotateCcw className="h-4 w-4" />
        {label('عكس الدفعة', 'Reverse payment')}
      </Button>

      <AdaptiveFormSurface
        open={open}
        onOpenChange={(nextOpen) => {
          if (!nextOpen && !pending) {
            setOpen(false);
            setError(null);
            setReason('');
          }
        }}
        title={label('عكس دفعة توزيع', 'Reverse distribution payment')}
        description={`${partnerName(partner, locale)} · ${formatEgp(allocation.allocated_amount, true)} ${distribution.currency}`}
        pending={pending}
        formId={`distribution-payment-reversal-${allocation.id}`}
        submitLabel={label('تأكيد العكس', 'Confirm reversal')}
        cancelLabel={label('إلغاء', 'Cancel')}
        closeLabel={label('إغلاق نموذج العكس', 'Close reversal form')}
        error={<FormErrorSummary title={label('تعذر عكس الدفعة', 'Could not reverse payment')} serverError={error} />}
      >
        <form
          id={`distribution-payment-reversal-${allocation.id}`}
          className="space-y-4"
          onSubmit={(event) => void submit(event)}
        >
          <div className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm leading-6 text-danger">
            {label(
              'سيُنشئ النظام قيدًا عكسيًا وحركة نقدية مقابلة، ويعيد فتح حصة الشريك والتوزيع إن كان مغلقًا بالكامل. لن يُحذف السجل الأصلي.',
              'The system will create an append-only reversal and opposite cash movement, then reopen the partner allocation and the distribution when needed. The original record will not be deleted.',
            )}
          </div>

          <label className="block text-sm font-semibold">
            {label('تاريخ العكس', 'Reversal date')}
            <input
              type="date"
              value={postingDate}
              onChange={(event) => setPostingDate(event.target.value)}
              disabled={pending}
              required
              className="mt-1 min-h-11 w-full rounded-xl border bg-card px-3"
            />
          </label>

          <label className="block text-sm font-semibold">
            {label('سبب العكس', 'Reversal reason')}
            <textarea
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              disabled={pending}
              required
              minLength={3}
              rows={4}
              placeholder={label('اكتب السبب الذي سيظهر في سجل التدقيق...', 'Enter the reason recorded in the audit trail...')}
              className="mt-1 w-full rounded-xl border bg-card px-3 py-2"
            />
          </label>

          {pending && (
            <p role="status" className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              {label('جار إنشاء القيد والحركة العكسية ذريًا...', 'Creating the atomic ledger and cash reversal...')}
            </p>
          )}
        </form>
      </AdaptiveFormSurface>
    </>
  );
}

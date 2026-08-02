import { useCallback } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormHint, FormLabel } from '../../components/ui/FormControls';
import { obligationSchema, type ObligationFormValues } from '../../core/lib/validation';
import { useI18n } from '../../core/i18n/context';
import { useAutoFxRate } from '../settings/useAutoFxRate';
import type { ObligationInput } from './storage';
import type { Obligation, Partner, Project, Currency } from '../../core/types/domain';

interface Props {
  partners: Partner[];
  projects: Project[];
  onSubmit: (input: ObligationInput) => void | Promise<void>;
  onCancel: () => void;
  defaultProjectId?: string;
  defaultPartnerId?: string;
  initial?: Partial<Obligation>;
  formId?: string;
  hideActions?: boolean;
}

export function ObligationForm({ partners, projects, onSubmit, onCancel, defaultProjectId, defaultPartnerId, initial, formId, hideActions = false }: Props) {
  const { t, locale } = useI18n();

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<ObligationFormValues>({
    resolver: zodResolver(obligationSchema) as any,
    defaultValues: {
      direction: initial?.direction ?? 'receivable',
      partner_id: initial?.partner_id ?? defaultPartnerId ?? '',
      project_id: initial?.project_id ?? defaultProjectId ?? '',
      amount: initial?.amount ?? undefined as any,
      currency: initial?.currency ?? 'EGP',
      fx_rate: initial?.fx_rate ?? 1,
      due_date: initial?.due_date ?? '',
      document_id: initial?.document_id ?? '',
      notes: initial?.notes ?? '',
    },
    mode: 'onBlur',
  });

  const direction = watch('direction');
  const currency = watch('currency') as Currency;
  const fx_rate = Number(watch('fx_rate')) || 1;
  const amount = Number(watch('amount')) || 0;
  const effectiveFx = currency === 'EGP' ? 1 : fx_rate;
  const amountBase = amount * effectiveFx;

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const onFxChange = useCallback((rate: number) => {
    setValue('fx_rate', rate, { shouldValidate: true });
  }, [setValue]);
  useAutoFxRate(currency, onFxChange);

  const submit = async (v: ObligationFormValues) => {
    const amountNum = Number(v.amount);
    const fx = v.currency === 'EGP' ? 1 : Number(v.fx_rate);
    await onSubmit({
      direction: v.direction,
      partner_id: v.partner_id,
      project_id: v.project_id || undefined,
      amount: amountNum,
      currency: v.currency as Currency,
      fx_rate: fx,
      amount_egp: Math.round(amountNum * fx * 1000) / 1000,
      due_date: v.due_date || undefined,
      document_id: v.document_id || undefined,
      status: initial?.status ?? 'open',
      notes: v.notes || undefined,
    });
  };

  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'block text-sm font-medium text-foreground mb-1';

  return (
    <form id={formId} onSubmit={handleSubmit(submit)} className="space-y-4" noValidate>
      <div className="flex gap-2">
        {(['receivable','payable'] as const).map(d => (
          <label key={d} className="flex-1 cursor-pointer">
            <input type="radio" value={d} {...register('direction')} className="sr-only peer" />
            <div className={`rounded-xl border py-2.5 text-center text-sm font-semibold transition peer-checked:ring-2
              ${d==='receivable'
                ? 'peer-checked:border-success peer-checked:bg-success/10 peer-checked:text-success'
                : 'peer-checked:border-danger peer-checked:bg-danger/10 peer-checked:text-danger'
              } border-border text-muted-foreground hover:bg-muted`}>
              {d === 'receivable' ? `← ${t('obligation_direction_receivable')}` : `${t('obligation_direction_payable')} →`}
            </div>
          </label>
        ))}
      </div>
      {errors.direction && <FormError>{errors.direction.message}</FormError>}

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <label className={lc}>{t('transaction_counterparty')} *</label>
          <select className={ic} {...register('partner_id')}>
            <option value="">{locale==='ar' ? 'اختر الطرف…' : 'Choose…'}</option>
            {partners.map(p => <option key={p.id} value={p.id}>{locale==='ar' ? p.name_ar : (p.name_en || p.name_ar)}</option>)}
          </select>
          {errors.partner_id && <FormError>{errors.partner_id.message}</FormError>}
        </FormField>

        <FormField>
          <label className={lc}>{t('project_name_ar')} ({locale==='ar'?'اختياري':'optional'})</label>
          <select className={ic} {...register('project_id')}>
            <option value="">{locale==='ar' ? 'بدون مشروع' : 'No project'}</option>
            {projects.map(p => <option key={p.id} value={p.id}>{locale==='ar' ? p.name_ar : (p.name_en || p.name_ar)}</option>)}
          </select>
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <label className={lc}>{t('transaction_amount')} *</label>
          <input type="number" step="0.001" min="0" {...register('amount', { valueAsNumber: true })} className={ic} dir="ltr" placeholder="0.000" />
          {errors.amount && <FormError>{errors.amount.message}</FormError>}
        </FormField>

        <FormField>
          <label className={lc}>{t('transaction_currency')}</label>
          <select {...register('currency')} className={ic}>
            {['EGP','USD','OMR','SAR','AED','EUR','GBP'].map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </FormField>

        <FormField>
          <label className={lc}>{t('obligation_due_date')}</label>
          <input type="date" {...register('due_date')} className={ic} />
        </FormField>
      </div>

      {currency !== 'EGP' && (
        <FormField>
          <label className={lc}>{t('transaction_fx_rate')}</label>
          <input type="number" step="0.0001" min="0" {...register('fx_rate', { valueAsNumber: true })} className={ic} dir="ltr" />
          {errors.fx_rate && <FormError>{errors.fx_rate.message}</FormError>}
          <FormHint>المكافئ بالعملة المرجعية: {amountBase.toLocaleString(locale === 'ar' ? 'ar-EG' : 'en-US', { maximumFractionDigits: 3 })}</FormHint>
        </FormField>
      )}

      <FormField>
        <label className={lc}>{t('transaction_notes')}</label>
        <textarea {...register('notes')} rows={2} className={ic} placeholder={locale==='ar' ? 'ملاحظات…' : 'Notes…'} />
      </FormField>

      {!hideActions && <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={isSubmitting}>
          {t('action_cancel')}
        </Button>
        <Button type="submit" disabled={isSubmitting} className={direction === 'receivable' ? 'bg-success hover:bg-success/90' : 'bg-danger hover:bg-danger/90'}>
          {isSubmitting ? (locale==='ar' ? 'جار الحفظ…' : 'Saving…') : t('action_save')}
        </Button>
      </div>}

      {Object.keys(errors).length > 0 && (
        <div className="rounded-xl bg-warning/5 border border-warning/20 p-3 text-xs text-warning" dir="rtl">
          {Object.entries(errors).map(([k,e]:any) => <div key={k}>• {k}: {e?.message}</div>)}
        </div>
      )}
    </form>
  );
}

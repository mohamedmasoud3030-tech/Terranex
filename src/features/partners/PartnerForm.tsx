import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import { partnerSchema, type PartnerFormValues } from '../../core/lib/validation';
import { useI18n } from '../../core/i18n/context';
import type { PartnerInput } from './storage';

const ROLES = [
  { id: 'supplier', ar: 'مورد', en: 'Supplier' },
  { id: 'client', ar: 'عميل', en: 'Client' },
  { id: 'service_provider', ar: 'مزود خدمة', en: 'Service Provider' },
  { id: 'lender', ar: 'ممول', en: 'Lender' },
  { id: 'government', ar: 'جهة حكومية', en: 'Government' },
  { id: 'other', ar: 'أخرى', en: 'Other' },
] as const;

interface Props {
  onSubmit: (input: PartnerInput) => void;
  onCancel: () => void;
  initial?: Partial<PartnerFormValues>;
}

export function PartnerForm({ onSubmit, onCancel, initial }: Props) {
  const { t, locale } = useI18n();

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<PartnerFormValues>({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    resolver: zodResolver(partnerSchema) as any,
    defaultValues: {
      name_ar: initial?.name_ar ?? '',
      name_en: initial?.name_en ?? '',
      category: initial?.category ?? 'counterparty',
      counterparty_role: initial?.counterparty_role ?? 'supplier',
      phone: initial?.phone ?? '',
      email: initial?.email ?? '',
      address: initial?.address ?? '',
      notes: initial?.notes ?? '',
    },
    mode: 'onBlur',
  });

  const category = watch('category');
  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'block text-sm font-medium text-foreground mb-1';

  const submit = (v: PartnerFormValues) => {
    onSubmit({
      name_ar: v.name_ar,
      name_en: v.name_en || undefined,
      category: v.category,
      counterparty_role: v.category === 'counterparty' ? v.counterparty_role : undefined,
      phone: v.phone || undefined,
      email: v.email || undefined,
      address: v.address || undefined,
      notes: v.notes || undefined,
    });
  };

  return (
    <form onSubmit={handleSubmit(submit)} className="space-y-4" noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <label className={lc}>{t('partner_name_ar')} *</label>
          <input className={ic} {...register('name_ar')} placeholder={locale==='ar' ? 'شركة الأمل للمقاولات' : 'Partner name'} />
          {errors.name_ar && <FormError>{errors.name_ar.message}</FormError>}
        </FormField>
        <FormField>
          <label className={lc}>{t('partner_name_ar')} (EN)</label>
          <input className={ic} {...register('name_en')} placeholder="Al-Amal Co." dir="ltr" />
          {errors.name_en && <FormError>{errors.name_en.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <label className={lc}>{t('partner_category')}</label>
          <select className={ic} {...register('category')}>
            <option value="counterparty">{t('partner_category_counterparty')}</option>
            <option value="equity_partner">{t('partner_category_equity')}</option>
          </select>
          {errors.category && <FormError>{errors.category.message}</FormError>}
        </FormField>

        {category === 'counterparty' && (
          <FormField>
            <label className={lc}>{t('partner_role')}</label>
            <select className={ic} {...register('counterparty_role')}>
              {ROLES.map(r => <option key={r.id} value={r.id}>{locale==='ar' ? r.ar : r.en}</option>)}
            </select>
            {errors.counterparty_role && <FormError>{errors.counterparty_role.message}</FormError>}
          </FormField>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <label className={lc}>{locale==='ar' ? 'رقم الهاتف' : 'Phone'}</label>
          <input className={ic} {...register('phone')} placeholder="+20..." dir="ltr" />
          {errors.phone && <FormError>{errors.phone.message}</FormError>}
        </FormField>
        <FormField>
          <label className={lc}>Email</label>
          <input className={ic} type="email" {...register('email')} placeholder="name@company.com" dir="ltr" />
          {errors.email && <FormError>{errors.email.message}</FormError>}
        </FormField>
      </div>

      <FormField>
        <label className={lc}>{locale==='ar' ? 'العنوان' : 'Address'}</label>
        <textarea className={ic} rows={2} {...register('address')} />
        {errors.address && <FormError>{errors.address.message}</FormError>}
      </FormField>

      <FormField>
        <label className={lc}>{locale==='ar' ? 'ملاحظات' : 'Notes'}</label>
        <textarea className={ic} rows={2} {...register('notes')} />
        {errors.notes && <FormError>{errors.notes.message}</FormError>}
      </FormField>

      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={isSubmitting}>
          {t('action_cancel')}
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          {isSubmitting ? (locale==='ar' ? 'جار الحفظ…' : 'Saving…') : t('action_save')}
        </Button>
      </div>

      {Object.keys(errors).length > 0 && (
        <div className="rounded-xl bg-warning/5 border border-warning/20 p-3 text-xs text-warning" dir="rtl">
          {Object.entries(errors).map(([k, e]: any) => <div key={k}>• {k}: {e?.message}</div>)}
        </div>
      )}
    </form>
  );
}

import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import {
  projectPartnerSchema,
  type ProjectPartnerFormValues,
} from '../../core/lib/validation';
import type { Partner, ProjectPartner } from '../../core/types/domain';
import type { ProjectPartnerInput } from '../partners/storage';
import { validateEquityAddition } from './model';

export function ProjectPartnerForm({
  formId,
  projectId,
  partners,
  projectPartners,
  locale,
  onSubmit,
}: {
  formId: string;
  projectId: string;
  partners: Partner[];
  projectPartners: ProjectPartner[];
  locale: 'ar' | 'en';
  onSubmit: (input: ProjectPartnerInput) => void | Promise<void>;
}) {
  const available = partners.filter(
    (partner) => partner.category === 'equity_partner'
      && !projectPartners.some(
        (link) => link.project_id === projectId && link.partner_id === partner.id && !link.effective_to,
      ),
  );
  const {
    register,
    handleSubmit,
    setError,
    formState: { errors },
  } = useForm<ProjectPartnerFormValues>({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    resolver: zodResolver(projectPartnerSchema) as any,
    defaultValues: {
      project_id: projectId,
      partner_id: '',
      equity_pct: 0,
      effective_from: new Date().toISOString().slice(0, 10),
      effective_to: '',
      notes: '',
    },
    mode: 'onBlur',
  });
  const current = validateEquityAddition(projectPartners, projectId, 0);
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const inputClass = 'min-h-11 w-full rounded-xl border bg-background px-3 text-sm';

  const submit = async (values: ProjectPartnerFormValues) => {
    const boundary = validateEquityAddition(projectPartners, projectId, values.equity_pct);
    if (!boundary.valid) {
      setError('equity_pct', {
        message: label(
          `النسبة تتجاوز المتاح حاليًا (${boundary.remaining.toFixed(2)}%)`,
          `Percentage exceeds the remaining ${boundary.remaining.toFixed(2)}%`,
        ),
      });
      return;
    }
    await onSubmit({
      project_id: projectId,
      partner_id: values.partner_id,
      equity_pct: values.equity_pct,
      effective_from: values.effective_from,
      effective_to: values.effective_to || undefined,
      notes: values.notes || undefined,
    });
  };

  return (
    <form id={formId} onSubmit={handleSubmit(submit)} className="space-y-4" noValidate>
      <input type="hidden" {...register('project_id')} />
      <FormField>
        <FormLabel>{label('شريك الملكية', 'Equity partner')}</FormLabel>
        <select {...register('partner_id')} className={inputClass}>
          <option value="">{label('اختر الشريك', 'Select partner')}</option>
          {available.map((partner) => (
            <option key={partner.id} value={partner.id}>
              {locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar}
            </option>
          ))}
        </select>
        {available.length === 0 && (
          <p className="text-xs text-muted-foreground">
            {label('لا يوجد شريك ملكية متاح للربط.', 'No equity partner is available to link.')}
          </p>
        )}
        {errors.partner_id && <FormError>{errors.partner_id.message}</FormError>}
      </FormField>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{label('نسبة الملكية', 'Equity percentage')}</FormLabel>
          <input type="number" min="0.01" max={current.remaining} step="0.01" {...register('equity_pct')} className={inputClass} />
          <p className="text-xs text-muted-foreground">
            {label('المتاح', 'Remaining')}: {current.remaining.toFixed(2)}%
          </p>
          {errors.equity_pct && <FormError>{errors.equity_pct.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('ساري من', 'Effective from')}</FormLabel>
          <input type="date" {...register('effective_from')} className={inputClass} />
          {errors.effective_from && <FormError>{errors.effective_from.message}</FormError>}
        </FormField>
      </div>
      <FormField>
        <FormLabel>{label('ملاحظات', 'Notes')}</FormLabel>
        <textarea {...register('notes')} rows={3} className={`${inputClass} py-3`} />
        {errors.notes && <FormError>{errors.notes.message}</FormError>}
      </FormField>
    </form>
  );
}

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useI18n } from '../../core/i18n/context';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import type { ProjectInput } from './storage';
import type { Project, SectorId, Currency } from '../../core/types/domain';
import { projectSchema, type ProjectFormValues } from '../../core/lib/validation';

const SECTORS: { id: SectorId; ar: string; en: string }[] = [
  { id: 'real-estate', ar: 'العقاري', en: 'Real Estate' },
  { id: 'agriculture', ar: 'الزراعي', en: 'Agriculture' },
  { id: 'livestock', ar: 'الحيواني', en: 'Livestock' },
];

const CURRENCIES: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

const STATUSES: { id: Project['status']; ar: string; en: string }[] = [
  { id: 'planning', ar: 'تخطيط', en: 'Planning' },
  { id: 'active', ar: 'نشط', en: 'Active' },
  { id: 'on_hold', ar: 'متوقف مؤقتاً', en: 'On Hold' },
  { id: 'completed', ar: 'مكتمل', en: 'Completed' },
  { id: 'cancelled', ar: 'ملغى', en: 'Cancelled' },
];

interface Props {
  initial?: Partial<Project>;
  onSubmit: (input: ProjectInput) => void;
  onCancel: () => void;
  loading?: boolean;
  // allow forcing sector (used in sector pages)
  sectorLock?: SectorId;
}

export function ProjectForm({ initial, onSubmit, onCancel, loading, sectorLock }: Props) {
  const { t, locale } = useI18n();

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<ProjectFormValues>({
    resolver: zodResolver(projectSchema) as any,
    defaultValues: {
      sector_id: (initial?.sector_id ?? sectorLock ?? 'real-estate') as SectorId,
      name_ar: initial?.name_ar ?? '',
      name_en: initial?.name_en ?? '',
      description_ar: initial?.description_ar ?? '',
      description_en: initial?.description_en ?? '',
      status: initial?.status ?? 'active',
      start_date: initial?.start_date ?? new Date().toISOString().slice(0, 10),
      end_date: initial?.end_date ?? '',
      base_currency: initial?.base_currency ?? 'EGP',
    },
    mode: 'onBlur',
  });

  const submit = (values: ProjectFormValues) => {
    onSubmit({
      name_ar: values.name_ar,
      name_en: values.name_en || '',
      sector_id: values.sector_id,
      status: values.status,
      start_date: values.start_date,
      end_date: values.end_date || undefined,
      base_currency: values.base_currency,
      description_ar: values.description_ar || undefined,
      description_en: values.description_en || undefined,
    });
  };

  return (
    <form onSubmit={handleSubmit(submit)} className="space-y-4" noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="project-name-ar">{t('project_name_ar')} *</FormLabel>
          <input
            id="project-name-ar"
            {...register('name_ar')}
            className="w-full rounded-xl border border-border bg-background px-3 py-2.5"
            placeholder={locale==='ar' ? 'مشروع أرض المرسى' : 'Project name'}
            dir="rtl"
          />
          {errors.name_ar && <FormError>{errors.name_ar.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel htmlFor="project-name-en">{t('project_name_en')}</FormLabel>
          <input
            id="project-name-en"
            {...register('name_en')}
            className="w-full rounded-xl border border-border bg-background px-3 py-2.5"
            placeholder="Al-Marsa Land Project"
            dir="ltr"
          />
          {errors.name_en && <FormError>{errors.name_en.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel>{t('project_sector')}</FormLabel>
          <select
            {...register('sector_id')}
            disabled={!!sectorLock}
            className="w-full rounded-xl border border-border bg-background px-3 py-2.5 disabled:opacity-60"
          >
            {SECTORS.map(s => (
              <option key={s.id} value={s.id}>{locale==='ar' ? s.ar : s.en}</option>
            ))}
          </select>
          {errors.sector_id && <FormError>{errors.sector_id.message}</FormError>}
        </FormField>

        <FormField>
          <FormLabel>{t('project_status')}</FormLabel>
          <select {...register('status')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5">
            {STATUSES.map(s => <option key={s.id} value={s.id}>{locale==='ar' ? s.ar : s.en}</option>)}
          </select>
          {errors.status && <FormError>{errors.status.message}</FormError>}
        </FormField>

        <FormField>
          <FormLabel>{t('project_currency')}</FormLabel>
          <select {...register('base_currency')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5">
            {CURRENCIES.map(c => <option key={c} value={c}>{c} — {t(`currency_${c}` as any)}</option>)}
          </select>
          {errors.base_currency && <FormError>{errors.base_currency.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{t('project_start_date')} *</FormLabel>
          <input type="date" {...register('start_date')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5" />
          {errors.start_date && <FormError>{errors.start_date.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{t('project_end_date')}</FormLabel>
          <input type="date" {...register('end_date')} className="w-full rounded-xl border border-border bg-background px-3 py-2.5" />
          {errors.end_date && <FormError>{errors.end_date.message}</FormError>}
        </FormField>
      </div>

      <FormField>
        <FormLabel>{t('project_description_ar')}</FormLabel>
        <textarea
          {...register('description_ar')}
          rows={3}
          className="w-full rounded-xl border border-border bg-background px-3 py-2.5"
          placeholder={locale==='ar' ? 'وصف موجز للمشروع وأهدافه…' : 'Project description…'}
        />
        {errors.description_ar && <FormError>{errors.description_ar.message}</FormError>}
      </FormField>

      <div className="flex flex-col gap-3 pt-2 min-[360px]:flex-row min-[360px]:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={loading || isSubmitting}>
          {t('action_cancel')}
        </Button>
        <Button type="submit" disabled={loading || isSubmitting}>
          {loading || isSubmitting ? (locale==='ar' ? 'جار الحفظ…' : 'Saving…') : t('action_save')}
        </Button>
      </div>

      {/* Zod error summary — helps debugging */}
      {Object.keys(errors).length > 0 && (
        <div className="rounded-xl bg-warning/5 border border-warning/20 p-3 text-xs text-warning" dir="rtl">
          {Object.entries(errors).map(([k, e]: any) => (
            <div key={k}>• {k}: {e?.message}</div>
          ))}
        </div>
      )}
    </form>
  );
}

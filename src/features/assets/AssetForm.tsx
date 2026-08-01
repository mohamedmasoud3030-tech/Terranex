import { zodResolver } from '@hookform/resolvers/zod';
import { useCallback, useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import { assetSchema, type AssetFormValues } from '../../core/lib/validation';
import { useAutoFxRate } from '../settings/useAutoFxRate';
import type { Asset, AssetStatus, AssetType, Currency, Project } from '../../core/types/domain';
import type { AssetInput } from './storage';

const ASSET_TYPES: AssetType[] = [
  'land',
  'building',
  'farm',
  'equipment',
  'herd',
  'animal_group',
  'crop',
  'other',
];
const ASSET_STATUSES: AssetStatus[] = ['owned', 'leased', 'sold', 'disposed'];
const CURRENCIES: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

const AR_TYPE: Record<AssetType, string> = {
  land: 'أرض',
  building: 'مبنى',
  farm: 'مزرعة',
  equipment: 'معدات',
  herd: 'قطيع',
  animal_group: 'مجموعة حيوانات',
  crop: 'محصول',
  other: 'أصل آخر',
};
const AR_STATUS: Record<AssetStatus, string> = {
  owned: 'مملوك',
  leased: 'مؤجر',
  sold: 'مباع',
  disposed: 'مستبعد',
};

interface AssetFormProps {
  projects: Project[];
  initial?: Partial<Asset>;
  projectLock?: string;
  formId?: string;
  hideActions?: boolean;
  pending?: boolean;
  locale: 'ar' | 'en';
  onSubmit: (input: AssetInput) => void | Promise<void>;
  onCancel: () => void;
}

export function AssetForm({
  projects,
  initial,
  projectLock,
  formId,
  hideActions = false,
  pending = false,
  locale,
  onSubmit,
  onCancel,
}: AssetFormProps) {
  const selectedProjectId = initial?.project_id ?? projectLock ?? projects[0]?.id ?? '';
  const selectedProject = projects.find((project) => project.id === selectedProjectId);
  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<AssetFormValues>({
    // Zod 4 and the current resolver expose slightly different input generics.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    resolver: zodResolver(assetSchema) as any,
    defaultValues: {
      project_id: selectedProjectId,
      sector_id: initial?.sector_id ?? selectedProject?.sector_id ?? 'real-estate',
      type: initial?.type ?? 'land',
      name_ar: initial?.name_ar ?? '',
      name_en: initial?.name_en ?? '',
      acquisition_date: initial?.acquisition_date ?? new Date().toISOString().slice(0, 10),
      acquisition_cost: initial?.acquisition_cost ?? 0,
      acquisition_currency: initial?.acquisition_currency ?? selectedProject?.base_currency ?? 'EGP',
      fx_rate: 1,
      acquisition_cost_egp: initial?.acquisition_cost_egp ?? 0,
      current_value_egp: initial?.current_value_egp,
      status: initial?.status ?? 'owned',
      quantity: initial?.quantity,
      unit: initial?.unit ?? '',
      notes: initial?.notes ?? '',
    },
    mode: 'onBlur',
  });

  const projectId = watch('project_id');
  useEffect(() => {
    const project = projects.find((item) => item.id === projectId);
    if (project) setValue('sector_id', project.sector_id, { shouldValidate: true });
  }, [projectId, projects, setValue]);

  const currency = watch('acquisition_currency');
  useAutoFxRate(currency, useCallback((rate: number) => {
    setValue('fx_rate', rate, { shouldValidate: true });
  }, [setValue]));

  // acquisition_cost_egp follows acquisition_cost × fx_rate automatically,
  // unless the user explicitly opts into manual entry (e.g. a negotiated
  // price that doesn't match the day's rate). This mirrors TransactionForm's
  // fx_rate pattern instead of leaving the two currency fields disconnected.
  const [manualEgpCost, setManualEgpCost] = useState(Boolean(initial?.id));
  const acquisitionCost = watch('acquisition_cost') || 0;
  const fxRate = watch('fx_rate') || 1;
  const effectiveFx = currency === 'EGP' ? 1 : fxRate;
  useEffect(() => {
    if (manualEgpCost) return;
    const computed = Math.round(Number(acquisitionCost) * effectiveFx * 100) / 100;
    setValue('acquisition_cost_egp', computed, { shouldValidate: false });
  }, [acquisitionCost, effectiveFx, manualEgpCost, setValue]);

  const submit = async (values: AssetFormValues) => {
    await onSubmit({
      project_id: values.project_id,
      sector_id: values.sector_id,
      type: values.type,
      name_ar: values.name_ar,
      name_en: values.name_en || '',
      acquisition_date: values.acquisition_date,
      acquisition_cost: values.acquisition_cost,
      acquisition_currency: values.acquisition_currency,
      acquisition_cost_egp: values.acquisition_cost_egp,
      current_value_egp: values.current_value_egp,
      status: values.status,
      quantity: values.quantity,
      unit: values.unit || undefined,
      notes: values.notes || undefined,
    });
  };

  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const inputClass =
    'min-h-11 w-full rounded-xl border border-border bg-background px-3 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary disabled:opacity-60';

  return (
    <form id={formId} onSubmit={handleSubmit(submit)} className="space-y-4" noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor={`${formId ?? 'asset'}-project`}>{label('المشروع', 'Project')} *</FormLabel>
          <select
            id={`${formId ?? 'asset'}-project`}
            {...register('project_id')}
            disabled={Boolean(projectLock)}
            className={inputClass}
          >
            <option value="">{label('اختر المشروع', 'Select project')}</option>
            {projects.map((project) => (
              <option key={project.id} value={project.id}>
                {locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}
              </option>
            ))}
          </select>
          {errors.project_id && <FormError>{errors.project_id.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('القطاع', 'Sector')}</FormLabel>
          <input
            {...register('sector_id')}
            readOnly
            className={`${inputClass} bg-muted`}
            aria-label={label('قطاع المشروع', 'Project sector')}
          />
          {errors.sector_id && <FormError>{errors.sector_id.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{label('اسم الأصل بالعربية', 'Arabic asset name')} *</FormLabel>
          <input {...register('name_ar')} className={inputClass} dir="rtl" />
          {errors.name_ar && <FormError>{errors.name_ar.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('اسم الأصل بالإنجليزية', 'English asset name')}</FormLabel>
          <input {...register('name_en')} className={inputClass} dir="ltr" />
          {errors.name_en && <FormError>{errors.name_en.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel>{label('النوع', 'Type')}</FormLabel>
          <select {...register('type')} className={inputClass}>
            {ASSET_TYPES.map((type) => (
              <option key={type} value={type}>{locale === 'ar' ? AR_TYPE[type] : type.replaceAll('_', ' ')}</option>
            ))}
          </select>
          {errors.type && <FormError>{errors.type.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('الحالة', 'Status')}</FormLabel>
          <select {...register('status')} className={inputClass}>
            {ASSET_STATUSES.map((status) => (
              <option key={status} value={status}>{locale === 'ar' ? AR_STATUS[status] : status}</option>
            ))}
          </select>
          {errors.status && <FormError>{errors.status.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('تاريخ الاقتناء', 'Acquisition date')}</FormLabel>
          <input type="date" {...register('acquisition_date')} className={inputClass} />
          {errors.acquisition_date && <FormError>{errors.acquisition_date.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel>{label('التكلفة الأصلية', 'Original cost')}</FormLabel>
          <input type="number" min="0" step="0.01" {...register('acquisition_cost')} className={inputClass} />
          {errors.acquisition_cost && <FormError>{errors.acquisition_cost.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('العملة', 'Currency')}</FormLabel>
          <select {...register('acquisition_currency')} className={inputClass}>
            {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          {errors.acquisition_currency && <FormError>{errors.acquisition_currency.message}</FormError>}
        </FormField>
        {currency !== 'EGP' && (
          <FormField>
            <FormLabel>{label('سعر الصرف', 'Exchange rate')}</FormLabel>
            <input type="number" min="0" step="0.0001" {...register('fx_rate')} className={inputClass} dir="ltr" />
            {errors.fx_rate && <FormError>{errors.fx_rate.message}</FormError>}
          </FormField>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <div className="flex items-center justify-between">
            <FormLabel>{label('التكلفة بالجنيه', 'Cost in EGP')}</FormLabel>
            {currency !== 'EGP' && (
              <button
                type="button"
                onClick={() => setManualEgpCost((current) => !current)}
                className="text-xs text-primary hover:underline"
              >
                {manualEgpCost
                  ? label('احتساب تلقائي', 'Auto-calculate')
                  : label('تعديل يدوي', 'Edit manually')}
              </button>
            )}
          </div>
          <input
            type="number"
            min="0"
            step="0.01"
            {...register('acquisition_cost_egp')}
            className={inputClass}
            readOnly={currency !== 'EGP' && !manualEgpCost}
            dir="ltr"
          />
          {currency !== 'EGP' && !manualEgpCost && (
            <p className="mt-1 text-xs text-muted-foreground">
              {label('محتسبة تلقائياً من التكلفة × سعر الصرف', 'Auto-calculated from cost × exchange rate')}
            </p>
          )}
          {errors.acquisition_cost_egp && <FormError>{errors.acquisition_cost_egp.message}</FormError>}
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel>{label('القيمة الحالية بالجنيه', 'Current value in EGP')}</FormLabel>
          <input type="number" min="0" step="0.01" {...register('current_value_egp')} className={inputClass} />
          {errors.current_value_egp && <FormError>{errors.current_value_egp.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('الكمية الأساسية', 'Base quantity')}</FormLabel>
          <input type="number" min="0" step="0.01" {...register('quantity')} className={inputClass} />
          {errors.quantity && <FormError>{errors.quantity.message}</FormError>}
        </FormField>
        <FormField>
          <FormLabel>{label('الوحدة', 'Unit')}</FormLabel>
          <input {...register('unit')} className={inputClass} />
          {errors.unit && <FormError>{errors.unit.message}</FormError>}
        </FormField>
      </div>

      <FormField>
        <FormLabel>{label('ملاحظات', 'Notes')}</FormLabel>
        <textarea {...register('notes')} rows={3} className={`${inputClass} py-3`} />
        {errors.notes && <FormError>{errors.notes.message}</FormError>}
      </FormField>

      {!hideActions && (
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onCancel} disabled={pending || isSubmitting}>
            {label('إلغاء', 'Cancel')}
          </Button>
          <Button type="submit" disabled={pending || isSubmitting}>
            {pending || isSubmitting ? label('جار الحفظ…', 'Saving…') : label('حفظ', 'Save')}
          </Button>
        </div>
      )}
    </form>
  );
}

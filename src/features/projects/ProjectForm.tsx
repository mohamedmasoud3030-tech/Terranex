import { useState, type FormEvent } from 'react';
import { useI18n } from '../../core/i18n';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormLabel, SelectInput, TextArea, TextInput } from '../../components/ui/FormControls';
import type { ProjectInput } from './storage';
import type { Project, SectorId, Currency } from '../../core/types/domain';

const SECTORS: { id: SectorId; ar: string; en: string }[] = [
  { id: 'real-estate', ar: 'العقاري', en: 'Real Estate' },
  { id: 'agriculture', ar: 'الزراعي', en: 'Agriculture' },
  { id: 'livestock', ar: 'الحيواني', en: 'Livestock' },
];

const CURRENCIES: Currency[] = ['EGP', 'USD', 'SAR', 'AED', 'EUR', 'GBP'];

const STATUSES: { id: Project['status']; ar: string }[] = [
  { id: 'planning', ar: 'تخطيط' },
  { id: 'active', ar: 'نشط' },
  { id: 'on_hold', ar: 'متوقف مؤقتاً' },
  { id: 'completed', ar: 'مكتمل' },
  { id: 'cancelled', ar: 'ملغى' },
];

interface Props {
  initial?: Partial<Project>;
  onSubmit: (input: ProjectInput) => void;
  onCancel: () => void;
  loading?: boolean;
}

export function ProjectForm({ initial, onSubmit, onCancel, loading }: Props) {
  const { locale } = useI18n();
  const [name_ar, setNameAr] = useState(initial?.name_ar ?? '');
  const [name_en, setNameEn] = useState(initial?.name_en ?? '');
  const [sector_id, setSectorId] = useState<SectorId>(initial?.sector_id ?? 'real-estate');
  const [status, setStatus] = useState<Project['status']>(initial?.status ?? 'planning');
  const [start_date, setStartDate] = useState(initial?.start_date ?? new Date().toISOString().slice(0, 10));
  const [end_date, setEndDate] = useState(initial?.end_date ?? '');
  const [base_currency, setBaseCurrency] = useState<Currency>(initial?.base_currency ?? 'EGP');
  const [description_ar, setDescAr] = useState(initial?.description_ar ?? '');
  const [errors, setErrors] = useState<Record<string, string>>({});

  function validate(): boolean {
    const e: Record<string, string> = {};
    if (!name_ar.trim()) e.name_ar = 'اسم المشروع بالعربي مطلوب';
    if (!start_date) e.start_date = 'تاريخ البدء مطلوب';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!validate()) return;
    onSubmit({ name_ar, name_en, sector_id, status, start_date, end_date: end_date || undefined, base_currency, description_ar, description_en: undefined });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4" noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="project-name-ar">اسم المشروع (عربي) *</FormLabel>
          <TextInput id="project-name-ar" value={name_ar} onChange={(e) => setNameAr(e.target.value)} placeholder="مشروع أرض المرسى" dir="rtl" />
          {errors.name_ar && <FormError>{errors.name_ar}</FormError>}
        </FormField>
        <FormField>
          <FormLabel htmlFor="project-name-en">اسم المشروع (إنجليزي)</FormLabel>
          <TextInput id="project-name-en" value={name_en} onChange={(e) => setNameEn(e.target.value)} placeholder="Al-Marsa Land Project" dir="ltr" />
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel htmlFor="project-sector">القطاع</FormLabel>
          <SelectInput id="project-sector" value={sector_id} onChange={(e) => setSectorId(e.target.value as SectorId)}>
            {SECTORS.map((s) => (
              <option key={s.id} value={s.id}>{locale === 'ar' ? s.ar : s.en}</option>
            ))}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel htmlFor="project-status">الحالة</FormLabel>
          <SelectInput id="project-status" value={status} onChange={(e) => setStatus(e.target.value as Project['status'])}>
            {STATUSES.map((s) => <option key={s.id} value={s.id}>{s.ar}</option>)}
          </SelectInput>
        </FormField>
        <FormField>
          <FormLabel htmlFor="project-currency">العملة الأساسية</FormLabel>
          <SelectInput id="project-currency" value={base_currency} onChange={(e) => setBaseCurrency(e.target.value as Currency)}>
            {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </SelectInput>
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor="project-start-date">تاريخ البدء *</FormLabel>
          <TextInput id="project-start-date" type="date" value={start_date} onChange={(e) => setStartDate(e.target.value)} />
          {errors.start_date && <FormError>{errors.start_date}</FormError>}
        </FormField>
        <FormField>
          <FormLabel htmlFor="project-end-date">تاريخ الانتهاء (اختياري)</FormLabel>
          <TextInput id="project-end-date" type="date" value={end_date} onChange={(e) => setEndDate(e.target.value)} />
        </FormField>
      </div>

      <FormField>
        <FormLabel htmlFor="project-description">وصف المشروع</FormLabel>
        <TextArea id="project-description" rows={3} value={description_ar} onChange={(e) => setDescAr(e.target.value)} placeholder="وصف موجز للمشروع وأهدافه…" />
      </FormField>

      <div className="flex flex-col gap-3 pt-2 min-[360px]:flex-row min-[360px]:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit" disabled={loading}>{loading ? 'جار الحفظ…' : 'حفظ المشروع'}</Button>
      </div>
    </form>
  );
}

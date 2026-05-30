import { useState, type FormEvent } from 'react';
import { useI18n } from '../../core/i18n';
import { Button } from '../../components/ui/Button';
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
    onSubmit({ name_ar, name_en, sector_id, status, start_date, end_date: end_date || undefined, base_currency, description_ar, description_en: undefined, created_at: '', updated_at: '' });
  }

  const labelClass = 'block text-sm font-medium text-foreground mb-1';
  const inputClass = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const errorClass = 'mt-1 text-xs text-danger';

  return (
    <form onSubmit={handleSubmit} className="space-y-4" noValidate>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className={labelClass}>اسم المشروع (عربي) *</label>
          <input className={inputClass} value={name_ar} onChange={(e) => setNameAr(e.target.value)} placeholder="مشروع أرض المرسى" dir="rtl" />
          {errors.name_ar && <p className={errorClass}>{errors.name_ar}</p>}
        </div>
        <div>
          <label className={labelClass}>اسم المشروع (إنجليزي)</label>
          <input className={inputClass} value={name_en} onChange={(e) => setNameEn(e.target.value)} placeholder="Al-Marsa Land Project" dir="ltr" />
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className={labelClass}>القطاع</label>
          <select className={inputClass} value={sector_id} onChange={(e) => setSectorId(e.target.value as SectorId)}>
            {SECTORS.map((s) => (
              <option key={s.id} value={s.id}>{locale === 'ar' ? s.ar : s.en}</option>
            ))}
          </select>
        </div>
        <div>
          <label className={labelClass}>الحالة</label>
          <select className={inputClass} value={status} onChange={(e) => setStatus(e.target.value as Project['status'])}>
            {STATUSES.map((s) => <option key={s.id} value={s.id}>{s.ar}</option>)}
          </select>
        </div>
        <div>
          <label className={labelClass}>العملة الأساسية</label>
          <select className={inputClass} value={base_currency} onChange={(e) => setBaseCurrency(e.target.value as Currency)}>
            {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className={labelClass}>تاريخ البدء *</label>
          <input type="date" className={inputClass} value={start_date} onChange={(e) => setStartDate(e.target.value)} />
          {errors.start_date && <p className={errorClass}>{errors.start_date}</p>}
        </div>
        <div>
          <label className={labelClass}>تاريخ الانتهاء (اختياري)</label>
          <input type="date" className={inputClass} value={end_date} onChange={(e) => setEndDate(e.target.value)} />
        </div>
      </div>

      <div>
        <label className={labelClass}>وصف المشروع</label>
        <textarea className={inputClass} rows={3} value={description_ar} onChange={(e) => setDescAr(e.target.value)} placeholder="وصف موجز للمشروع وأهدافه…" />
      </div>

      <div className="flex gap-3 justify-end pt-2">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit" disabled={loading}>{loading ? 'جار الحفظ…' : 'حفظ المشروع'}</Button>
      </div>
    </form>
  );
}

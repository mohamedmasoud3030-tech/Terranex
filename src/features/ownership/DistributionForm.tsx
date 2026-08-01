import { useMemo, useRef, useState, type FormEvent } from 'react';
import { Card, CardContent } from '../../components/ui/Card';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import { formatEgp } from '../../core/lib/profitability';
import type { Currency, Partner, Project, ProjectPartner } from '../../core/types/domain';
import {
  getOwnershipRowsAsOf as getCachedOwnershipAsOf,
  partnerName,
  previewDistributionAllocations,
  type DistributionPreview,
} from './model';
import { createOwnershipRequestId, type RecordDistributionInput } from './service';

const currencies: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];

export function DistributionForm({
  formId,
  projects,
  partners,
  projectPartners,
  locale,
  defaultProjectId,
  pending = false,
  onSubmit,
}: {
  formId: string;
  projects: Project[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  locale: 'ar' | 'en';
  defaultProjectId?: string;
  pending?: boolean;
  onSubmit: (input: RecordDistributionInput) => Promise<void>;
}) {
  const today = new Date().toISOString().slice(0, 10);
  const [projectId, setProjectId] = useState(defaultProjectId ?? '');
  const project = projects.find((item) => item.id === projectId);
  const [ownershipAsOfDate, setOwnershipAsOfDate] = useState(today);
  const [distributionDate, setDistributionDate] = useState(today);
  const [amount, setAmount] = useState('');
  const [currency, setCurrency] = useState<Currency>(project?.base_currency ?? 'EGP');
  const [fxRate, setFxRate] = useState('1');
  const [notes, setNotes] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(createOwnershipRequestId());
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const inputClass = 'min-h-11 w-full rounded-xl border bg-background px-3 text-sm disabled:opacity-60';
  const partnerById = new Map(partners.map((partner) => [partner.id, partner]));

  const preview = useMemo<DistributionPreview | null>(() => {
    const numericAmount = Number(amount);
    const numericFx = Number(fxRate);
    if (!projectId || !ownershipAsOfDate || !Number.isFinite(numericAmount) || numericAmount <= 0 || !Number.isFinite(numericFx) || numericFx <= 0) return null;
    try {
      return previewDistributionAllocations(
        numericAmount,
        currency,
        numericFx,
        getCachedOwnershipAsOf(projectPartners, projectId, ownershipAsOfDate),
      );
    } catch {
      return null;
    }
  }, [amount, currency, fxRate, ownershipAsOfDate, projectId, projectPartners]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const numericAmount = Number(amount);
    const numericFx = Number(fxRate);
    if (!projectId) {
      setError(label('اختر المشروع.', 'Choose a project.'));
      return;
    }
    if (!distributionDate || !ownershipAsOfDate) {
      setError(label('تاريخ التوزيع وتاريخ الملكية مطلوبان.', 'Distribution and ownership dates are required.'));
      return;
    }
    if (ownershipAsOfDate > distributionDate) {
      setError(label('تاريخ ملكية التوزيع يجب أن يسبق تاريخ التوزيع أو يساويه.', 'Ownership as-of date must be on or before distribution date.'));
      return;
    }
    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      setError(label('مبلغ التوزيع يجب أن يكون أكبر من صفر.', 'Distribution amount must be positive.'));
      return;
    }
    if (!Number.isFinite(numericFx) || numericFx <= 0) {
      setError(label('سعر الصرف يجب أن يكون أكبر من صفر.', 'FX rate must be positive.'));
      return;
    }
    if (!preview || preview.allocations.length === 0) {
      setError(label('لا توجد ملكية فعالة لتكوين تخصيصات التوزيع.', 'There is no effective ownership for allocation preview.'));
      return;
    }
    if (preview.allocation_total !== preview.total_amount) {
      setError(label('مجموع التخصيصات لا يساوي مبلغ التوزيع.', 'Allocation sum does not equal distribution amount.'));
      return;
    }
    if (!confirmed) {
      setError(label('أكد تجميد نسب الملكية والتخصيصات قبل الإنشاء.', 'Confirm the frozen ownership snapshot before creation.'));
      return;
    }

    await onSubmit({
      requestId: requestId.current,
      project_id: projectId,
      distribution_date: distributionDate,
      ownership_as_of_date: ownershipAsOfDate,
      total_amount: numericAmount,
      currency,
      fx_rate: numericFx,
      notes: notes.trim() || undefined,
    });
  }

  return (
    <form id={formId} onSubmit={submit} className="space-y-4" noValidate>
      {error && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</p>}
      <FormField>
        <FormLabel>{label('المشروع', 'Project')}</FormLabel>
        <select aria-label={label('المشروع', 'Project')} value={projectId} onChange={(event) => {
          const nextProject = projects.find((item) => item.id === event.target.value);
          setProjectId(event.target.value);
          if (nextProject) {
            setCurrency(nextProject.base_currency);
            if (nextProject.base_currency === 'EGP') setFxRate('1');
          }
        }} className={inputClass} disabled={pending || Boolean(defaultProjectId)}>
          <option value="">{label('اختر المشروع', 'Choose project')}</option>
          {projects.map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en || item.name_ar}</option>)}
        </select>
      </FormField>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{label('تاريخ ملكية التوزيع', 'Ownership as-of date')}</FormLabel>
          <input aria-label={label('تاريخ ملكية التوزيع', 'Ownership as-of date')} type="date" value={ownershipAsOfDate} onChange={(event) => { setOwnershipAsOfDate(event.target.value); setConfirmed(false); }} className={inputClass} disabled={pending} />
        </FormField>
        <FormField>
          <FormLabel>{label('تاريخ التوزيع', 'Distribution date')}</FormLabel>
          <input aria-label={label('تاريخ التوزيع', 'Distribution date')} type="date" value={distributionDate} onChange={(event) => setDistributionDate(event.target.value)} className={inputClass} disabled={pending} />
        </FormField>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <FormField>
          <FormLabel>{label('إجمالي التوزيع', 'Total distribution')}</FormLabel>
          <input aria-label={label('إجمالي التوزيع', 'Total distribution')} type="number" min="0.01" step="0.01" value={amount} onChange={(event) => { setAmount(event.target.value); setConfirmed(false); }} className={inputClass} disabled={pending} />
        </FormField>
        <FormField>
          <FormLabel>{label('العملة', 'Currency')}</FormLabel>
          <select aria-label={label('العملة', 'Currency')} value={currency} onChange={(event) => {
            const next = event.target.value as Currency;
            setCurrency(next);
            if (next === 'EGP') {
              setFxRate('1');
            }
            setConfirmed(false);
          }} className={inputClass} disabled={pending}>
            {currencies.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{label('سعر الصرف', 'FX rate')}</FormLabel>
          <input aria-label={label('سعر الصرف', 'FX rate')} type="number" min="0.000001" step="0.000001" value={fxRate} onChange={(event) => { setFxRate(event.target.value); setConfirmed(false); }} className={inputClass} disabled={pending || currency === 'EGP'} />
        </FormField>
      </div>

      <FormField>
        <FormLabel>{label('ملاحظات ومراجع', 'Notes and references')}</FormLabel>
        <textarea aria-label={label('ملاحظات ومراجع', 'Notes and references')} value={notes} onChange={(event) => setNotes(event.target.value)} rows={3} className={`${inputClass} py-3`} disabled={pending} />
      </FormField>

      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <h3 className="font-extrabold">{label('معاينة التخصيصات المجمدة', 'Frozen allocation preview')}</h3>
            <p className="text-xs text-muted-foreground">{label('قاعدة التقريب: الفرق يذهب لأكبر حصة', 'Rounding rule: difference goes to largest share')}</p>
          </div>
          {!preview ? (
            <p className="mt-3 text-sm text-muted-foreground">{label('أدخل مشروعًا ومبلغًا وتاريخ ملكية صالحًا لعرض المعاينة.', 'Choose a project, amount, and ownership date to preview allocations.')}</p>
          ) : (
            <div className="mt-3 overflow-x-auto">
              <table className="w-full text-sm">
                <caption className="sr-only">{label('معاينة تخصيصات التوزيع', 'Distribution allocation preview')}</caption>
                <thead>
                  <tr className="border-b text-xs text-muted-foreground">
                    <th className="p-2 text-start">{label('الشريك', 'Partner')}</th>
                    <th className="p-2 text-end">{label('النسبة المجمدة', 'Frozen %')}</th>
                    <th className="p-2 text-end">{label('المحسوب', 'Calculated')}</th>
                    <th className="p-2 text-end">{label('فرق التقريب', 'Rounding')}</th>
                    <th className="p-2 text-end">{label('النهائي', 'Final')}</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.allocations.map((allocation) => (
                    <tr key={allocation.partner_id} className="border-b last:border-b-0">
                      <td className="p-2 font-semibold">{partnerName(partnerById.get(allocation.partner_id), locale)}</td>
                      <td className="p-2 text-end">{allocation.equity_pct_snapshot.toFixed(2)}%</td>
                      <td className="p-2 text-end">{allocation.rounded_amount.toLocaleString()} {preview.currency}</td>
                      <td className="p-2 text-end">{allocation.rounding_adjustment.toFixed(2)}</td>
                      <td className="p-2 text-end font-bold">{allocation.final_amount.toLocaleString()} {preview.currency}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot>
                  <tr className="border-t font-extrabold">
                    <td className="p-2" colSpan={4}>{label('الإجمالي الدقيق', 'Exact total')}</td>
                    <td className="p-2 text-end">{preview.allocation_total.toLocaleString()} {preview.currency}</td>
                  </tr>
                </tfoot>
              </table>
              <p className="mt-2 text-xs text-muted-foreground">
                {label('الإجمالي بالجنيه', 'Total EGP')}: {formatEgp(preview.total_amount_egp)} EGP · {label('فرق التقريب', 'Rounding difference')}: {preview.rounding_difference.toFixed(2)}
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      <label className="flex items-start gap-2 rounded-2xl border border-primary/30 bg-primary/5 p-3 text-sm">
        <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} className="mt-1" disabled={pending || !preview} />
        <span>{label('أؤكد أن التوزيع سيجمّد نسب الملكية والمبالغ في تاريخ الملكية المحدد، وأن أي تصحيح لاحق يكون بعكس أو قيد تصحيحي.', 'I confirm this distribution freezes ownership percentages and amounts at the selected as-of date; later corrections use reversal or corrective entries.')}</span>
      </label>
    </form>
  );
}

import { useMemo, useRef, useState, type FormEvent } from 'react';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import type { EquityChangeEvent, EquityChangeType, Partner, ProjectPartner } from '../../core/types/domain';
import {
  buildOwnershipTimeline,
  getPartnerOwnershipPct,
  normalizeDateOnly,
  partnerName,
  summarizeOwnership,
  validateOwnershipChangeTotal,
} from './model';
import {
  createOwnershipRequestId,
  type ChangeOwnershipInput,
} from './service';

const changeTypes: EquityChangeType[] = ['entry', 'increase', 'decrease', 'exit', 'correction'];

export function OwnershipChangeForm({
  formId,
  projectId,
  partners,
  projectPartners,
  equityChangeEvents,
  locale,
  pending = false,
  onSubmit,
}: {
  formId: string;
  projectId: string;
  partners: Partner[];
  projectPartners: ProjectPartner[];
  equityChangeEvents: EquityChangeEvent[];
  locale: 'ar' | 'en';
  pending?: boolean;
  onSubmit: (input: ChangeOwnershipInput) => Promise<void>;
}) {
  const today = new Date().toISOString().slice(0, 10);
  const [partnerId, setPartnerId] = useState('');
  const [changeType, setChangeType] = useState<EquityChangeType>('entry');
  const [effectiveDate, setEffectiveDate] = useState(today);
  const [newPct, setNewPct] = useState('');
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(createOwnershipRequestId());
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const inputClass = 'min-h-11 w-full rounded-xl border bg-background px-3 text-sm disabled:opacity-60';
  const selectedPartner = partners.find((partner) => partner.id === partnerId);
  const parsedPct = changeType === 'exit' ? 0 : Number(newPct);
  const beforePct = partnerId ? getPartnerOwnershipPct(projectPartners, projectId, partnerId, effectiveDate) : 0;
  const summary = partnerId && Number.isFinite(parsedPct)
    ? validateOwnershipChangeTotal(projectPartners, projectId, partnerId, parsedPct, effectiveDate)
    : summarizeOwnership([]);
  const currentProjectPartners = projectPartners.filter((record) => record.project_id === projectId);
  const timeline = useMemo(
    () => buildOwnershipTimeline(projectId, projectPartners, equityChangeEvents),
    [equityChangeEvents, projectId, projectPartners],
  );
  const partnerLatestDate = partnerId
    ? currentProjectPartners
        .filter((record) => record.partner_id === partnerId)
        .map((record) => normalizeDateOnly(record.effective_from, 'تاريخ بداية الملكية'))
        .sort((first, second) => first.localeCompare(second))
        .at(-1)
    : undefined;

  function changeTypeLabel(type: EquityChangeType) {
    const labels: Record<EquityChangeType, string> = {
      entry: label('دخول / إعادة دخول', 'Entry / re-entry'),
      increase: label('زيادة', 'Increase'),
      decrease: label('تخفيض', 'Decrease'),
      exit: label('خروج', 'Exit'),
      correction: label('تصحيح', 'Correction'),
    };
    return labels[type];
  }

  function validationError(): string | null {
    const rules: Array<() => string | null> = [
      () => partnerId ? null : label('اختر الشريك أولاً.', 'Choose a partner first.'),
      () => reason.trim() ? null : label('سبب تغيير الملكية مطلوب للحفظ في السجل التاريخي.', 'A reason is required for the ownership audit trail.'),
      () => {
        try {
          normalizeDateOnly(effectiveDate, 'تاريخ سريان الملكية');
          return null;
        } catch (err) {
          return err instanceof Error ? err.message : label('تاريخ غير صالح.', 'Invalid date.');
        }
      },
      () => partnerLatestDate && effectiveDate < partnerLatestDate
        ? label(
          `تاريخ السريان يجب ألا يسبق آخر فترة مسجلة لهذا الشريك (${partnerLatestDate}).`,
          `Effective date cannot be before the partner's latest recorded period (${partnerLatestDate}).`,
        )
        : null,
      () => Number.isFinite(parsedPct) && parsedPct >= 0 && parsedPct <= 100
        ? null
        : label('النسبة الجديدة يجب أن تكون بين 0 و100%.', 'The new percentage must be between 0 and 100%.'),
      () => changeType === 'entry' && beforePct > 0
        ? label('الشريك لديه ملكية فعالة بالفعل؛ استخدم زيادة أو تخفيض.', 'The partner already has active ownership; use increase or decrease.')
        : null,
      () => changeType === 'increase' && parsedPct <= beforePct
        ? label('الزيادة يجب أن ترفع النسبة عن الحالة السابقة.', 'An increase must set a higher percentage.')
        : null,
      () => changeType === 'decrease' && parsedPct >= beforePct
        ? label('التخفيض يجب أن يقلل النسبة عن الحالة السابقة.', 'A decrease must set a lower percentage.')
        : null,
      () => changeType === 'exit' && beforePct <= 0
        ? label('لا يمكن إخراج شريك لا يملك حصة فعالة.', 'Cannot exit a partner with no active ownership.')
        : null,
      () => summary.exceeds_full
        ? label('لا يمكن تنفيذ التغيير لأنه سيتجاوز إجمالي الملكية 100%.', 'This change would exceed 100% total ownership.')
        : null,
    ];
    for (const rule of rules) {
      const message = rule();
      if (message) return message;
    }
    return null;
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const message = validationError();
    if (message) {
      setError(message);
      return;
    }

    await onSubmit({
      requestId: requestId.current,
      project_id: projectId,
      partner_id: partnerId,
      effective_date: normalizeDateOnly(effectiveDate, 'تاريخ سريان الملكية'),
      new_pct: parsedPct,
      change_type: changeType,
      reason: reason.trim(),
      notes: notes.trim() || undefined,
    });
  }

  return (
    <form id={formId} onSubmit={submit} className="space-y-4" noValidate aria-describedby={`${formId}-impact`}>
      {error && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</p>}
      <FormField>
        <FormLabel>{label('الشريك', 'Partner')}</FormLabel>
        <select aria-label={label('الشريك', 'Partner')} value={partnerId} onChange={(event) => setPartnerId(event.target.value)} className={inputClass} disabled={pending}>
          <option value="">{label('اختر شريكًا قائمًا', 'Choose an existing partner')}</option>
          {partners.filter((partner) => partner.category === 'equity_partner').map((partner) => (
            <option key={partner.id} value={partner.id}>{partnerName(partner, locale)}</option>
          ))}
        </select>
        <p className="text-xs text-muted-foreground">
          {label('لإضافة اسم جديد، أنشئ الشريك من مساحة الشركاء ثم عد إلى هذا النموذج.', 'To add a new name, create the partner in the Partners workspace and return here.')}
        </p>
      </FormField>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel>{label('نوع التغيير', 'Change type')}</FormLabel>
          <select aria-label={label('نوع التغيير', 'Change type')} value={changeType} onChange={(event) => setChangeType(event.target.value as EquityChangeType)} className={inputClass} disabled={pending}>
            {changeTypes.map((type) => <option key={type} value={type}>{changeTypeLabel(type)}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{label('تاريخ السريان', 'Effective date')}</FormLabel>
          <input aria-label={label('تاريخ السريان', 'Effective date')} type="date" value={effectiveDate} onChange={(event) => setEffectiveDate(event.target.value)} className={inputClass} disabled={pending} />
        </FormField>
      </div>

      <FormField>
        <FormLabel>{label('النسبة الجديدة', 'New percentage')}</FormLabel>
        <input
          aria-label={label('النسبة الجديدة', 'New percentage')}
          type="number"
          min="0"
          max="100"
          step="0.01"
          value={changeType === 'exit' ? '0' : newPct}
          onChange={(event) => setNewPct(event.target.value)}
          className={inputClass}
          disabled={pending || changeType === 'exit'}
        />
        {summary.exceeds_full ? (
          <FormError>{label('إجمالي الملكية بعد التغيير يتجاوز 100%.', 'Total ownership after the change exceeds 100%.')}</FormError>
        ) : (
          <p className="text-xs text-muted-foreground">
            {label('المخصص بعد التغيير', 'Assigned after change')}: {summary.assigned_pct.toFixed(2)}% · {label('غير مخصص', 'Unassigned')}: {summary.remaining_pct.toFixed(2)}%
          </p>
        )}
      </FormField>

      <div id={`${formId}-impact`} className="rounded-2xl border bg-muted/30 p-3 text-sm" aria-live="polite">
        <p className="font-bold">{label('مراجعة الأثر قبل التأكيد', 'Impact review before confirmation')}</p>
        <dl className="mt-2 grid gap-2 sm:grid-cols-3">
          <div><dt className="text-xs text-muted-foreground">{label('قبل', 'Before')}</dt><dd className="font-semibold">{beforePct.toFixed(2)}%</dd></div>
          <div><dt className="text-xs text-muted-foreground">{label('بعد', 'After')}</dt><dd className="font-semibold">{Number.isFinite(parsedPct) ? parsedPct.toFixed(2) : '—'}%</dd></div>
          <div><dt className="text-xs text-muted-foreground">{label('الشريك', 'Partner')}</dt><dd className="font-semibold">{partnerName(selectedPartner, locale)}</dd></div>
        </dl>
        <p className="mt-2 text-xs text-muted-foreground">
          {label('سيُغلق السجل السابق ويُضاف حدث ملكية جديد عبر RPC ذري؛ لا يتم تعديل السجل التاريخي مباشرة.', 'The previous period is closed and a new ownership event is added through the atomic RPC; historical rows are not edited directly.')}
        </p>
      </div>

      <FormField>
        <FormLabel>{label('سبب التغيير', 'Reason')}</FormLabel>
        <textarea aria-label={label('سبب التغيير', 'Reason')} value={reason} onChange={(event) => setReason(event.target.value)} rows={3} className={`${inputClass} py-3`} disabled={pending} />
      </FormField>
      <FormField>
        <FormLabel>{label('ملاحظات اختيارية', 'Optional notes')}</FormLabel>
        <textarea aria-label={label('ملاحظات اختيارية', 'Optional notes')} value={notes} onChange={(event) => setNotes(event.target.value)} rows={3} className={`${inputClass} py-3`} disabled={pending} />
      </FormField>

      {timeline.length > 0 && (
        <div className="rounded-2xl border p-3 text-xs text-muted-foreground">
          {label('آخر تغيير مسجل', 'Latest recorded change')}: {timeline[0].effective_date} · {changeTypeLabel(timeline[0].change_type)} · {timeline[0].previous_pct}% → {timeline[0].new_pct}%
        </div>
      )}
    </form>
  );
}

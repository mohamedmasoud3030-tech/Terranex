import { useMemo, useState, type FormEvent } from 'react';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { FormField, FormLabel } from '../../components/ui/FormControls';
import type {
  Asset,
  Document,
  OperationalEvent,
  OperationalEventType,
  Project,
} from '../../core/types/domain';
import type { OperationalEventInput } from '../events/storage';
import {
  EVENT_DEFINITIONS,
  eventTypesForSector,
  normalizeQuantityDelta,
} from './model';

interface EventFormProps {
  formId: string;
  locale: 'ar' | 'en';
  projects: Project[];
  assets: Asset[];
  documents: Document[];
  context: { projectId?: string; assetId?: string };
  initial?: OperationalEvent;
  serverError?: string | null;
  onSubmit: (input: OperationalEventInput) => void | Promise<void>;
}

export function EventForm({
  formId,
  locale,
  projects,
  assets,
  documents,
  context,
  initial,
  serverError,
  onSubmit,
}: EventFormProps) {
  const initialAsset = assets.find((asset) => asset.id === (initial?.asset_id ?? context.assetId));
  const firstAsset = initialAsset ?? assets.find((asset) =>
    asset.sector_id !== 'real-estate'
    && (!context.projectId || asset.project_id === context.projectId),
  );
  const initialTypes = firstAsset ? eventTypesForSector(firstAsset.sector_id) : [];
  const [assetId, setAssetId] = useState(firstAsset?.id ?? '');
  const [type, setType] = useState<OperationalEventType>(
    initial?.type ?? initialTypes[0] ?? 'birth',
  );
  const [date, setDate] = useState(initial?.event_date ?? new Date().toISOString().slice(0, 10));
  const [quantity, setQuantity] = useState(
    initial?.quantity_delta == null ? '' : String(initial.quantity_delta),
  );
  const [weight, setWeight] = useState(initial?.weight_kg == null ? '' : String(initial.weight_kg));
  const [unitCost, setUnitCost] = useState(
    initial?.unit_cost_egp == null ? '' : String(initial.unit_cost_egp),
  );
  const [totalCost, setTotalCost] = useState(
    initial?.total_cost_egp == null ? '' : String(initial.total_cost_egp),
  );
  const [documentId, setDocumentId] = useState(initial?.document_id ?? '');
  const [description, setDescription] = useState(initial?.description ?? '');
  const [errors, setErrors] = useState<string[]>([]);

  const selectedAsset = assets.find((asset) => asset.id === assetId);
  const allowedTypes = selectedAsset ? eventTypesForSector(selectedAsset.sector_id) : [];
  const definition = EVENT_DEFINITIONS[type];
  const project = projects.find((item) => item.id === selectedAsset?.project_id);
  const availableAssets = useMemo(
    () => assets.filter((asset) =>
      asset.sector_id !== 'real-estate'
      && (!context.projectId || asset.project_id === context.projectId),
    ),
    [assets, context.projectId],
  );
  const availableDocuments = documents.filter((document) =>
    document.project_id === selectedAsset?.project_id
    && (!document.asset_id || document.asset_id === selectedAsset?.id),
  );

  async function submit(event: FormEvent) {
    event.preventDefault();
    const nextErrors: string[] = [];
    if (!selectedAsset) nextErrors.push(locale === 'ar' ? 'اختر أصلًا تشغيليًا.' : 'Choose an operational asset.');
    if (selectedAsset?.sector_id === 'real-estate') {
      nextErrors.push(locale === 'ar' ? 'الأصل العقاري لا يملك نموذج أحداث.' : 'Real-estate assets do not have an event model.');
    }
    if (!date) nextErrors.push(locale === 'ar' ? 'تاريخ الحدث مطلوب.' : 'Event date is required.');
    if (!allowedTypes.includes(type)) nextErrors.push(locale === 'ar' ? 'نوع الحدث لا يطابق قطاع الأصل.' : 'Event type does not match the asset sector.');
    if (definition.weight && (!Number.isFinite(Number(weight)) || Number(weight) <= 0)) {
      nextErrors.push(locale === 'ar' ? 'أدخل وزنًا صالحًا أكبر من صفر.' : 'Enter a valid weight above zero.');
    }
    for (const [key, value] of [['تكلفة الوحدة', unitCost], ['التكلفة الإجمالية', totalCost]] as const) {
      if (value && (!Number.isFinite(Number(value)) || Number(value) < 0)) {
        nextErrors.push(locale === 'ar' ? `${key} غير صالحة.` : 'Cost must be zero or greater.');
      }
    }
    setErrors(nextErrors);
    if (nextErrors.length || !selectedAsset) return;

    await onSubmit({
      asset_id: selectedAsset.id,
      project_id: selectedAsset.project_id,
      type,
      event_date: date,
      quantity_delta: normalizeQuantityDelta(type, quantity === '' ? undefined : Number(quantity)),
      weight_kg: definition.weight ? Number(weight) : undefined,
      unit_cost_egp: unitCost === '' ? undefined : Number(unitCost),
      total_cost_egp: totalCost === '' ? undefined : Number(totalCost),
      description: description.trim() || undefined,
      document_id: documentId || undefined,
      linked_transaction_id: initial?.linked_transaction_id,
    });
  }

  return (
    <form id={formId} onSubmit={(event) => void submit(event)} className="space-y-4" noValidate>
      <FormErrorSummary
        serverError={[...errors, ...(serverError ? [serverError] : [])].join(' ')}
        title={locale === 'ar' ? 'تعذر حفظ الحدث' : 'Event could not be saved'}
      />

      <FormField>
        <FormLabel htmlFor={`${formId}-asset`}>{locale === 'ar' ? 'الأصل التشغيلي' : 'Operational asset'}</FormLabel>
        <select
          id={`${formId}-asset`}
          value={assetId}
          disabled={Boolean(initial) || Boolean(context.assetId)}
          onChange={(event) => {
            const nextAsset = assets.find((asset) => asset.id === event.target.value);
            setAssetId(event.target.value);
            const nextTypes = nextAsset ? eventTypesForSector(nextAsset.sector_id) : [];
            setType(nextTypes[0] ?? 'birth');
          }}
          className="min-h-11 w-full rounded-xl border bg-background px-3"
        >
          <option value="">{locale === 'ar' ? 'اختر الأصل…' : 'Choose asset…'}</option>
          {availableAssets.map((asset) => (
            <option key={asset.id} value={asset.id}>
              {locale === 'ar' ? asset.name_ar : asset.name_en}
            </option>
          ))}
        </select>
        {project && <p className="text-xs text-muted-foreground">{locale === 'ar' ? project.name_ar : project.name_en}</p>}
      </FormField>

      <div className="grid gap-4 sm:grid-cols-2">
        <FormField>
          <FormLabel htmlFor={`${formId}-type`}>{locale === 'ar' ? 'نوع الحدث' : 'Event type'}</FormLabel>
          <select
            id={`${formId}-type`}
            value={type}
            onChange={(event) => setType(event.target.value as OperationalEventType)}
            className="min-h-11 w-full rounded-xl border bg-background px-3"
          >
            {allowedTypes.map((eventType) => (
              <option key={eventType} value={eventType}>
                {EVENT_DEFINITIONS[eventType][locale]}
              </option>
            ))}
          </select>
        </FormField>
        <FormField>
          <FormLabel htmlFor={`${formId}-date`}>{locale === 'ar' ? 'التاريخ' : 'Date'}</FormLabel>
          <input
            id={`${formId}-date`}
            type="date"
            value={date}
            onChange={(event) => setDate(event.target.value)}
            className="min-h-11 w-full rounded-xl border bg-background px-3"
          />
        </FormField>
      </div>

      {definition.quantity !== 'none' && (
        <FormField>
          <FormLabel htmlFor={`${formId}-quantity`}>
            {locale === 'ar' ? 'تغير الكمية' : 'Quantity delta'}
          </FormLabel>
          <input
            id={`${formId}-quantity`}
            type="number"
            value={quantity}
            onChange={(event) => setQuantity(event.target.value)}
            className="min-h-11 w-full rounded-xl border bg-background px-3"
            dir="ltr"
            placeholder={definition.quantity === 'positive' ? '+1' : definition.quantity === 'negative' ? '-1' : '0'}
          />
        </FormField>
      )}

      {definition.weight && (
        <FormField>
          <FormLabel htmlFor={`${formId}-weight`}>{locale === 'ar' ? 'الوزن (كجم)' : 'Weight (kg)'}</FormLabel>
          <input
            id={`${formId}-weight`}
            type="number"
            min="0"
            step="0.01"
            value={weight}
            onChange={(event) => setWeight(event.target.value)}
            className="min-h-11 w-full rounded-xl border bg-background px-3"
            dir="ltr"
          />
        </FormField>
      )}

      {definition.cost && (
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField>
            <FormLabel htmlFor={`${formId}-unit-cost`}>{locale === 'ar' ? 'تكلفة الوحدة EGP' : 'Unit cost EGP'}</FormLabel>
            <input id={`${formId}-unit-cost`} type="number" min="0" step="0.01" value={unitCost} onChange={(event) => setUnitCost(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" />
          </FormField>
          <FormField>
            <FormLabel htmlFor={`${formId}-total-cost`}>{locale === 'ar' ? 'التكلفة الإجمالية EGP' : 'Total cost EGP'}</FormLabel>
            <input id={`${formId}-total-cost`} type="number" min="0" step="0.01" value={totalCost} onChange={(event) => setTotalCost(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3" dir="ltr" />
          </FormField>
        </div>
      )}

      <FormField>
        <FormLabel htmlFor={`${formId}-document`}>{locale === 'ar' ? 'المستند المرتبط' : 'Linked document'}</FormLabel>
        <select id={`${formId}-document`} value={documentId} onChange={(event) => setDocumentId(event.target.value)} className="min-h-11 w-full rounded-xl border bg-background px-3">
          <option value="">{locale === 'ar' ? 'بدون مستند' : 'No document'}</option>
          {availableDocuments.map((document) => (
            <option key={document.id} value={document.id}>{locale === 'ar' ? document.title_ar : document.title_en ?? document.title_ar}</option>
          ))}
        </select>
      </FormField>

      <FormField>
        <FormLabel htmlFor={`${formId}-description`}>{locale === 'ar' ? 'الوصف' : 'Description'}</FormLabel>
        <textarea id={`${formId}-description`} rows={3} value={description} onChange={(event) => setDescription(event.target.value)} className="w-full rounded-xl border bg-background px-3 py-2.5" />
      </FormField>
    </form>
  );
}

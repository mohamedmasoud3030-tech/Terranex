'use client';

import { useActionState, useMemo, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import {
  approvePurchaseOrder,
  approvePurchaseRequest,
  createPurchaseOrder,
  createPurchaseRequest,
  createSupplier,
  submitPurchaseOrder,
  submitPurchaseRequest,
} from '@/features/procurement/actions';
import type {
  ProcurementSupplierRead,
  PurchaseRequestRead,
} from '@/features/procurement/queries';

const initial: ActionState = { error: undefined };
function Key({ prefix }: { prefix: string }) {
  const key = useMemo(() => `${prefix}-${crypto.randomUUID()}`, [prefix]);
  return <input type="hidden" name="idempotencyKey" value={key} />;
}
function Result({ state, pending, label, pendingLabel = 'جارٍ الحفظ…' }: {
  state: ActionState; pending: boolean; label: string; pendingLabel?: string;
}) {
  return (
    <>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? pendingLabel : label}</button>
    </>
  );
}

export function SupplierForm({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  const [state, action, pending] = useActionState(createSupplier, initial);
  return (
    <form action={action} className="form-grid">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <Key prefix="gf25-supplier" />
      <label className="full">اسم المورد<input name="name" required maxLength={160} /></label>
      <label>الرقم الضريبي <span className="muted">(اختياري)</span><input name="taxNumber" maxLength={40} /></label>
      <label>شروط السداد <span className="muted">(اختياري)</span><input name="paymentTerms" maxLength={200} /></label>
      <label className="full">ملاحظات <span className="muted">(اختياري)</span><textarea name="notes" maxLength={2000} /></label>
      <div className="full"><Result state={state} pending={pending} label="تسجيل المورد" /></div>
    </form>
  );
}

function LinesEditor({ name }: { name: string }) {
  const [lines, setLines] = useState<{ itemDescription: string; quantity: string; unit: string; notes: string }[]>([
    { itemDescription: '', quantity: '', unit: '', notes: '' },
  ]);
  const json = useMemo(() => JSON.stringify(lines.filter((l) => l.itemDescription.trim() || l.quantity.trim())), [lines]);
  const update = (index: number, field: keyof typeof lines[number], value: string) => {
    setLines((prev) => prev.map((line, i) => (i === index ? { ...line, [field]: value } : line)));
  };
  const add = () => setLines((prev) => [...prev, { itemDescription: '', quantity: '', unit: '', notes: '' }]);
  const remove = (index: number) => setLines((prev) => prev.length === 1 ? prev : prev.filter((_, i) => i !== index));
  return (
    <div className="full">
      <input type="hidden" name={name} value={json} />
      <div className="table-wrap">
        <table>
          <thead><tr><th>الوصف</th><th>الكمية</th><th>الوحدة</th><th>ملاحظات</th><th></th></tr></thead>
          <tbody>
            {lines.map((line, index) => (
              <tr key={index}>
                <td><input value={line.itemDescription} onChange={(e) => update(index, 'itemDescription', e.target.value)} maxLength={160} /></td>
                <td><input value={line.quantity} onChange={(e) => update(index, 'quantity', e.target.value)} inputMode="decimal" placeholder="0.000000" /></td>
                <td><input value={line.unit} onChange={(e) => update(index, 'unit', e.target.value)} maxLength={20} /></td>
                <td><input value={line.notes} onChange={(e) => update(index, 'notes', e.target.value)} maxLength={1000} /></td>
                <td><button type="button" onClick={() => remove(index)} aria-label="حذف السطر">×</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <button type="button" onClick={add}>إضافة سطر</button>
      <p className="muted">الكمية كمية تشغيلية (حتى 6 خانات عشرية). لا تُسجَّل أرقام مالية في هذه الشريحة.</p>
    </div>
  );
}

export function PurchaseRequestForm({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  const [state, action, pending] = useActionState(createPurchaseRequest, initial);
  return (
    <form action={action} className="form-grid">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <Key prefix="gf25-pr" />
      <label>المرجع الداخلي<input name="internalReference" required maxLength={80} /></label>
      <label className="full">الوصف <span className="muted">(اختياري)</span><textarea name="description" maxLength={2000} /></label>
      <LinesEditor name="linesJson" />
      <div className="full"><Result state={state} pending={pending} label="إنشاء طلب شراء (مسودة)" /></div>
    </form>
  );
}

export function PurchaseOrderForm({
  organizationId, projectId, suppliers, requests,
}: {
  organizationId: string; projectId: string;
  suppliers: ProcurementSupplierRead[]; requests: PurchaseRequestRead[];
}) {
  const [state, action, pending] = useActionState(createPurchaseOrder, initial);
  return (
    <form action={action} className="form-grid">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <Key prefix="gf25-po" />
      <label>المرجع الداخلي<input name="internalReference" required maxLength={80} /></label>
      <label>المورد <span className="muted">(اختياري)</span>
        <select name="supplierId">
          <option value="">بدون مورد</option>
          {suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}
        </select>
      </label>
      <label>من طلب شراء <span className="muted">(اختياري)</span>
        <select name="sourcePurchaseRequestId">
          <option value="">بدون مصدر</option>
          {requests.filter((request) => request.status === 'APPROVED').map((request) =>
            <option key={request.id} value={request.id}>{request.internal_reference}</option>)}
        </select>
      </label>
      <label>تاريخ التسليم المتوقع <span className="muted">(اختياري)</span><input type="date" name="expectedDeliveryDate" /></label>
      <label className="full">الوصف <span className="muted">(اختياري)</span><textarea name="description" maxLength={2000} /></label>
      <LinesEditor name="linesJson" />
      <div className="full"><Result state={state} pending={pending} label="إنشاء أمر شراء (مسودة)" /></div>
    </form>
  );
}

function SubmitAction({ organizationId, projectId, id, actionFn, label }: {
  organizationId: string; projectId: string; id: string;
  actionFn: (_: ActionState, form: FormData) => Promise<ActionState>;
  label: string;
}) {
  const [state, submit, pending] = useActionState(actionFn, initial);
  return (
    <form action={submit} className="inline">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="purchaseRequestId" value={id} />
      <input type="hidden" name="purchaseOrderId" value={id} />
      <Key prefix="gf25-doc-action" />
      <Result state={state} pending={pending} label={label} />
    </form>
  );
}

export function SubmitRequestAction({ organizationId, projectId, requestId }: {
  organizationId: string; projectId: string; requestId: string;
}) {
  return <SubmitAction organizationId={organizationId} projectId={projectId} id={requestId} actionFn={submitPurchaseRequest} label="إرسال للاعتماد" />;
}

export function ApproveRequestAction({ organizationId, projectId, requestId }: {
  organizationId: string; projectId: string; requestId: string;
}) {
  return <SubmitAction organizationId={organizationId} projectId={projectId} id={requestId} actionFn={approvePurchaseRequest} label="اعتماد" />;
}

export function SubmitOrderAction({ organizationId, projectId, orderId }: {
  organizationId: string; projectId: string; orderId: string;
}) {
  return <SubmitAction organizationId={organizationId} projectId={projectId} id={orderId} actionFn={submitPurchaseOrder} label="إرسال للاعتماد" />;
}

export function ApproveOrderAction({ organizationId, projectId, orderId }: {
  organizationId: string; projectId: string; orderId: string;
}) {
  return <SubmitAction organizationId={organizationId} projectId={projectId} id={orderId} actionFn={approvePurchaseOrder} label="اعتماد" />;
}

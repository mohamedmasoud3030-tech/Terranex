'use client';

import { useActionState, useMemo, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import type { Party } from '@/features/funding/queries';
import type { CashAccountPosition } from '@/features/finance/queries';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { formatMinorUnits } from '@/shared/money';
import {
  approvePurchaseOrder,
  approvePurchaseRequest,
  approveSupplierInvoice,
  approveSupplierPayment,
  createPurchaseOrder,
  createPurchaseReceipt,
  createPurchaseRequest,
  createSupplier,
  linkSupplierParty,
  prepareSupplierPayment,
  recordSupplierInvoice,
  submitPurchaseOrder,
  submitPurchaseRequest,
} from '@/features/procurement/actions';
import type {
  ProcurementSupplierRead,
  PurchaseOrderLineRead,
  PurchaseOrderRead,
  PurchaseReceiptInvoiceBasisRead,
  PurchaseRequestRead,
  SupplierInvoiceRead,
} from '@/features/procurement/queries';

const initial: ActionState = { error: undefined };
function CommandKey({ prefix, state, serverNonce }: { prefix: string; state: ActionState; serverNonce: string }) {
  const key = useCommandIdempotencyKey(prefix, state, serverNonce);
  return <input type="hidden" name="idempotencyKey" value={key} />;
}
function Result({ state, pending, label, pendingLabel = 'جارٍ الحفظ…' }: {
  state: ActionState; pending: boolean; label: string; pendingLabel?: string;
}) {
  return <>{state.error && <p className="error" role="alert">{state.error}</p>}<button disabled={pending}>{pending ? pendingLabel : label}</button></>;
}

export function SupplierForm({ organizationId, projectId, serverNonce, parties = [] }: {
  organizationId: string; projectId: string; serverNonce: string; parties?: Party[];
}) {
  const [state, action, pending] = useActionState(createSupplier, initial);
  return (
    <form action={action} className="form-grid">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <CommandKey prefix="gf25-supplier" state={state} serverNonce={serverNonce} />
      <label>الطرف المالي المعتمد<select name="partyId" required><option value="">اختر الطرف</option>{parties.map((party) => <option key={party.id} value={party.id}>{party.legal_name}</option>)}</select></label>
      <label>اسم المورد<input name="name" required maxLength={160} /></label>
      <label>الرقم الضريبي <span className="muted">(اختياري)</span><input name="taxNumber" maxLength={40} /></label>
      <label>شروط السداد <span className="muted">(اختياري)</span><input name="paymentTerms" maxLength={200} /></label>
      <label className="full">ملاحظات <span className="muted">(اختياري)</span><textarea name="notes" maxLength={2000} /></label>
      {parties.length === 0 && <p className="muted full">أنشئ طرفًا معتمدًا في بيانات المشروع/الأطراف قبل تسجيل مورد مالي.</p>}
      <div className="full"><Result state={state} pending={pending} label="تسجيل المورد" /></div>
    </form>
  );
}

export function LinkSupplierPartyForm({ organizationId, projectId, supplierId, parties, serverNonce }: {
  organizationId: string; projectId: string; supplierId: string; parties: Party[]; serverNonce: string;
}) {
  const [state, action, pending] = useActionState(linkSupplierParty, initial);
  return <form action={action} className="inline">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} />
    <input type="hidden" name="supplierId" value={supplierId} /><CommandKey prefix="r4-supplier-party" state={state} serverNonce={serverNonce} />
    <select name="partyId" required><option value="">ربط بطرف مالي…</option>{parties.map((party) => <option key={party.id} value={party.id}>{party.legal_name}</option>)}</select>
    <Result state={state} pending={pending} label="ربط" />
  </form>;
}

type EditableLine = { itemDescription: string; quantity: string; unit: string; unitPrice: string; notes: string };
function LinesEditor({ name, commercial = false, currency = 'EGP' }: { name: string; commercial?: boolean; currency?: string }) {
  const empty = (): EditableLine => ({ itemDescription: '', quantity: '', unit: '', unitPrice: '', notes: '' });
  const [lines, setLines] = useState<EditableLine[]>([empty()]);
  const json = useMemo(() => JSON.stringify(lines.filter((line) => line.itemDescription.trim() || line.quantity.trim())), [lines]);
  const update = (index: number, field: keyof EditableLine, value: string) => setLines((prev) => prev.map((line, i) => i === index ? { ...line, [field]: value } : line));
  return <div className="full">
    <input type="hidden" name={name} value={json} />
    <div className="table-wrap"><table><thead><tr><th>الوصف</th><th>الكمية</th><th>الوحدة</th>{commercial && <th>سعر الوحدة ({currency})</th>}<th>ملاحظات</th><th></th></tr></thead>
      <tbody>{lines.map((line, index) => <tr key={index}>
        <td><input value={line.itemDescription} onChange={(e) => update(index, 'itemDescription', e.target.value)} maxLength={160} /></td>
        <td><input value={line.quantity} onChange={(e) => update(index, 'quantity', e.target.value)} inputMode="decimal" placeholder="0.000000" /></td>
        <td><input value={line.unit} onChange={(e) => update(index, 'unit', e.target.value)} maxLength={20} /></td>
        {commercial && <td><input value={line.unitPrice} onChange={(e) => update(index, 'unitPrice', e.target.value)} inputMode="decimal" placeholder="0.00" /></td>}
        <td><input value={line.notes} onChange={(e) => update(index, 'notes', e.target.value)} maxLength={1000} /></td>
        <td><button type="button" onClick={() => setLines((prev) => prev.length === 1 ? prev : prev.filter((_, i) => i !== index))} aria-label="حذف السطر">×</button></td>
      </tr>)}</tbody></table></div>
    <button type="button" onClick={() => setLines((prev) => [...prev, empty()])}>إضافة سطر</button>
    {commercial && <p className="muted">الإجماليات تُشتق في قاعدة البيانات من الكمية × سعر الوحدة. لا تُرسل قيمة إجمالية من المتصفح.</p>}
  </div>;
}

export function PurchaseRequestForm({ organizationId, projectId, serverNonce }: { organizationId: string; projectId: string; serverNonce: string }) {
  const [state, action, pending] = useActionState(createPurchaseRequest, initial);
  return <form action={action} className="form-grid">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} />
    <CommandKey prefix="r4-pr" state={state} serverNonce={serverNonce} />
    <label>المرجع الداخلي<input name="internalReference" required maxLength={80} /></label>
    <label className="full">الوصف <span className="muted">(اختياري)</span><textarea name="description" maxLength={2000} /></label>
    <LinesEditor name="linesJson" /><div className="full"><Result state={state} pending={pending} label="إنشاء طلب شراء (مسودة)" /></div>
  </form>;
}

export function PurchaseOrderForm({ organizationId, projectId, serverNonce, suppliers, requests, currency = 'EGP' }: {
  organizationId: string; projectId: string; serverNonce: string; suppliers: ProcurementSupplierRead[];
  requests: PurchaseRequestRead[]; currency?: string;
}) {
  const [state, action, pending] = useActionState(createPurchaseOrder, initial);
  const eligible = suppliers.filter((supplier) => supplier.status === 'ACTIVE' && supplier.party_id);
  return <form action={action} className="form-grid">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} />
    <input type="hidden" name="currency" value={currency} /><CommandKey prefix="r4-po" state={state} serverNonce={serverNonce} />
    <label>المرجع الداخلي<input name="internalReference" required maxLength={80} /></label>
    <label>المورد<select name="supplierId" required><option value="">اختر موردًا مرتبطًا ماليًا</option>{eligible.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label>
    <label>من طلب شراء <span className="muted">(اختياري)</span><select name="sourcePurchaseRequestId"><option value="">بدون مصدر</option>{requests.filter((request) => request.status === 'APPROVED').map((request) => <option key={request.id} value={request.id}>{request.internal_reference}</option>)}</select></label>
    <label>تاريخ التسليم المتوقع <span className="muted">(اختياري)</span><input type="date" name="expectedDeliveryDate" /></label>
    <label className="full">مرجع العرض/العقد/الدليل التجاري<input name="commercialReference" required minLength={3} maxLength={200} /></label>
    <label className="full">الوصف <span className="muted">(اختياري)</span><textarea name="description" maxLength={2000} /></label>
    <LinesEditor name="linesJson" commercial currency={currency} />
    <div className="full"><Result state={state} pending={pending} label="إنشاء أمر شراء تجاري (مسودة)" /></div>
  </form>;
}

function DocumentAction({ organizationId, projectId, id, actionFn, label, serverNonce, invoice = false }: {
  organizationId: string; projectId: string; id: string; actionFn: (_: ActionState, form: FormData) => Promise<ActionState>;
  label: string; serverNonce: string; invoice?: boolean;
}) {
  const [state, submit, pending] = useActionState(actionFn, initial);
  return <form action={submit} className="inline">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} />
    <input type="hidden" name="purchaseRequestId" value={id} /><input type="hidden" name="purchaseOrderId" value={id} />
    {invoice && <input type="hidden" name="supplierInvoiceId" value={id} />}
    <CommandKey prefix={invoice ? 'r4-invoice-approve' : 'r4-doc-action'} state={state} serverNonce={serverNonce} />
    <Result state={state} pending={pending} label={label} />
  </form>;
}
export const SubmitRequestAction = (p: { organizationId: string; projectId: string; requestId: string; serverNonce: string }) => <DocumentAction {...p} id={p.requestId} actionFn={submitPurchaseRequest} label="إرسال للاعتماد" />;
export const ApproveRequestAction = (p: { organizationId: string; projectId: string; requestId: string; serverNonce: string }) => <DocumentAction {...p} id={p.requestId} actionFn={approvePurchaseRequest} label="اعتماد" />;
export const SubmitOrderAction = (p: { organizationId: string; projectId: string; orderId: string; serverNonce: string }) => <DocumentAction {...p} id={p.orderId} actionFn={submitPurchaseOrder} label="إرسال للاعتماد" />;
export const ApproveOrderAction = (p: { organizationId: string; projectId: string; orderId: string; serverNonce: string }) => <DocumentAction {...p} id={p.orderId} actionFn={approvePurchaseOrder} label="اعتماد وإنشاء التزام شراء" />;
export const ApproveInvoiceAction = (p: { organizationId: string; projectId: string; invoiceId: string; serverNonce: string }) => <DocumentAction {...p} id={p.invoiceId} actionFn={approveSupplierInvoice} label="اعتماد وإنشاء المستحق" invoice />;

export function ReceiptForm({ organizationId, projectId, order, lines, serverNonce }: {
  organizationId: string; projectId: string; serverNonce: string; order: PurchaseOrderRead; lines: PurchaseOrderLineRead[];
}) {
  const [state, action, pending] = useActionState(createPurchaseReceipt, initial);
  const [quantities, setQuantities] = useState<Record<string, string>>({});
  const json = useMemo(() => JSON.stringify(lines.filter((line) => (quantities[line.id] ?? '').trim()).map((line) => ({ purchaseOrderLineId: line.id, quantityReceived: quantities[line.id] }))), [lines, quantities]);
  return <form action={action} className="form-grid">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} /><input type="hidden" name="purchaseOrderId" value={order.id} />
    <CommandKey prefix="r4-receipt" state={state} serverNonce={serverNonce} />
    <label className="full">مرجع دليل الاستلام<input name="evidenceReference" required maxLength={200} /></label><label className="full">ملاحظات <span className="muted">(اختياري)</span><textarea name="notes" maxLength={2000} /></label>
    <div className="full"><input type="hidden" name="linesJson" value={json} /><div className="table-wrap"><table><thead><tr><th>الصنف</th><th>الوحدة</th><th>الكمية المستلمة</th></tr></thead><tbody>{lines.map((line) => <tr key={line.id}><td>{line.item_description}</td><td>{line.unit}</td><td><input value={quantities[line.id] ?? ''} onChange={(e) => setQuantities((prev) => ({ ...prev, [line.id]: e.target.value }))} inputMode="decimal" /></td></tr>)}</tbody></table></div></div>
    <div className="full"><Result state={state} pending={pending} label="تسجيل الاستلام" /></div>
  </form>;
}

export function SupplierInvoiceForm({ organizationId, projectId, order, basis, serverNonce }: {
  organizationId: string; projectId: string; order: PurchaseOrderRead; basis: PurchaseReceiptInvoiceBasisRead[]; serverNonce: string;
}) {
  const [state, action, pending] = useActionState(recordSupplierInvoice, initial);
  const available = basis.filter((line) => line.purchase_order_id === order.id && Number(line.available_to_invoice_quantity) > 0);
  const [values, setValues] = useState<Record<string, { quantityInvoiced: string; unitPrice: string }>>({});
  const json = useMemo(() => JSON.stringify(available.filter((line) => (values[line.purchase_receipt_line_id]?.quantityInvoiced ?? '').trim()).map((line) => ({
    purchaseReceiptLineId: line.purchase_receipt_line_id,
    quantityInvoiced: values[line.purchase_receipt_line_id]?.quantityInvoiced,
    unitPrice: values[line.purchase_receipt_line_id]?.unitPrice,
  }))), [available, values]);
  if (!order.currency || available.length === 0) return <p className="muted">لا توجد كميات مستلمة متاحة للفوترة على هذا الأمر.</p>;
  return <form action={action} className="form-grid">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} /><input type="hidden" name="purchaseOrderId" value={order.id} /><input type="hidden" name="currency" value={order.currency} />
    <CommandKey prefix="r4-invoice" state={state} serverNonce={serverNonce} />
    <label>رقم/مرجع فاتورة المورد<input name="invoiceReference" required maxLength={120} /></label><label>تاريخ الفاتورة<input type="date" name="invoiceDate" required /></label>
    <label>المعالجة المالية<select name="costTreatment"><option value="EXPENSE">مصروف مشروع</option><option value="CAPITALIZABLE_WIP">أعمال تحت التطوير</option></select></label>
    <label>مرجع دليل الفاتورة<input name="evidenceReference" required minLength={3} maxLength={200} /></label><label className="full">ملاحظات <span className="muted">(اختياري)</span><textarea name="notes" maxLength={2000} /></label>
    <div className="full"><input type="hidden" name="linesJson" value={json} /><div className="table-wrap"><table><thead><tr><th>الصنف / دليل الاستلام</th><th>متاح للفوترة</th><th>كمية الفاتورة</th><th>سعر أمر الشراء</th><th>سعر الفاتورة ({order.currency})</th></tr></thead><tbody>{available.map((line) => <tr key={line.purchase_receipt_line_id}>
      <td>{line.item_description}<br /><span className="muted">{line.receipt_evidence_reference}</span></td><td>{line.available_to_invoice_quantity} {line.unit}</td>
      <td><input inputMode="decimal" value={values[line.purchase_receipt_line_id]?.quantityInvoiced ?? ''} onChange={(e) => setValues((prev) => ({ ...prev, [line.purchase_receipt_line_id]: { quantityInvoiced: e.target.value, unitPrice: prev[line.purchase_receipt_line_id]?.unitPrice ?? '' } }))} /></td>
      <td>{formatMinorUnits(line.unit_price_minor_units, line.currency)}</td>
      <td><input inputMode="decimal" value={values[line.purchase_receipt_line_id]?.unitPrice ?? ''} onChange={(e) => setValues((prev) => ({ ...prev, [line.purchase_receipt_line_id]: { quantityInvoiced: prev[line.purchase_receipt_line_id]?.quantityInvoiced ?? '', unitPrice: e.target.value } }))} /></td>
    </tr>)}</tbody></table></div><p className="muted">لا توجد نسبة سماح مفترضة: السعر يجب أن يطابق الأمر والكمية لا تتجاوز الاستلام.</p></div>
    <div className="full"><Result state={state} pending={pending} label="تسجيل فاتورة المورد للاعتماد" /></div>
  </form>;
}

export function SupplierPaymentForm({ organizationId, projectId, invoice, cashAccounts, serverNonce }: {
  organizationId: string; projectId: string; invoice: SupplierInvoiceRead; cashAccounts: CashAccountPosition[]; serverNonce: string;
}) {
  const [state, action, pending] = useActionState(prepareSupplierPayment, initial);
  if (!invoice.cost_obligation_id) return null;
  const accounts = cashAccounts.filter((account) => account.currency === invoice.currency);
  return <form action={action} className="form-grid compact">
    <input type="hidden" name="organizationId" value={organizationId} /><input type="hidden" name="projectId" value={projectId} /><input type="hidden" name="obligationId" value={invoice.cost_obligation_id} /><input type="hidden" name="currency" value={invoice.currency} />
    <CommandKey prefix="r4-payment" state={state} serverNonce={serverNonce} />
    <label>حساب نقدية المشروع<select name="cashAccountId" required><option value="">اختر الحساب</option>{accounts.map((account) => <option key={account.cash_account_id} value={account.cash_account_id}>{account.name} — {formatMinorUnits(account.balance_minor_units, account.currency)}</option>)}</select></label>
    <label>مبلغ الدفعة ({invoice.currency})<input name="amount" inputMode="decimal" required /></label><label>تاريخ الدفعة<input type="date" name="paymentDate" required /></label>
    <div><Result state={state} pending={pending} label="إعداد مقترح دفع المورد" pendingLabel="جارٍ فحص الرصيد والإعداد…" /></div><p className="muted full">هذا مقترح فقط: تُفحص النقدية الآن، ثم يلزم مالك مختلف لاعتماده وإعادة فحص الرصيد قبل الترحيل. المطابقة البنكية خطوة مستقلة.</p>
  </form>;
}

export function SupplierPaymentApprovalForm({ organizationId, projectId, paymentProposalId, serverNonce }: {
  organizationId: string; projectId: string; paymentProposalId: string; serverNonce: string;
}) {
  const [state, action, pending] = useActionState(approveSupplierPayment, initial);
  return <form action={action} className="stack">
    <input type="hidden" name="organizationId" value={organizationId} />
    <input type="hidden" name="projectId" value={projectId} />
    <input type="hidden" name="paymentProposalId" value={paymentProposalId} />
    <CommandKey prefix="r4-payment-approval" state={state} serverNonce={serverNonce} />
    <Result state={state} pending={pending} label="اعتماد المقترح وترحيل الدفع" pendingLabel="جارٍ إعادة فحص النقدية والترحيل…" />
  </form>;
}

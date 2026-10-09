'use client';

import { useActionState, useSyncExternalStore } from 'react';
import type { ActionState } from '@/features/auth/actions';
import type { CashAccountPosition, ObligationPosition } from '@/features/finance/queries';
import type { Party } from '@/features/funding/queries';
import type { DevelopmentPhase, Parcel, PropertyWorkspace } from '@/features/real-estate/queries';
import {
  approveDisposition,
  classifySellingCost,
  collectReceivable,
  confirmControlTransfer,
  createDisposition,
  recognizeSale,
  reconcileCollection,
} from '@/features/revenue/command-actions';
import type {
  PositiveStatementLine,
  PropertyDisposition,
  SaleCollection,
} from '@/features/revenue/queries';
import { commandIdempotencyKey } from '@/shared/idempotency';
import { useResolvedCommandNonce } from '@/shared/idempotency/use-resolved-command-nonce';
import { formatMinorUnits } from '@/shared/money';

const initial: ActionState = { error: undefined };
const subscribe = () => () => {};
function useCommandReady() {
  return useSyncExternalStore(
    subscribe,
    () => true,
    () => false,
  );
}
function Key({ prefix, state }: { prefix: string; state: ActionState }) {
  const nonce = useResolvedCommandNonce();
  if (!nonce) return null;
  const key = commandIdempotencyKey(prefix, nonce, state.successCount ?? 0);
  return <input type="hidden" name="idempotencyKey" value={key} />;
}
function Context({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  return (
    <>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
    </>
  );
}
function Result({
  state,
  pending,
  label,
  pendingLabel = 'جارٍ الحفظ…',
}: {
  state: ActionState;
  pending: boolean;
  label: string;
  pendingLabel?: string;
}) {
  const ready = useCommandReady();
  return (
    <>
      {state.error && (
        <p className="error" role="alert">
          {state.error}
        </p>
      )}
      <button disabled={pending || !ready}>{pending ? pendingLabel : label}</button>
    </>
  );
}

export function DispositionForm({
  organizationId,
  projectId,
  currency,
  assets,
  parties,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
  assets: PropertyWorkspace[];
  parties: Party[];
}) {
  const [state, action, pending] = useActionState(createDisposition, initial);
  return (
    <form action={action} className="form-grid">
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-disposition" state={state} />
      <input type="hidden" name="currency" value={currency} />
      <label>
        الأصل كاملًا
        <select name="propertyAssetId" required>
          <option value="">اختر الأصل</option>
          {assets.map((a) => (
            <option key={a.property_asset_id} value={a.property_asset_id}>
              {a.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        المشتري
        <select name="buyerPartyId" required>
          <option value="">اختر الطرف</option>
          {parties.map((p) => (
            <option key={p.id} value={p.id}>
              {p.legal_name}
            </option>
          ))}
        </select>
      </label>
      <label>
        مرجع اتفاق التصرف
        <input name="agreementReference" required minLength={2} maxLength={120} />
      </label>
      <label>
        تاريخ الاتفاق
        <input type="date" name="agreementDate" required />
      </label>
      <label>
        المقابل المتفق عليه ({currency})<input name="agreedProceeds" inputMode="decimal" required />
      </label>
      <label>
        تاريخ انتقال السيطرة المتوقع
        <input type="date" name="expectedControlTransferDate" />
      </label>
      <label className="full">
        مرجع دليل الاتفاق
        <input name="agreementEvidenceReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">
        التصرف يشمل الأصل كاملًا فقط. الاتفاق لا يعني انتقال السيطرة، والبيع لا يعني التحصيل.
      </p>
      <div className="full">
        <Result {...{ state, pending }} label="حفظ مسودة التصرف" />
      </div>
    </form>
  );
}

export function ApproveDispositionForm({
  organizationId,
  projectId,
  dispositionId,
}: {
  organizationId: string;
  projectId: string;
  dispositionId: string;
}) {
  const [state, action, pending] = useActionState(approveDisposition, initial);
  return (
    <form action={action}>
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-disposition-approve" state={state} />
      <input type="hidden" name="dispositionId" value={dispositionId} />
      <Result {...{ state, pending }} label="اعتماد اتفاق التصرف" pendingLabel="جارٍ الاعتماد…" />
    </form>
  );
}

export function ControlTransferForm({
  organizationId,
  projectId,
  dispositionId,
}: {
  organizationId: string;
  projectId: string;
  dispositionId: string;
}) {
  const [state, action, pending] = useActionState(confirmControlTransfer, initial);
  return (
    <form action={action} className="form-grid compact">
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-control-transfer" state={state} />
      <input type="hidden" name="dispositionId" value={dispositionId} />
      <label>
        تاريخ انتقال السيطرة
        <input type="date" name="controlTransferDate" required />
      </label>
      <label>
        مرجع دليل الإقفال / التسليم
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <div>
        <Result {...{ state, pending }} label="تأكيد انتقال السيطرة" pendingLabel="جارٍ التأكيد…" />
      </div>
    </form>
  );
}

export function RecognizeSaleForm({
  organizationId,
  projectId,
  dispositionId,
}: {
  organizationId: string;
  projectId: string;
  dispositionId: string;
}) {
  const [state, action, pending] = useActionState(recognizeSale, initial);
  return (
    <form action={action} className="form-grid compact">
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-sale-recognize" state={state} />
      <input type="hidden" name="dispositionId" value={dispositionId} />
      <label>
        تاريخ الاعتراف
        <input type="date" name="recognitionDate" required />
      </label>
      <div>
        <Result
          {...{ state, pending }}
          label="الاعتراف بالبيع والتكلفة الدفترية"
          pendingLabel="جارٍ الترحيل الذري…"
        />
      </div>
      <p className="muted full">
        سيُنشئ قيدًا واحدًا متوازنًا للإيراد والذمم وتكلفة البيع وإلغاء WIP. لا يمكن إدخال التكلفة
        الدفترية يدويًا.
      </p>
    </form>
  );
}

export function CollectionForm({
  organizationId,
  projectId,
  disposition,
  cashAccounts,
}: {
  organizationId: string;
  projectId: string;
  disposition: PropertyDisposition;
  cashAccounts: CashAccountPosition[];
}) {
  const [state, action, pending] = useActionState(collectReceivable, initial);
  if (!disposition.recognition_id) return null;
  return (
    <form action={action} className="form-grid">
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-sale-collection" state={state} />
      <input type="hidden" name="recognitionId" value={disposition.recognition_id} />
      <input type="hidden" name="currency" value={disposition.currency} />
      <label>
        حساب النقدية
        <select name="cashAccountId" required>
          <option value="">اختر الحساب</option>
          {cashAccounts
            .filter((a) => a.currency === disposition.currency)
            .map((a) => (
              <option key={a.cash_account_id} value={a.cash_account_id}>
                {a.name} — {formatMinorUnits(a.balance_minor_units, a.currency)}
              </option>
            ))}
        </select>
      </label>
      <label>
        مبلغ التحصيل ({disposition.currency})<input name="amount" inputMode="decimal" required />
      </label>
      <label>
        تاريخ التحصيل
        <input type="date" name="collectionDate" required />
      </label>
      <label>
        مرجع دليل التحصيل
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">
        يدعم تحصيلات متعددة وجزئية. قاعدة البيانات تمنع تجاوز الذمم المتبقية حتى مع الطلبات
        المتزامنة.
      </p>
      <div className="full">
        <Result {...{ state, pending }} label="ترحيل التحصيل" pendingLabel="جارٍ ترحيل النقدية…" />
      </div>
    </form>
  );
}

export function ReconcileCollectionForm({
  organizationId,
  projectId,
  collection,
  statementLines,
}: {
  organizationId: string;
  projectId: string;
  collection: SaleCollection;
  statementLines: PositiveStatementLine[];
}) {
  const [state, action, pending] = useActionState(reconcileCollection, initial);
  const candidates = statementLines.filter(
    (line) =>
      line.cash_account_id === collection.cash_account_id &&
      line.currency === collection.currency &&
      line.amount_minor_units === collection.amount_minor_units,
  );
  if (collection.is_reconciled) return <span className="status">مطابق بنكيًا</span>;
  if (candidates.length === 0) return <span className="muted">لا يوجد إيداع بنكي موجب مطابق</span>;
  return (
    <form action={action} className="inline-form">
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-collection-reconcile" state={state} />
      <input type="hidden" name="collectionId" value={collection.collection_id} />
      <select name="statementLineId" aria-label="سطر البنك المطابق">
        {candidates.map((line) => (
          <option key={line.line_id} value={line.line_id}>
            {line.transaction_date} · {line.provider_reference || line.description}
          </option>
        ))}
      </select>
      <Result {...{ state, pending }} label="مطابقة" />
    </form>
  );
}

export function SellingCostForm({
  organizationId,
  projectId,
  assets,
  parcels,
  phases,
  obligations,
}: {
  organizationId: string;
  projectId: string;
  assets: PropertyWorkspace[];
  parcels: Parcel[];
  phases: DevelopmentPhase[];
  obligations: ObligationPosition[];
}) {
  const [state, action, pending] = useActionState(classifySellingCost, initial);
  const expenses = obligations.filter((o) => o.cost_treatment === 'EXPENSE' && !o.is_reversed);
  if (expenses.length === 0)
    return <p className="muted">لا توجد التزامات مصروف متاحة لإسنادها كتكلفة بيع.</p>;
  return (
    <form action={action} className="form-grid">
      <Context {...{ organizationId, projectId }} />
      <Key prefix="re-selling-cost" state={state} />
      <label>
        التزام المصروف
        <select name="obligationId">
          {expenses.map((o) => (
            <option key={o.obligation_id} value={o.obligation_id}>
              {o.description} — {formatMinorUnits(o.amount_minor_units, o.currency)}
            </option>
          ))}
        </select>
      </label>
      <label>
        الأصل
        <select name="propertyAssetId">
          {assets.map((a) => (
            <option key={a.property_asset_id} value={a.property_asset_id}>
              {a.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        القطعة (اختياري)
        <select name="parcelId">
          <option value="">كل الأصل</option>
          {parcels.map((p) => (
            <option key={p.id} value={p.id}>
              {p.identifier}
            </option>
          ))}
        </select>
      </label>
      <label>
        المرحلة (اختياري)
        <select name="phaseId">
          <option value="">دون مرحلة</option>
          {phases.map((p) => (
            <option key={p.phase_id} value={p.phase_id}>
              {p.name}
            </option>
          ))}
        </select>
      </label>
      <label className="full">
        مرجع معالجة تكلفة البيع
        <input name="policyReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">
        المبلغ يأتي من قيد المصروف؛ هذا الإسناد لا ينشئ قيدًا أو يضيفه إلى التكلفة الدفترية.
      </p>
      <div className="full">
        <Result {...{ state, pending }} label="إسناد تكلفة البيع" />
      </div>
    </form>
  );
}

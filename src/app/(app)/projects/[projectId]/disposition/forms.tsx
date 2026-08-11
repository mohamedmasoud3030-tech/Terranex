'use client';

import { useActionState } from 'react';
import {
  createDisposition,
  approveDisposition,
  recognizeSale,
  recordCollection,
} from '@/features/real-estate/actions';
import type { PropertyAsset } from '@/features/real-estate/queries';
import type { Party } from '@/features/funding/queries';
import type { FinancialAccount } from '@/features/real-estate/queries';

function generateKey(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

export function DispositionForm({
  organizationId,
  projectId,
  assets,
  parties,
  currency,
}: {
  organizationId: string;
  projectId: string;
  assets: PropertyAsset[];
  parties: Party[];
  currency: string;
}) {
  const [state, action, pending] = useActionState(createDisposition, {});
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={generateKey()} />
      <div className="grid">
        <label>
          العقار
          <select name="propertyAssetId" required>
            <option value="">اختر عقارًا</option>
            {assets.map((a) => (
              <option key={a.id} value={a.id}>
                {a.display_name}
              </option>
            ))}
          </select>
        </label>
        <label>
          المشتري
          <select name="buyerPartyId" required>
            <option value="">اختر طرفًا</option>
            {parties.map((p) => (
              <option key={p.id} value={p.id}>
                {p.legal_name}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="grid">
        <label>
          تاريخ الاتفاق
          <input type="date" name="agreementDate" required />
        </label>
        <label>
          الإيراد المتفق عليه ({currency})
          <input name="agreedProceeds" type="text" inputMode="decimal" required placeholder="0.00" />
        </label>
      </div>
      <div className="grid">
        <label>
          تكاليف البيع ({currency})
          <input name="sellingCosts" type="text" inputMode="decimal" placeholder="0.00" />
        </label>
        <label>
          مرجع العقد
          <input name="contractReference" maxLength={120} />
        </label>
      </div>
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري الإنشاء...' : 'إنشاء التصرف'}
      </button>
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
  const [state, action, pending] = useActionState(approveDisposition, {});
  return (
    <form action={action}>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="dispositionId" value={dispositionId} />
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري الاعتماد...' : 'اعتماد التصرف'}
      </button>
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
  const [state, action, pending] = useActionState(recognizeSale, {});
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="dispositionId" value={dispositionId} />
      <input type="hidden" name="idempotencyKey" value={generateKey()} />
      <label>
        تاريخ نقل السيطرة
        <input type="date" name="controlTransferDate" required />
      </label>
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري الاعتراف...' : 'الاعتراف بالبيع'}
      </button>
    </form>
  );
}

export function CollectionForm({
  organizationId,
  projectId,
  saleReceivableId,
  currency,
  cashAccounts,
  maxAmount,
}: {
  organizationId: string;
  projectId: string;
  saleReceivableId: string;
  currency: string;
  cashAccounts: FinancialAccount[];
  maxAmount: bigint;
}) {
  const [state, action, pending] = useActionState(recordCollection, {});
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="saleReceivableId" value={saleReceivableId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={generateKey()} />
      <div className="grid">
        <label>
          تاريخ التحصيل
          <input type="date" name="collectedOn" required />
        </label>
        <label>
          المبلغ ({currency})
          <input name="collectionAmount" type="text" inputMode="decimal" required placeholder="0.00" />
        </label>
      </div>
      <label>
        الحساب النقدي
        <select name="cashAccountId" required>
          <option value="">اختر حسابًا</option>
          {cashAccounts.map((acc) => (
            <option key={acc.id} value={acc.id}>
              {acc.display_name}
            </option>
          ))}
        </select>
      </label>
      <p className="muted">الحد الأقصى: {maxAmount.toString()}</p>
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري التسجيل...' : 'تسجيل التحصيل'}
      </button>
    </form>
  );
}

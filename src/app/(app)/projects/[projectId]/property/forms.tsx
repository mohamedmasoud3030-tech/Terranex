'use client';

import { useActionState } from 'react';
import {
  createPropertyAsset,
  recordPropertyCostItem,
  recordPropertyValuation,
} from '@/features/real-estate/actions';

function generateKey(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

export function PropertyAssetForm({
  organizationId,
  projectId,
  currency,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
}) {
  const [state, action, pending] = useActionState(createPropertyAsset, {});
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={generateKey()} />
      <div className="grid">
        <label>
          اسم العقار
          <input name="displayName" required minLength={2} maxLength={160} />
        </label>
        <label>
          الاستراتيجية
          <select name="strategy" defaultValue="DEVELOP_SELL">
            <option value="ACQUIRE_HOLD">شراء واحتفاظ</option>
            <option value="DEVELOP_SELL">تطوير وبيع</option>
            <option value="LAND_TRADE">تجارة أراضٍ</option>
          </select>
        </label>
      </div>
      <div className="grid">
        <label>
          الولاية القضائية
          <input name="jurisdiction" maxLength={80} />
        </label>
        <label>
          حالة السند
          <select name="titleStatus">
            <option value="">غير محدد</option>
            <option value="PENDING">قيد الإجراء</option>
            <option value="CLEAR">سليم</option>
            <option value="DISPUTED">متنازع عليه</option>
            <option value="LEASED">مؤجر</option>
          </select>
        </label>
      </div>
      <div className="grid">
        <label>
          تاريخ الاكتساب
          <input type="date" name="acquiredOn" />
        </label>
        <label>
          تكلفة الاكتساب ({currency})
          <input name="acquisitionCost" type="text" inputMode="decimal" placeholder="0.00" />
        </label>
      </div>
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري الحفظ...' : 'حفظ العقار'}
      </button>
    </form>
  );
}

export function PropertyCostForm({
  organizationId,
  projectId,
  propertyAssetId,
  currency,
}: {
  organizationId: string;
  projectId: string;
  propertyAssetId: string;
  currency: string;
}) {
  const [state, action, pending] = useActionState(recordPropertyCostItem, {});
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="propertyAssetId" value={propertyAssetId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={generateKey()} />
      <div className="grid">
        <label>
          فئة التكلفة
          <input name="costCategory" required minLength={2} maxLength={80} />
        </label>
        <label>
          المبلغ ({currency})
          <input name="costAmount" type="text" inputMode="decimal" required placeholder="0.00" />
        </label>
      </div>
      <div className="grid">
        <label>
          التاريخ
          <input type="date" name="occurredOn" required />
        </label>
        <label>
          <input type="checkbox" name="isCapitalizable" value="true" defaultChecked />
          تكلفة رأسمالية (تدخل في التكلفة الدفترية)
        </label>
      </div>
      <label>
        الوصف
        <textarea name="description" maxLength={500} />
      </label>
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري التسجيل...' : 'تسجيل التكلفة'}
      </button>
    </form>
  );
}

export function PropertyValuationForm({
  organizationId,
  projectId,
  propertyAssetId,
  currency,
}: {
  organizationId: string;
  projectId: string;
  propertyAssetId: string;
  currency: string;
}) {
  const [state, action, pending] = useActionState(recordPropertyValuation, {});
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="propertyAssetId" value={propertyAssetId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={generateKey()} />
      <div className="grid">
        <label>
          تاريخ التقييم
          <input type="date" name="effectiveDate" required />
        </label>
        <label>
          القيمة ({currency})
          <input name="valuationAmount" type="text" inputMode="decimal" required placeholder="0.00" />
        </label>
      </div>
      <div className="grid">
        <label>
          المصدر/المقيّم
          <input name="valuerSource" required minLength={2} maxLength={160} />
        </label>
        <label>
          الطريقة
          <input name="method" required minLength={2} maxLength={80} placeholder="مقارنة سوقية، دخل، تكلفة" />
        </label>
      </div>
      <div className="grid">
        <label>
          مستوى الثقة
          <select name="confidence">
            <option value="">غير محدد</option>
            <option value="HIGH">عالية</option>
            <option value="MEDIUM">متوسطة</option>
            <option value="LOW">منخفضة</option>
          </select>
        </label>
      </div>
      <label>
        الافتراضات
        <textarea name="assumptions" maxLength={2000} />
      </label>
      {state.error && <p className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? 'جاري التسجيل...' : 'تسجيل التقييم'}
      </button>
    </form>
  );
}

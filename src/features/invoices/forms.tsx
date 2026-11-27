'use client';

import { useActionState, useMemo } from 'react';
import { collectCustomerInvoice, createCustomerParty, issueCustomerInvoice } from './actions';
import { PARTY_TYPE_LABEL } from './labels';
import { commandIdempotencyKey } from '@/shared/idempotency';

type ProjectOption = { id: string; name: string; reporting_currency: string };
type PartyOption = { id: string; legal_name: string };
type CashAccountOption = { cash_account_id: string; project_id: string; name: string; currency: string };

export function IssueCustomerInvoiceForm({
  organizationId,
  projects,
  parties,
  commandNonce,
}: {
  organizationId: string;
  projects: ProjectOption[];
  parties: PartyOption[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(issueCustomerInvoice, { successCount: 0 });
  const idempotencyKey = useMemo(
    () => commandIdempotencyKey('customer-invoice-issue', commandNonce, state.successCount ?? 0),
    [commandNonce, state.successCount],
  );
  const today = useMemo(() => new Date().toISOString().slice(0, 10), []);

  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        المشروع
        <ProjectSelect projects={projects} />
      </label>
      <label>
        العميل
        <select name="customerPartyId" required defaultValue="">
          <option value="" disabled>اختر العميل</option>
          {parties.map((party) => (
            <option key={party.id} value={party.id}>{party.legal_name}</option>
          ))}
        </select>
      </label>
      <label>
        رقم الفاتورة
        <input name="invoiceReference" required maxLength={120} placeholder="INV-0001" />
      </label>
      <label>
        المبلغ
        <input name="amount" required inputMode="decimal" placeholder="0.00" />
      </label>
      <label>
        تاريخ الفاتورة
        <input type="date" name="invoiceDate" required defaultValue={today} max={today} />
      </label>
      <label>
        مرجع الدليل
        <input name="evidenceReference" required minLength={3} maxLength={200} placeholder="رقم السند أو مرجع العقد" />
      </label>
      <label>
        الوصف <span className="muted">(اختياري)</span>
        <input name="description" maxLength={1000} />
      </label>
      <small className="muted">تُصدر الفاتورة بعملة تقارير المشروع، وتُقيد كإيراد مبيعات وذمة مدينة على العميل. لا يمكن تعديلها بعد الإصدار.</small>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <div>
        <button disabled={pending}>{pending ? 'جارٍ الإصدار…' : 'إصدار الفاتورة'}</button>
      </div>
    </form>
  );
}

function ProjectSelect({ projects }: { projects: ProjectOption[] }) {
  // The invoice is always denominated in the project reporting currency; the
  // hidden currency field tracks the selected project.
  return (
    <>
      <select
        name="projectId"
        required
        defaultValue=""
        onChange={(event) => {
          const form = event.currentTarget.form;
          const currencyInput = form?.querySelector<HTMLInputElement>('input[name="currency"]');
          const selected = projects.find((p) => p.id === event.currentTarget.value);
          if (currencyInput && selected) currencyInput.value = selected.reporting_currency;
        }}
      >
        <option value="" disabled>اختر المشروع</option>
        {projects.map((project) => (
          <option key={project.id} value={project.id}>
            {project.name} ({project.reporting_currency})
          </option>
        ))}
      </select>
      <input type="hidden" name="currency" value={projects.length === 1 ? projects[0].reporting_currency : ''} />
    </>
  );
}

export function CollectCustomerInvoiceForm({
  organizationId,
  invoiceId,
  projectId,
  currency,
  outstandingMajorHint,
  cashAccounts,
  commandNonce,
}: {
  organizationId: string;
  invoiceId: string;
  projectId: string;
  currency: string;
  outstandingMajorHint: string;
  cashAccounts: CashAccountOption[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(collectCustomerInvoice, { successCount: 0 });
  const idempotencyKey = useMemo(
    () => commandIdempotencyKey(`customer-invoice-collect-${invoiceId}`, commandNonce, state.successCount ?? 0),
    [commandNonce, invoiceId, state.successCount],
  );
  const today = useMemo(() => new Date().toISOString().slice(0, 10), []);
  const projectAccounts = cashAccounts.filter((a) => a.project_id === projectId && a.currency === currency);

  if (projectAccounts.length === 0) {
    return <small className="muted">أضف حسابًا نقديًا لهذا المشروع من صفحة النقدية لتسجيل التحصيل.</small>;
  }

  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="invoiceId" value={invoiceId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        حساب التحصيل
        <select name="cashAccountId" required defaultValue={projectAccounts.length === 1 ? projectAccounts[0].cash_account_id : ''}>
          {projectAccounts.length !== 1 && <option value="" disabled>اختر الحساب</option>}
          {projectAccounts.map((account) => (
            <option key={account.cash_account_id} value={account.cash_account_id}>{account.name}</option>
          ))}
        </select>
      </label>
      <label>
        المبلغ <span className="muted">(المتبقي {outstandingMajorHint} {currency})</span>
        <input name="amount" required inputMode="decimal" placeholder={outstandingMajorHint} />
      </label>
      <label>
        تاريخ التحصيل
        <input type="date" name="collectionDate" required defaultValue={today} max={today} />
      </label>
      <label>
        مرجع الدليل
        <input name="evidenceReference" required minLength={3} maxLength={200} placeholder="رقم الإيصال" />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <div>
        <button disabled={pending}>{pending ? 'جارٍ الترحيل…' : 'تسجيل تحصيل'}</button>
      </div>
    </form>
  );
}

export function CreateCustomerPartyForm({
  organizationId,
  commandNonce,
}: {
  organizationId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(createCustomerParty, { successCount: 0 });
  const key = useMemo(
    () => commandIdempotencyKey('customer-party', commandNonce, state.successCount ?? 0),
    [commandNonce, state.successCount],
  );
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={key} />
      <label>
        اسم العميل
        <input name="legalName" required minLength={2} maxLength={160} />
      </label>
      <label>
        النوع
        <select name="partyType" defaultValue="ORGANIZATION">
          {(Object.keys(PARTY_TYPE_LABEL) as Array<'PERSON' | 'ORGANIZATION'>).map((type) => (
            <option key={type} value={type}>{PARTY_TYPE_LABEL[type]}</option>
          ))}
        </select>
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <div>
        <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'إضافة عميل'}</button>
      </div>
    </form>
  );
}

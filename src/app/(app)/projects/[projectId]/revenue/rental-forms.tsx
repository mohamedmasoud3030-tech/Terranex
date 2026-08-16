'use client';

import { useActionState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { collectRentalReceivable, recognizeRentalIncome, reconcileRentalCollection } from '@/features/revenue/actions';
import type { CashAccountPosition } from '@/features/finance/queries';
import type { Party } from '@/features/funding/queries';
import type { PropertyWorkspace } from '@/features/real-estate/queries';
import type { PositiveStatementLine, RentalCollection, RentalIncome } from '@/features/revenue/queries';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { formatMinorUnits } from '@/shared/money';

const initial: ActionState = {};
type Context = { organizationId:string; projectId:string; commandNonce:string };
function Hidden({organizationId,projectId,keyValue}:{organizationId:string;projectId:string;keyValue:string}) { return <><input type="hidden" name="organizationId" value={organizationId}/><input type="hidden" name="projectId" value={projectId}/><input type="hidden" name="idempotencyKey" value={keyValue}/></>; }
function Result({state,pending,label}:{state:ActionState;pending:boolean;label:string}) { return <>{state.error?<p className="error" role="alert">{state.error}</p>:null}{!state.error&&(state.successCount??0)>0?<p className="status" role="status">تم ترحيل العملية بنجاح.</p>:null}<button disabled={pending}>{pending?'جارٍ الترحيل…':label}</button></>; }

export function RentalRecognitionForm(props: Context & { currency:string; assets:PropertyWorkspace[]; parties:Party[] }) {
  const [state,action,pending]=useActionState(recognizeRentalIncome,initial);
  const key=useCommandIdempotencyKey('r5-rent-recognize',state,props.commandNonce);
  const held=props.assets.filter(a=>a.operational_state==='HELD');
  return <form action={action} className="form-grid"><Hidden {...props} keyValue={key}/><input type="hidden" name="currency" value={props.currency}/>
    <label>الأصل المحتفظ به<select name="propertyAssetId" required defaultValue=""><option value="" disabled>اختر الأصل</option>{held.map(a=><option key={a.property_asset_id} value={a.property_asset_id}>{a.name}</option>)}</select></label>
    <label>المستأجر / الطرف<select name="tenantPartyId" required defaultValue=""><option value="" disabled>اختر الطرف</option>{props.parties.map(p=><option key={p.id} value={p.id}>{p.legal_name}</option>)}</select></label>
    <label>مرجع عقد الإيجار<input name="contractReference" required minLength={2} maxLength={160}/></label><label>المبلغ ({props.currency})<input name="amount" inputMode="decimal" required/></label>
    <label>بداية الفترة<input type="date" name="rentalPeriodStart" required/></label><label>نهاية الفترة<input type="date" name="rentalPeriodEnd" required/></label><label>تاريخ الاعتراف<input type="date" name="recognitionDate" required/></label><label>مرجع الدليل<input name="evidenceReference" required minLength={3} maxLength={200}/></label>
    <p className="muted full">ينشئ الاعتراف إيرادًا وذمة مدينة متوازنين. لا يعني التحصيل أو المطابقة البنكية.</p><div className="full"><Result {...{state,pending}} label="الاعتراف بإيراد الإيجار"/></div>
  </form>;
}

export function RentalCollectionForm(props: Context & { recognition:RentalIncome; cashAccounts:CashAccountPosition[] }) {
  const [state,action,pending]=useActionState(collectRentalReceivable,initial);
  const key=useCommandIdempotencyKey(`r5-rent-collect-${props.recognition.recognition_id}`,state,props.commandNonce);
  return <form action={action} className="form-grid compact"><Hidden {...props} keyValue={key}/><input type="hidden" name="recognitionId" value={props.recognition.recognition_id}/><input type="hidden" name="currency" value={props.recognition.currency}/>
    <label>الحساب النقدي<select name="cashAccountId" required>{props.cashAccounts.filter(a=>a.currency===props.recognition.currency).map(a=><option key={a.cash_account_id} value={a.cash_account_id}>{a.name} · {formatMinorUnits(a.balance_minor_units,a.currency)}</option>)}</select></label><label>المبلغ ({props.recognition.currency})<input name="amount" inputMode="decimal" required/></label><label>تاريخ التحصيل<input type="date" name="collectionDate" required/></label><label>مرجع الدليل<input name="evidenceReference" required minLength={3} maxLength={200}/></label><div><Result {...{state,pending}} label="ترحيل التحصيل"/></div>
  </form>;
}

export function RentalReconciliationForm(props: Context & { collection:RentalCollection; statementLines:PositiveStatementLine[] }) {
  const [state,action,pending]=useActionState(reconcileRentalCollection,initial);
  const key=useCommandIdempotencyKey(`r5-rent-reconcile-${props.collection.collection_id}`,state,props.commandNonce);
  const candidates=props.statementLines.filter(l=>l.cash_account_id===props.collection.cash_account_id&&l.currency===props.collection.currency&&l.amount_minor_units===props.collection.amount_minor_units);
  if(props.collection.is_reconciled)return <span className="status">مطابق بنكيًا</span>;
  if(!candidates.length)return <span className="muted">لا يوجد سطر إيداع مطابق غير مستخدم</span>;
  return <form action={action} className="inline-form"><Hidden {...props} keyValue={key}/><input type="hidden" name="collectionId" value={props.collection.collection_id}/><select name="statementLineId" aria-label="سطر البنك المطابق">{candidates.map(l=><option key={l.line_id} value={l.line_id}>{l.transaction_date} · {l.provider_reference??l.description}</option>)}</select><Result {...{state,pending}} label="مطابقة"/></form>;
}

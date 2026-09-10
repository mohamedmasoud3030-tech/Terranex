import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership, getCashAccountPositions, getPaymentProposals } from '@/features/finance/queries';
import { getParties } from '@/features/funding/queries';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import {
  getProcurementCommitments,
  getProcurementEvidence,
  getPurchaseOrderLines,
  getPurchaseOrderLinesReceiving,
  getPurchaseOrders,
  getPurchaseReceiptInvoiceBasis,
  getPurchaseReceiptLines,
  getPurchaseReceipts,
  getPurchaseRequestLines,
  getPurchaseRequests,
  getSupplierInvoiceLines,
  getSupplierInvoices,
  getSuppliers,
} from '@/features/procurement/queries';
import {
  formatDate, formatDocumentState, formatPaymentState, formatReconciliationState, formatSupplierStatus,
} from '@/features/procurement/labels';
import { formatMinorUnits } from '@/shared/money';
import { newCommandNonce } from '@/shared/idempotency';
import {
  ApproveInvoiceAction, ApproveOrderAction, ApproveRequestAction, LinkSupplierPartyForm,
  ProcurementEvidenceForm, PurchaseOrderForm, PurchaseRequestForm, ReceiptForm, SubmitOrderAction, SubmitRequestAction,
  SupplierForm, SupplierInvoiceForm, SupplierPaymentApprovalForm, SupplierPaymentForm,
} from './forms';

export const dynamic = 'force-dynamic';

export default async function ProcurementPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;
  const [membership, parties, cashAccounts, paymentProposals, suppliers, requests, requestLines, orders, orderLines,
    receipts, receiptLines, receiving, invoiceBasis, invoices, invoiceLines, commitments, evidence] = await Promise.all([
    getCurrentMembership(organizationId), getParties(organizationId), getCashAccountPositions(projectId),
    getPaymentProposals(projectId), getSuppliers(organizationId), getPurchaseRequests(projectId),
    getPurchaseRequestLines(projectId), getPurchaseOrders(projectId), getPurchaseOrderLines(projectId),
    getPurchaseReceipts(projectId), getPurchaseReceiptLines(projectId), getPurchaseOrderLinesReceiving(projectId),
    getPurchaseReceiptInvoiceBasis(projectId), getSupplierInvoices(projectId),
    getSupplierInvoiceLines(projectId), getProcurementCommitments(projectId), getProcurementEvidence(projectId),
  ]);
  if (!membership) return <ForbiddenCard projectId={projectId} message="لا تملك عضوية نشطة في منظمة هذا المشروع." />;
  const canApprove = membership.role === 'OWNER';

  const group = <T,>(rows: T[], key: (row: T) => string) => {
    const map = new Map<string, T[]>();
    rows.forEach((row) => map.set(key(row), [...(map.get(key(row)) ?? []), row]));
    return map;
  };
  const requestLineMap = group(requestLines, (line) => line.purchase_request_id);
  const orderLineMap = group(orderLines, (line) => line.purchase_order_id);
  const receiptLineMap = group(receiptLines, (line) => line.purchase_receipt_id);
  const invoiceLineMap = group(invoiceLines, (line) => line.supplier_invoice_id);
  const receivingMap = new Map(receiving.map((line) => [line.purchase_order_line_id, line]));
  const commitmentMap = new Map(commitments.map((commitment) => [commitment.purchase_order_id, commitment]));
  const orderEvidence = group(evidence.filter((item) => item.purchase_order_id), (item) => item.purchase_order_id!);
  const receiptEvidence = group(evidence.filter((item) => item.purchase_receipt_id), (item) => item.purchase_receipt_id!);
  const invoiceEvidence = group(evidence.filter((item) => item.supplier_invoice_id), (item) => item.supplier_invoice_id!);
  const evidenceList = (items: typeof evidence) => items.length === 0
    ? <p className="error">لا يوجد ملف دليل فعلي مسجل.</p>
    : <ul>{items.map((item) => <li key={item.evidence_link_id}>{item.download_url
      ? <a href={item.download_url} target="_blank" rel="noreferrer">{item.title} — الإصدار {item.version_number}</a>
      : <span>{item.title} — الإصدار {item.version_number}</span>} <small className="muted">{item.original_filename} · SHA-256 {item.sha256.slice(0, 12)}…</small></li>)}</ul>;

  return <section className="stack">
    <WorkspaceChrome projectId={projectId} active="procurement" title="المشتريات والدورة المالية"
      subtitle="طلب شراء ← أمر تجاري ← استلام ← فاتورة مورد ← مستحق ← دفع ← مطابقة بنكية"
      internalReference={project.internal_reference} sector={project.sector} />

    <section className="card stack"><div className="section-heading"><div><h2>الموردون والأطراف المالية</h2><p className="muted">ملف المورد تشغيلي؛ الهوية المالية هي Party المشتركة مع Finance Core.</p></div><span className="status">{suppliers.length} مورد</span></div>
      {suppliers.length === 0 ? <p className="muted">لا يوجد موردون بعد.</p> : <div className="table-wrap"><table className="table-stackable"><thead><tr><th>المورد</th><th>الطرف المالي</th><th>شروط السداد</th><th>الحالة</th></tr></thead><tbody>{suppliers.map((supplier) => <tr key={supplier.id}><td data-label="المورد">{supplier.name}</td><td data-label="الطرف المالي">{supplier.party_name ?? (canApprove ? <LinkSupplierPartyForm organizationId={organizationId} projectId={projectId} supplierId={supplier.id} parties={parties} serverNonce={newCommandNonce()} /> : 'غير مربوط')}</td><td data-label="شروط السداد">{supplier.payment_terms ?? '—'}</td><td data-label="الحالة">{formatSupplierStatus(supplier.status)}</td></tr>)}</tbody></table></div>}
      <details><summary>تسجيل مورد جديد</summary><SupplierForm organizationId={organizationId} projectId={projectId} parties={parties} serverNonce={newCommandNonce()} /></details>
    </section>

    <section className="card stack"><div className="section-heading"><div><h2>طلبات الشراء</h2><p className="muted">احتياج تشغيلي مستقل عن الالتزام والدفع.</p></div><span className="status">{requests.length} طلب</span></div>
      {requests.map((request) => <article className="card stack" key={request.id}><header className="topline"><h3>{request.internal_reference}</h3><span className="status">{formatDocumentState(request.status)}</span></header>
        <div className="table-wrap"><table className="table-stackable"><thead><tr><th>الصنف</th><th>الكمية</th><th>الوحدة</th></tr></thead><tbody>{(requestLineMap.get(request.id) ?? []).map((line) => <tr key={line.id}><td data-label="الصنف">{line.item_description}</td><td data-label="الكمية">{line.quantity}</td><td data-label="الوحدة">{line.unit}</td></tr>)}</tbody></table></div>
        {request.status === 'DRAFT' && <SubmitRequestAction organizationId={organizationId} projectId={projectId} requestId={request.id} serverNonce={newCommandNonce()} />}
        {request.status === 'SUBMITTED' && canApprove && <ApproveRequestAction organizationId={organizationId} projectId={projectId} requestId={request.id} serverNonce={newCommandNonce()} />}
      </article>)}
      <details><summary>إنشاء طلب شراء</summary><PurchaseRequestForm organizationId={organizationId} projectId={projectId} serverNonce={newCommandNonce()} /></details>
    </section>

    <section className="card stack"><div className="section-heading"><div><h2>أوامر الشراء التجارية والالتزامات</h2><p className="muted">الاعتماد ينشئ التزام شراء غير مرحّل؛ لا يسجل مصروفًا أو مستحقًا أو نقدية.</p></div><span className="status">{orders.length} أمر</span></div>
      {orders.map((order) => {
        const lines = orderLineMap.get(order.id) ?? [];
        const commitment = commitmentMap.get(order.id);
        return <article className="card stack" key={order.id}><header className="topline"><div><h3>{order.internal_reference}</h3><p className="muted">{order.supplier_name ?? '—'} · {order.commercial_reference ?? 'أمر قديم دون شروط مالية'} · {formatDate(order.expected_delivery_date)}</p></div><span className="status">{formatDocumentState(order.status)}</span></header>
          {order.currency && <div className="metrics-grid"><article><span className="muted">المطلوب تجاريًا</span><strong>{formatMinorUnits(order.commercial_total_minor_units, order.currency)}</strong></article><article><span className="muted">المفوتر المعتمد</span><strong>{formatMinorUnits(commitment?.invoiced_minor_units ?? '0', order.currency)}</strong></article><article><span className="muted">التزام متبقٍ</span><strong>{formatMinorUnits(commitment?.remaining_commitment_minor_units ?? order.commercial_total_minor_units, order.currency)}</strong></article></div>}
          <div className="table-wrap"><table className="table-stackable"><thead><tr><th>الصنف</th><th>المطلوب</th><th>المستلم</th><th>المتبقي للاستلام</th><th>سعر الوحدة</th><th>إجمالي السطر</th></tr></thead><tbody>{lines.map((line) => { const state = receivingMap.get(line.id); return <tr key={line.id}><td data-label="الصنف">{line.item_description}</td><td data-label="المطلوب">{state?.ordered_quantity ?? line.quantity} {line.unit}</td><td data-label="المستلم">{state?.received_quantity ?? '0'} {line.unit}</td><td data-label="المتبقي للاستلام">{state?.remaining_quantity ?? line.quantity} {line.unit}</td><td data-label="سعر الوحدة">{line.unit_price_minor_units && line.currency ? formatMinorUnits(line.unit_price_minor_units, line.currency) : '—'}</td><td data-label="إجمالي السطر">{line.line_amount_minor_units && line.currency ? formatMinorUnits(line.line_amount_minor_units, line.currency) : '—'}</td></tr>; })}</tbody></table></div>
          <div><strong>ملفات الأمر/العقد</strong>{evidenceList(orderEvidence.get(order.id) ?? [])}</div>
          <details><summary>إرفاق أمر شراء/عقد أو إصدار جديد</summary><ProcurementEvidenceForm organizationId={organizationId} projectId={projectId} subject="PURCHASE_ORDER" subjectId={order.id} evidence={evidence} serverNonce={newCommandNonce()} /></details>
          {order.status === 'DRAFT' && <SubmitOrderAction organizationId={organizationId} projectId={projectId} orderId={order.id} serverNonce={newCommandNonce()} />}
          {order.status === 'SUBMITTED' && canApprove && <ApproveOrderAction organizationId={organizationId} projectId={projectId} orderId={order.id} serverNonce={newCommandNonce()} />}
          {order.status === 'APPROVED' && <><details><summary>تسجيل استلام</summary><ReceiptForm organizationId={organizationId} projectId={projectId} order={order} lines={lines} serverNonce={newCommandNonce()} /></details><details><summary>تسجيل فاتورة مورد من الاستلامات</summary><SupplierInvoiceForm organizationId={organizationId} projectId={projectId} order={order} basis={invoiceBasis} serverNonce={newCommandNonce()} /></details></>}
        </article>;
      })}
      <details><summary>إنشاء أمر شراء تجاري</summary><PurchaseOrderForm organizationId={organizationId} projectId={projectId} suppliers={suppliers} requests={requests} currency={project.reporting_currency} serverNonce={newCommandNonce()} /></details>
    </section>

    <section className="card stack"><div className="section-heading"><div><h2>الاستلام</h2><p className="muted">حقيقة كمية ثابتة؛ لا تعني فاتورة معتمدة ولا دفعًا.</p></div><span className="status">{receipts.length} استلام</span></div>
      {receipts.map((receipt) => <article className="card stack" key={receipt.id}><header className="topline"><h3>{receipt.purchase_order_reference}</h3><span>{formatDate(receipt.received_at)}</span></header><p className="muted">مرجع الدليل: {receipt.evidence_reference}</p><ul>{(receiptLineMap.get(receipt.id) ?? []).map((line) => <li key={line.id}>{line.item_description}: {line.quantity_received} {line.unit}</li>)}</ul>{evidenceList(receiptEvidence.get(receipt.id) ?? [])}<details><summary>إرفاق دليل الاستلام أو إصدار جديد</summary><ProcurementEvidenceForm organizationId={organizationId} projectId={projectId} subject="RECEIPT" subjectId={receipt.id} evidence={evidence} serverNonce={newCommandNonce()} /></details></article>)}
    </section>

    <section className="card stack"><div className="section-heading"><div><h2>فواتير الموردين والمستحقات</h2><p className="muted">الاعتماد يرحّل المستحق في Finance Core. الدفع والمطابقة البنكية حالتان منفصلتان.</p></div><span className="status">{invoices.length} فاتورة</span></div>
      {invoices.length === 0 ? <p className="muted">لا توجد فواتير موردين بعد. سجّل الفاتورة من أمر مستلم أعلاه.</p> : invoices.map((invoice) => <article className="card stack" key={invoice.id}><header className="topline"><div><h3>{invoice.invoice_reference} — {invoice.supplier_name}</h3><p className="muted">أمر {invoice.purchase_order_reference} · {formatDate(invoice.invoice_date)} · دليل {invoice.evidence_reference}</p></div><span className="status">{formatDocumentState(invoice.status)}</span></header>
        <div className="metrics-grid"><article><span className="muted">قيمة الفاتورة</span><strong>{formatMinorUnits(invoice.invoice_total_minor_units, invoice.currency)}</strong></article><article><span className="muted">مدفوع</span><strong>{formatMinorUnits(invoice.paid_minor_units, invoice.currency)}</strong><small>{formatPaymentState(invoice.payment_state)}</small></article><article><span className="muted">متبقي مستحق</span><strong>{formatMinorUnits(invoice.outstanding_minor_units, invoice.currency)}</strong></article><article><span className="muted">المطابقة البنكية</span><strong>{formatReconciliationState(invoice.reconciliation_state)}</strong><small>{formatMinorUnits(invoice.reconciled_minor_units, invoice.currency)}</small></article></div>
        <div className="table-wrap"><table className="table-stackable"><thead><tr><th>الصنف</th><th>كمية الفاتورة</th><th>سعر الوحدة</th><th>المبلغ</th></tr></thead><tbody>{(invoiceLineMap.get(invoice.id) ?? []).map((line) => <tr key={line.id}><td data-label="الصنف">{line.item_description}</td><td data-label="كمية الفاتورة">{line.quantity_invoiced} {line.unit}</td><td data-label="سعر الوحدة">{formatMinorUnits(line.unit_price_minor_units, line.currency)}</td><td data-label="المبلغ">{formatMinorUnits(line.line_amount_minor_units, line.currency)}</td></tr>)}</tbody></table></div>
        <div><strong>ملف فاتورة المورد</strong>{evidenceList(invoiceEvidence.get(invoice.id) ?? [])}</div>
        <details><summary>إرفاق فاتورة المورد أو إصدار جديد</summary><ProcurementEvidenceForm organizationId={organizationId} projectId={projectId} subject="SUPPLIER_INVOICE" subjectId={invoice.id} evidence={evidence} serverNonce={newCommandNonce()} /></details>
        {invoice.status === 'SUBMITTED' && canApprove && <ApproveInvoiceAction organizationId={organizationId} projectId={projectId} invoiceId={invoice.id} serverNonce={newCommandNonce()} />}
        {invoice.payable_is_reversed && <p className="error">تم عكس قيد المستحق في Finance Core. الفاتورة الأصلية باقية كسجل مصدر ثابت ولا تقبل دفعات جديدة.</p>}
        {invoice.status === 'APPROVED' && !invoice.payable_is_reversed && invoice.payment_state !== 'FULLY_PAID' && <details><summary>إعداد مقترح دفع من حساب المشروع</summary><SupplierPaymentForm organizationId={organizationId} projectId={projectId} invoice={invoice} cashAccounts={cashAccounts} serverNonce={newCommandNonce()} /></details>}
        {paymentProposals.filter((proposal) => proposal.obligation_id === invoice.cost_obligation_id && proposal.status === 'PROPOSED').map((proposal) => <div className="card stack" key={proposal.payment_proposal_id}>
          <span className="status">مقترح دفع بانتظار معتمد مستقل</span>
          <p>{formatMinorUnits(proposal.amount_minor_units, proposal.currency)} · {proposal.cash_account_name} · {formatDate(proposal.payment_date)}</p>
          {canApprove && membership.user_id !== proposal.prepared_by
            ? <SupplierPaymentApprovalForm organizationId={organizationId} projectId={projectId} paymentProposalId={proposal.payment_proposal_id} serverNonce={newCommandNonce()} />
            : <p className="muted">لا يجوز للمُعدّ اعتماد مقترحه؛ يلزم مالك مختلف.</p>}
        </div>)}
        {invoice.paid_minor_units !== '0' && invoice.reconciliation_state !== 'RECONCILED' && <p className="muted">تم الدفع لكنه لم يطابق بنكيًا بالكامل. <Link href={`/projects/${projectId}/cash`}>افتح النقدية والمطابقة ←</Link></p>}
        {invoice.reconciliation_state === 'RECONCILED' && <p className="status">تمت المطابقة البنكية عبر آلية Finance Core المشتركة.</p>}
      </article>)}
    </section>

    <section className="card stack"><h3>حدود محاسبية واضحة</h3><p className="muted">أمر الشراء ≠ الاستلام ≠ فاتورة المورد ≠ المستحق ≠ الدفع ≠ المطابقة البنكية. لا ضريبة آلية ولا تقييم مخزون ولا دفتر موازٍ. التصحيح المالي بعكس القيد وإعادة الترحيل من مساحة التكاليف/النقدية.</p><p><Link href={`/projects/${projectId}/cash`}>النقدية والمطابقة البنكية ←</Link> · <Link href={`/projects/${projectId}/costs`}>المستحقات والقيود ←</Link></p></section>
  </section>;
}

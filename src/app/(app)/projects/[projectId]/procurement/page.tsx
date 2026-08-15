import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import {
  getPurchaseOrderLines,
  getPurchaseOrders,
  getPurchaseRequestLines,
  getPurchaseRequests,
  getSuppliers,
} from '@/features/procurement/queries';
import { formatDate, formatDocumentState, formatQuantity, formatSupplierStatus } from '@/features/procurement/labels';
import {
  ApproveOrderAction,
  ApproveRequestAction,
  PurchaseOrderForm,
  PurchaseRequestForm,
  SubmitOrderAction,
  SubmitRequestAction,
  SupplierForm,
} from './forms';

export const dynamic = 'force-dynamic';

export default async function ProcurementPage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, suppliers, requests, requestLines, orders, orderLines] = await Promise.all([
    getCurrentMembership(organizationId),
    getSuppliers(organizationId),
    getPurchaseRequests(projectId),
    getPurchaseRequestLines(projectId),
    getPurchaseOrders(projectId),
    getPurchaseOrderLines(projectId),
  ]);
  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="لا تملك عضوية نشطة في منظمة هذا المشروع." />;
  }
  const canApprove = membership.role === 'OWNER';

  const requestLinesByRequest = new Map<string, typeof requestLines>();
  for (const line of requestLines) {
    const existing = requestLinesByRequest.get(line.purchase_request_id) ?? [];
    existing.push(line);
    requestLinesByRequest.set(line.purchase_request_id, existing);
  }
  const orderLinesByOrder = new Map<string, typeof orderLines>();
  for (const line of orderLines) {
    const existing = orderLinesByOrder.get(line.purchase_order_id) ?? [];
    existing.push(line);
    orderLinesByOrder.set(line.purchase_order_id, existing);
  }

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="procurement"
        title="المشتريات والعمليات المشتركة"
        subtitle="الموردون المشتركون، طلبات الشراء، وأوامر الشراء عبر القطاعات — بدون أرقام مالية في هذه المرحلة."
        internalReference={project.internal_reference}
        sector={project.sector}
      />

      <section className="card stack scroll-target" id="suppliers">
        <div className="section-heading">
          <div>
            <h2>الموردون</h2>
            <p className="muted">موردون على مستوى المنظمة، مشتركون بين كل مشاريعها وقطاعاتها.</p>
          </div>
          <span className="status">{suppliers.length} مورد</span>
        </div>
        {suppliers.length === 0 ? (
          <div className="card empty"><p className="muted">لا يوجد موردون بعد.</p></div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>الاسم</th><th>الرقم الضريبي</th><th>شروط السداد</th><th>الحالة</th></tr></thead>
              <tbody>
                {suppliers.map((supplier) => (
                  <tr key={supplier.id}>
                    <td>{supplier.name}</td>
                    <td>{supplier.tax_number ?? '—'}</td>
                    <td>{supplier.payment_terms ?? '—'}</td>
                    <td><span className="status">{formatSupplierStatus(supplier.status)}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <details><summary>تسجيل مورد جديد</summary><SupplierForm organizationId={organizationId} projectId={projectId} /></details>
      </section>

      <section className="card stack scroll-target" id="requests">
        <div className="section-heading">
          <div>
            <h2>طلبات الشراء</h2>
            <p className="muted">طلب → إرسال → اعتماد (يتطلب مالك المنظمة، ولا يعتمد طالب المستند).</p>
          </div>
          <span className="status">{requests.length} طلب</span>
        </div>
        {requests.length === 0 ? (
          <div className="card empty"><p className="muted">لا توجد طلبات شراء بعد.</p></div>
        ) : (
          <div className="stack">
            {requests.map((request) => {
              const lines = requestLinesByRequest.get(request.id) ?? [];
              return (
                <article className="card stack" key={request.id}>
                  <header className="topline">
                    <div><h3>{request.internal_reference}</h3><p className="muted">{formatDate(request.created_at)} · {request.line_count} سطر</p></div>
                    <span className="status">{formatDocumentState(request.status)}</span>
                  </header>
                  {request.description ? <p className="muted">{request.description}</p> : null}
                  <div className="table-wrap">
                    <table>
                      <thead><tr><th>الصنف</th><th>الكمية</th><th>الوحدة</th><th>ملاحظات</th></tr></thead>
                      <tbody>
                        {lines.map((line) => (
                          <tr key={line.id}>
                            <td>{line.item_description}</td>
                            <td>{line.quantity}</td>
                            <td>{line.unit}</td>
                            <td>{line.notes ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {request.status === 'DRAFT'
                    ? <SubmitRequestAction organizationId={organizationId} projectId={projectId} requestId={request.id} />
                    : null}
                  {request.status === 'SUBMITTED' && canApprove
                    ? <ApproveRequestAction organizationId={organizationId} projectId={projectId} requestId={request.id} />
                    : null}
                  {request.status === 'SUBMITTED' && !canApprove
                    ? <p className="muted">الاعتماد يتطلب صلاحية مالك المنظمة.</p>
                    : null}
                  {request.status === 'APPROVED'
                    ? <p className="muted">طلب معتمد — يمكن إنشاء أمر شراء منه.</p>
                    : null}
                  {request.status === 'REJECTED' ? <p className="error">مرفوض: {request.rejection_reason}</p> : null}
                </article>
              );
            })}
          </div>
        )}
        <details><summary>إنشاء طلب شراء جديد (مسودة)</summary><PurchaseRequestForm organizationId={organizationId} projectId={projectId} /></details>
      </section>

      <section className="card stack scroll-target" id="orders">
        <div className="section-heading">
          <div>
            <h2>أوامر الشراء</h2>
            <p className="muted">أمر → إرسال → اعتماد. اختياريًا مرتبط بمورد أو بطلب شراء معتمد.</p>
          </div>
          <span className="status">{orders.length} أمر</span>
        </div>
        {orders.length === 0 ? (
          <div className="card empty"><p className="muted">لا توجد أوامر شراء بعد.</p></div>
        ) : (
          <div className="stack">
            {orders.map((order) => {
              const lines = orderLinesByOrder.get(order.id) ?? [];
              return (
                <article className="card stack" key={order.id}>
                  <header className="topline">
                    <div>
                      <h3>{order.internal_reference}</h3>
                      <p className="muted">
                        {order.supplier_name ?? 'بدون مورد'}
                        {order.expected_delivery_date ? ` · تسليم متوقع ${formatDate(order.expected_delivery_date)}` : ''}
                        {' · '}{order.line_count} سطر
                      </p>
                    </div>
                    <span className="status">{formatDocumentState(order.status)}</span>
                  </header>
                  {order.description ? <p className="muted">{order.description}</p> : null}
                  <div className="table-wrap">
                    <table>
                      <thead><tr><th>الصنف</th><th>الكمية</th><th>الوحدة</th><th>ملاحظات</th></tr></thead>
                      <tbody>
                        {lines.map((line) => (
                          <tr key={line.id}>
                            <td>{line.item_description}</td>
                            <td>{line.quantity}</td>
                            <td>{line.unit}</td>
                            <td>{line.notes ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {order.status === 'DRAFT'
                    ? <SubmitOrderAction organizationId={organizationId} projectId={projectId} orderId={order.id} />
                    : null}
                  {order.status === 'SUBMITTED' && canApprove
                    ? <ApproveOrderAction organizationId={organizationId} projectId={projectId} orderId={order.id} />
                    : null}
                  {order.status === 'SUBMITTED' && !canApprove
                    ? <p className="muted">الاعتماد يتطلب صلاحية مالك المنظمة.</p>
                    : null}
                  {order.status === 'REJECTED' ? <p className="error">مرفوض: {order.rejection_reason}</p> : null}
                  {order.status === 'CANCELLED' ? <p className="error">ملغي: {order.rejection_reason}</p> : null}
                </article>
              );
            })}
          </div>
        )}
        <details><summary>إنشاء أمر شراء جديد (مسودة)</summary><PurchaseOrderForm organizationId={organizationId} projectId={projectId} suppliers={suppliers} requests={requests} /></details>
      </section>

      <section className="card stack">
        <h3>حدود هذه الشريحة</h3>
        <p className="muted">المشتريات هنا سجل تشغيلي كمّي فقط: لا أسعار، لا التزام مالي، لا فاتورة أو دفع، لا استلام/مخزون. الربط المالي بالـFinance Core والاستلام يأتيان في الشريحة التالية من R4.</p>
        <p className="muted"><Link href={`/projects/${projectId}`}>← العودة إلى مساحة المشروع</Link></p>
      </section>
    </section>
  );
}

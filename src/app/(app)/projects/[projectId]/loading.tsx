export default function ProjectLoading() {
  return (
    <section className="card stack">
      <div className="skeleton" style={{ height: 28, width: '40%' }} />
      <div className="skeleton" style={{ height: 120 }} />
      <p className="muted">جارٍ تحميل مساحة عمل المشروع…</p>
    </section>
  );
}

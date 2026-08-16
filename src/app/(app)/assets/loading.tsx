export default function AssetsLoading() {
  return (
    <section className="card stack">
      <div className="skeleton" style={{ height: 28, width: '40%' }} />
      <div className="skeleton" style={{ height: 120 }} />
      <p className="muted">جارٍ تحميل سجل الأصول وأداء القطاعات…</p>
    </section>
  );
}

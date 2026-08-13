export default function Loading() {
  return (
    <section className="stack">
      <div className="card skeleton" style={{ height: 96 }} aria-hidden="true" />
      <div className="card skeleton" style={{ height: 160 }} aria-hidden="true" />
      <div className="card skeleton" style={{ height: 240 }} aria-hidden="true" />
      <p className="muted" role="status">جارٍ تحميل بيانات الزراعة…</p>
    </section>
  );
}

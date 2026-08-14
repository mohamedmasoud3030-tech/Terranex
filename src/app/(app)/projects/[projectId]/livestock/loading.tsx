export default function LivestockLoading() {
  return (
    <section className="stack">
      <div className="card skeleton" style={{ height: 96 }} aria-hidden="true" />
      <div className="card skeleton" style={{ height: 160 }} aria-hidden="true" />
      <div className="card skeleton" style={{ height: 240 }} aria-hidden="true" />
      <output className="muted">جارٍ تحميل بيانات الثروة الحيوانية…</output>
    </section>
  );
}

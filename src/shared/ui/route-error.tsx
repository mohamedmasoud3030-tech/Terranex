'use client';

import Link from 'next/link';

/**
 * Shared body for route-level error boundaries.
 *
 * An `error.tsx` has to be a client component because it receives `reset`, and
 * this module therefore cannot live in `shared/ui/index.tsx`, which is
 * deliberately server-component-first. Twenty-one routes needing a boundary is
 * not twenty-one copies of the same markup: each route supplies only what
 * actually differs — the name of the surface that failed, and where "back"
 * goes.
 *
 * The raw `Error` is intentionally not rendered. Next.js still logs it
 * server-side with its digest; showing a stack trace to an operator is not
 * transparency, it is noise in the one moment they need a clear next step.
 */
export function RouteError({
  surface,
  detail,
  reset,
  backHref,
  backLabel,
}: {
  /** What failed, in the operator's own words: "مساحة الإغلاق المالي". */
  surface: string;
  /** What was being read, and the guarantee that no stale figures were shown. */
  detail: string;
  reset: () => void;
  backHref: string;
  backLabel: string;
}) {
  return (
    <section className="card stack" role="alert">
      <h1>تعذر تحميل {surface}</h1>
      <p className="error">{detail}</p>
      <p className="muted">
        لم تُعرض أرقام أو حالات قديمة بدلًا من البيانات الحالية، ولم يتغيّر أي سجل.
      </p>
      <div className="row-wrap">
        <button type="button" className="button" onClick={() => reset()}>
          إعادة المحاولة
        </button>
        <Link className="button secondary" href={backHref}>
          {backLabel}
        </Link>
      </div>
    </section>
  );
}

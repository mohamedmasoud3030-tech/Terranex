import Link from 'next/link';
import { useId, type ReactNode } from 'react';

/**
 * Canonical shared UI primitives (see SHARED_COMPONENT_ARCHITECTURE.md).
 *
 * Server-component-first, class-based, no external UI dependency. Each
 * primitive encodes exactly one layout/semantics convention. Pages keep
 * owning data, copy and business rules; nothing here reads data.
 */

/* ----------------------------------------------------------------------- */
/* Page structure                                                           */
/* ----------------------------------------------------------------------- */

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  badge,
  backHref,
  backLabel,
}: {
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  badge?: ReactNode;
  backHref?: string;
  backLabel?: string;
}) {
  return (
    <header className="page-header">
      <div className="page-header-main">
        {backHref ? (
          <Link className="muted back-link" href={backHref}>
            ← {backLabel ?? 'رجوع'}
          </Link>
        ) : null}
        {eyebrow ? <p className="muted eyebrow">{eyebrow}</p> : null}
        <div className="page-title-row">
          <h1>{title}</h1>
          {badge}
        </div>
        {description ? <p className="muted page-description">{description}</p> : null}
      </div>
      {actions ? <div className="page-actions">{actions}</div> : null}
    </header>
  );
}

/**
 * Titled card section. Renders `h2` (never `h1`). `collapsible` uses a
 * native `<details>` so it works without hydration and is keyboard/screen
 * reader accessible by default.
 */
export function Section({
  id,
  title,
  description,
  actions,
  children,
  collapsible = false,
  defaultOpen = false,
  className = '',
  headingLevel = 2,
}: {
  id?: string;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  collapsible?: boolean;
  defaultOpen?: boolean;
  className?: string;
  headingLevel?: 2 | 3;
}) {
  const generatedId = useId();
  const headingId = id ? `${id}-heading` : `section-${generatedId}`;
  const Heading = headingLevel === 3 ? 'h3' : 'h2';
  if (collapsible) {
    return (
      <details id={id} className={`card section-collapsible scroll-target ${className}`.trim()} open={defaultOpen}>
        <summary>
          <span className="section-summary-title">{title}</span>
          {description ? <span className="muted section-summary-desc">{description}</span> : null}
        </summary>
        <div className="stack section-body">{children}</div>
      </details>
    );
  }
  return (
    <section id={id} className={`card stack scroll-target ${className}`.trim()} aria-labelledby={headingId}>
      <div className="section-heading">
        <div>
          <Heading id={headingId}>{title}</Heading>
          {description ? <p className="muted">{description}</p> : null}
        </div>
        {actions ? <div className="section-actions">{actions}</div> : null}
      </div>
      {children}
    </section>
  );
}

/* ----------------------------------------------------------------------- */
/* Stats                                                                    */
/* ----------------------------------------------------------------------- */

export type StatTone = 'neutral' | 'negative' | 'positive';

export function StatGrid({ children, label }: { children: ReactNode; label?: string }) {
  return (
    <div className="stat-grid" role={label ? 'group' : undefined} aria-label={label}>
      {children}
    </div>
  );
}

/**
 * One figure with its label and an optional hint. When `href` is given the
 * whole tile is a link (drill-down); otherwise it is a static definition.
 */
export function Stat({
  label,
  value,
  hint,
  href,
  tone = 'neutral',
}: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  href?: string;
  tone?: StatTone;
}) {
  const body = (
    <>
      <span className="stat-label">{label}</span>
      <strong className="stat-value">{value}</strong>
      {hint ? <small className="stat-hint">{hint}</small> : null}
    </>
  );
  const className = `stat stat-${tone}`;
  if (href) {
    return (
      <Link className={`${className} stat-link`} href={href}>
        {body}
      </Link>
    );
  }
  return <article className={className}>{body}</article>;
}

/* ----------------------------------------------------------------------- */
/* Status & feedback                                                        */
/* ----------------------------------------------------------------------- */

export type BadgeTone = 'neutral' | 'success' | 'warning' | 'danger' | 'info';

export function StatusBadge({ tone = 'neutral', children }: { tone?: BadgeTone; children: ReactNode }) {
  return <span className={`status badge-${tone}`}>{children}</span>;
}

export function Banner({
  tone = 'info',
  role,
  children,
}: {
  tone?: 'info' | 'warning' | 'danger';
  role?: 'note' | 'alert' | 'status';
  children: ReactNode;
}) {
  const cls = tone === 'info' ? 'banner info' : tone === 'warning' ? 'banner warning' : 'banner';
  return (
    <div className={cls} role={role ?? (tone === 'danger' ? 'alert' : 'note')}>
      {children}
    </div>
  );
}

export function EmptyState({
  title,
  description,
  action,
  compact = false,
}: {
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  compact?: boolean;
}) {
  if (compact) {
    return (
      <div className="empty-inline">
        <p className="muted">
          <strong>{title}</strong>
          {description ? <> — {description}</> : null}
        </p>
        {action}
      </div>
    );
  }
  return (
    <section className="card stack empty">
      <h2>{title}</h2>
      {description ? <p className="muted">{description}</p> : null}
      {action ? <div className="page-actions center">{action}</div> : null}
    </section>
  );
}

export function PermissionState({
  message,
  backHref,
  backLabel = 'العودة',
}: {
  message: string;
  backHref: string;
  backLabel?: string;
}) {
  return (
    <section className="card stack" role="alert">
      <h1>غير مصرح</h1>
      <p className="error">{message}</p>
      <div>
        <Link className="button" href={backHref}>{backLabel}</Link>
      </div>
    </section>
  );
}

/** Route loading state. `blocks` approximates the page's section count. */
export function PageSkeleton({ blocks = 3, withNav = false }: { blocks?: number; withNav?: boolean }) {
  return (
    <div className="stack" role="status" aria-live="polite" aria-busy="true">
      <span className="sr-only">جارٍ تحميل البيانات…</span>
      <div className="skeleton skeleton-title" aria-hidden="true" />
      {withNav ? <div className="skeleton skeleton-nav" aria-hidden="true" /> : null}
      {Array.from({ length: blocks }, (_, index) => (
        <div key={index} className="skeleton skeleton-block" aria-hidden="true" />
      ))}
    </div>
  );
}

/* ----------------------------------------------------------------------- */
/* Navigation                                                               */
/* ----------------------------------------------------------------------- */

export type TabItem = { href: string; label: string; current?: boolean; description?: string };

/** Route-level second-level tabs (e.g. التكاليف ↔ النقدية). */
export function SectionTabs({ items, label }: { items: TabItem[]; label: string }) {
  return (
    <nav className="tab-strip tab-strip-secondary" aria-label={label}>
      {items.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          aria-current={item.current ? 'page' : undefined}
          className={item.current ? 'tab current' : 'tab'}
          title={item.description}
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}

/**
 * Sticky in-page anchor strip for long workspace pages. Pure anchors: no
 * hydration, works with `scroll-margin-top` on `.scroll-target` sections.
 */
export function InPageTabs({ items, label }: { items: { href: string; label: string }[]; label: string }) {
  return (
    <nav className="tab-strip tab-strip-inpage" aria-label={label}>
      {items.map((item) => (
        <a key={item.href} href={item.href} className="tab">
          {item.label}
        </a>
      ))}
    </nav>
  );
}

/* ----------------------------------------------------------------------- */
/* Key-value                                                                */
/* ----------------------------------------------------------------------- */

export function KeyValueList({ items }: { items: { label: ReactNode; value: ReactNode }[] }) {
  return (
    <dl className="facts">
      {items.map((item, index) => (
        <div key={index}>
          <dt>{item.label}</dt>
          <dd>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

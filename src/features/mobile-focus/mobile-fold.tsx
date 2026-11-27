'use client';
import { useEffect, useId, useState, type ReactNode } from 'react';

/**
 * MobileFold: one focus per screen on small devices.
 *
 * On phones the section renders as a collapsed disclosure so the owner opens
 * heavy detail on demand; on larger screens it is the ordinary expanded
 * section. The server render and the first client render are always the
 * expanded variant, so desktop output and hydration never change — after
 * hydration a small screen swaps to the collapsed disclosure. Nothing is
 * removed: every section keeps its full content behind one tap.
 */
export function MobileFold({
  id,
  title,
  description,
  actions,
  className = '',
  headingLevel = 2,
  children,
}: Readonly<{
  id?: string;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  className?: string;
  headingLevel?: 2 | 3;
  children: ReactNode;
}>) {
  const headingId = useId();
  const Heading = headingLevel === 3 ? 'h3' : 'h2';
  const [small, setSmall] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 960px)');
    const update = () => setSmall(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

  if (!small) {
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

  return (
    <details id={id} className={`card section-collapsible m-fold scroll-target ${className}`.trim()}>
      <summary>
        <span className="section-summary-title">{title}</span>
        {description ? <span className="muted section-summary-desc">{description}</span> : null}
      </summary>
      <div className="stack section-body">
        {actions ? <div className="section-actions">{actions}</div> : null}
        {children}
      </div>
    </details>
  );
}

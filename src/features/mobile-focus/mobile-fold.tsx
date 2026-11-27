'use client';
import { useEffect, useState, type ReactNode } from 'react';
import { Section } from '@/shared/ui';

/**
 * MobileFold: one focus per screen on small devices.
 *
 * On phones the section renders as a collapsed disclosure so the owner opens
 * heavy detail on demand; on larger screens it is the ordinary expanded
 * section. Both variants are the design system's own Section: the server
 * render and the first client render are always expanded, so desktop output
 * and hydration never change — after hydration a small screen swaps to the
 * collapsed disclosure. Nothing is removed: every section keeps its full
 * content behind one tap.
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
  const [small, setSmall] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 960px)');
    const update = () => setSmall(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

  return (
    <Section
      id={id}
      title={title}
      description={description}
      actions={actions}
      className={`${small ? 'm-fold' : ''} ${className}`.trim()}
      headingLevel={headingLevel}
      collapsible={small}
    >
      {children}
    </Section>
  );
}

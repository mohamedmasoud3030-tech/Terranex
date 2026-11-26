'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useSyncExternalStore } from 'react';
import { createPortal } from 'react-dom';

export type ProjectNavGroup = {
  id: string;
  label: string;
  items: ReadonlyArray<{ id: string; label: string; href: string }>;
};

const noop = () => () => {};

/**
 * Project sections inside the app sidebar. Rendered by the project layout (which
 * knows the project and its sector) and portalled into the sidebar slot, so the
 * list is exactly `sectionGroupsFor(sector)`: never a hand-copied second list.
 */
export function ProjectSideNav({ title, groups }: { title: string; groups: ReadonlyArray<ProjectNavGroup> }) {
  const pathname = usePathname() ?? '';
  const slot = useSyncExternalStore(
    noop,
    () => document.getElementById('sidebar-project-slot'),
    () => null,
  );
  if (!slot) return null;
  return createPortal(
    <nav className="side-project" aria-label={`أقسام المشروع: ${title}`}>
      <p className="side-project-title" title={title}>{title}</p>
      {groups.map((group) => (
        <div className="side-group" key={group.id}>
          <span className="side-group-label">{group.label}</span>
          {group.items.map((item) => (
            <Link
              key={item.id}
              href={item.href}
              aria-current={pathname === item.href.split('#')[0] && !item.href.includes('#') ? 'page' : undefined}
            >
              {item.label}
            </Link>
          ))}
        </div>
      ))}
    </nav>,
    slot,
  );
}

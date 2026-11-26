import Link from 'next/link';
import type { ProjectListItem } from '@/features/projects/queries';

/**
 * "Add something" shortcuts for the organization-level list pages. Entry forms
 * live inside each project, so a list page offers one button per project that
 * can take the entry, never a form of its own.
 */
export function EntryLinks({
  title,
  projects,
  hrefFor,
  label,
}: Readonly<{
  title: string;
  projects: readonly ProjectListItem[];
  hrefFor: (project: ProjectListItem) => string;
  label: string;
}>) {
  if (projects.length === 0) return null;
  return (
    <div className="entry-links" role="group" aria-label={title}>
      <strong>{title}</strong>
      <span className="badge-row">
        {projects.map((p) => (
          <Link key={p.id} className="button secondary sm" href={hrefFor(p)}>
            {label}: {p.name}
          </Link>
        ))}
      </span>
    </div>
  );
}

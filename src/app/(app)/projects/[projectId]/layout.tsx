import { getProject } from '@/features/projects/queries';
import { sectionGroupsFor } from '@/features/workspace/nav';
import { ProjectSideNav } from '@/shared/ui/project-side-nav';

/** Adds the project's sections to the app sidebar. Pages are unchanged. */
export default async function ProjectLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  const groups = project
    ? [
        { id: 'home', label: 'المشروع', items: [{ id: 'project-home', label: 'ملخص المشروع', href: `/projects/${projectId}` }] },
        ...sectionGroupsFor(project.sector).map((group) => ({
          id: group.id,
          label: group.label,
          items: group.sections.map((section) => ({ id: section.id, label: section.label, href: section.href(projectId) })),
        })),
      ]
    : [];
  return (
    <>
      {project ? <ProjectSideNav title={project.name} groups={groups} /> : null}
      {children}
    </>
  );
}

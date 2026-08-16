import { redirect } from 'next/navigation';

/**
 * Partner capital/result statements depend on unresolved ownership,
 * allocation and distribution policy (BD-003/004/006/008). Until R14 the
 * safe participant surface is identity/agreement transparency only.
 */
export default async function StatementsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  redirect(`/projects/${projectId}/investors`);
}

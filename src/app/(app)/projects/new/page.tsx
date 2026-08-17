import { getOrganizations } from '@/features/organizations/queries';
import { newCommandNonce } from '@/shared/idempotency';
import NewProjectForm from './project-form';

export default async function NewProject() {
  const organizations = await getOrganizations();
  const organization = organizations[0];
  if (!organization) {
    return <p className="error" role="alert">لا توجد منظمة متاحة. أنشئ منظمة أولًا.</p>;
  }
  return (
    <NewProjectForm
      organizationId={organization.id}
      commandNonce={newCommandNonce()}
    />
  );
}

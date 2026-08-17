import { getActiveOrganization } from '@/features/organizations/context';
import { newCommandNonce } from '@/shared/idempotency';
import NewProjectForm from './project-form';

export default async function NewProject() {
  const { organization } = await getActiveOrganization();
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

import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type OrganizationInvite = {
  id: string;
  organization_id: string;
  role: 'MEMBER';
  note: string | null;
  created_by: string;
  created_at: string;
  expires_at: string;
  accepted_by: string | null;
  accepted_at: string | null;
  revoked_at: string | null;
  status: 'PENDING' | 'ACCEPTED' | 'REVOKED' | 'EXPIRED';
};

export type OrganizationMember = {
  user_id: string;
  role: 'OWNER' | 'MEMBER';
  status: 'ACTIVE' | 'INACTIVE';
  created_at: string;
};

export async function getOrganizationInvites(organizationId: string): Promise<OrganizationInvite[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('organization_invites_read')
    .select('id,organization_id,role,note,created_by,created_at,expires_at,accepted_by,accepted_at,revoked_at,status')
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as OrganizationInvite[];
}

export async function getOrganizationMembers(organizationId: string): Promise<OrganizationMember[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('memberships')
    .select('user_id,role,status,created_at')
    .eq('organization_id', organizationId)
    .order('created_at');
  if (error) throwOperatorQuery(error);
  return (data ?? []) as OrganizationMember[];
}

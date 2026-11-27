import type { OrganizationInvite } from './queries';

const INVITE_STATUS_LABEL: Record<OrganizationInvite['status'], string> = {
  PENDING: 'بانتظار القبول',
  ACCEPTED: 'مقبولة',
  REVOKED: 'ملغاة',
  EXPIRED: 'منتهية الصلاحية',
};

export function inviteStatusLabel(status: OrganizationInvite['status']): string {
  return INVITE_STATUS_LABEL[status] ?? status;
}

'use client';

import { useActionState, useMemo, useState } from 'react';
import { createInvite, revokeInvite, type InviteActionState } from './actions';
import type { OrganizationInvite, OrganizationMember } from './queries';
import { inviteStatusLabel } from './labels';
import { commandIdempotencyKey } from '@/shared/idempotency';
import { formatDate } from '@/features/procurement/labels';

function CopyInviteLink({ token }: { token: string }) {
  const [copied, setCopied] = useState(false);
  const path = `/invite/${token}`;
  return (
    <div className="stack-sm">
      <label>
        رابط الدعوة
        <input readOnly value={path} onFocus={(e) => e.currentTarget.select()} dir="ltr" />
      </label>
      <div>
        <button
          type="button"
          className="button secondary"
          onClick={async () => {
            const absolute = `${window.location.origin}${path}`;
            try {
              await navigator.clipboard.writeText(absolute);
            } catch {
              window.prompt('انسخ الرابط يدويًا:', absolute);
            }
            setCopied(true);
          }}
        >
          {copied ? 'نُسخ الرابط' : 'نسخ الرابط'}
        </button>
      </div>
      <small className="muted">
        يظهر الرابط الكامل مرة واحدة هنا فقط؛ يُخزَّن النظام بصمته المشفرة فقط. أرسله للمدعو بأي وسيلة، وإن فقد ألغِ الدعوة وأنشئ غيرها.
      </small>
    </div>
  );
}

type InviteManagerProps = Readonly<{
  organizationId: string;
  canManage: boolean;
  invites: OrganizationInvite[];
  members: OrganizationMember[];
  currentUserId: string | null;
  commandNonce: string;
}>;

export function InviteManager({
  organizationId,
  canManage,
  invites,
  members,
  currentUserId,
  commandNonce,
}: InviteManagerProps) {
  const [createState, createAction, createPending] = useActionState<InviteActionState, FormData>(createInvite, {
    successCount: 0,
  });
  const [revokeState, revokeAction, revokePending] = useActionState(revokeInvite, { successCount: 0 });
  const idempotencyKey = useMemo(
    () => commandIdempotencyKey('org-invite-create', commandNonce, createState.successCount ?? 0),
    [commandNonce, createState.successCount],
  );

  return (
    <div className="stack">
      <div>
        <h3>الأعضاء</h3>
        <ul className="stack-sm">
          {members.map((m) => (
            <li key={m.user_id}>
              {m.role === 'OWNER' ? 'مالك' : 'عضو'}
              {m.status === 'ACTIVE' ? '' : ' (موقوف)'}
              {m.user_id === currentUserId ? ' — أنت' : ''}
              {' '}<small className="muted">منذ {formatDate(m.created_at)}</small>
            </li>
          ))}
        </ul>
      </div>

      {canManage ? (
        <form action={createAction} className="stack">
          <input type="hidden" name="organizationId" value={organizationId} />
          <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
          <label>
            ملاحظة الدعوة <span className="muted">(اختياري، لتمييزها لك فقط)</span>
            <input name="note" maxLength={200} placeholder="مثال: محاسب الشركة" />
          </label>
          {createState.error && <p className="error" role="alert">{createState.error}</p>}
          <div>
            <button disabled={createPending}>{createPending ? 'جارٍ الإنشاء…' : 'إنشاء رابط دعوة'}</button>
          </div>
          {createState.token ? <CopyInviteLink token={createState.token} /> : null}
        </form>
      ) : (
        <p className="muted">إنشاء الدعوات وإلغاؤها متاح لمالك المنظمة فقط.</p>
      )}

      <div>
        <h3>الدعوات</h3>
        {revokeState.error && <p className="error" role="alert">{revokeState.error}</p>}
        {invites.length === 0 ? (
          <p className="muted">لا توجد دعوات بعد.</p>
        ) : (
          <ul className="stack-sm">
            {invites.map((invite) => (
              <li key={invite.id} className="stack-sm">
                <span>
                  <strong>{invite.note ?? 'دعوة عضو'}</strong>{' '}
                  <span className="muted">{inviteStatusLabel(invite.status)}</span>
                </span>
                <br />
                <small className="muted">
                  أُنشئت {formatDate(invite.created_at)} · تنتهي {formatDate(invite.expires_at)}
                </small>
                {canManage && invite.status === 'PENDING' ? (
                  <form action={revokeAction}>
                    <input type="hidden" name="organizationId" value={organizationId} />
                    <input type="hidden" name="inviteId" value={invite.id} />
                    <button type="submit" className="button secondary" disabled={revokePending}>
                      إلغاء الدعوة
                    </button>
                  </form>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

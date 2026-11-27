-- Organization invites: command identity, single-use tokens, expiry, RLS.

create or replace function s100_run(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_result text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s100_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql into v_msg;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

-- Fixtures (as superuser): owner, second member, invitee, outsider.
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000101'),
  ('00000000-0000-4000-8000-000000000102'),
  ('00000000-0000-4000-8000-000000000103'),
  ('00000000-0000-4000-8000-000000000104');
insert into public.organizations(id, name) values
  ('10000000-0000-4000-8000-000000000101', 'منظمة الدعوات');
insert into public.memberships(organization_id, user_id, role, status) values
  ('10000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000101', 'OWNER', 'ACTIVE'),
  ('10000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'MEMBER', 'ACTIVE');

-- The raw token leaves the database exactly once, at creation.
select s100_run('00000000-0000-4000-8000-000000000101',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', 'محاسب الشركة', 'org-invite-create-0001')$$)
  as s100_token \gset

select 1/case when char_length(:'s100_token') = 64 then 1 else 0 end
  as s100_token_is_64_hex_chars;

select 1/case when (
  select count(*) from public.organization_invites
  where organization_id = '10000000-0000-4000-8000-000000000101'
    and token_hash = encode(digest(:'s100_token', 'sha256'), 'hex')
) = 1 then 1 else 0 end as s100_only_hash_is_stored;

-- Exact replay returns the empty replay signal and never a second invite.
select s100_run('00000000-0000-4000-8000-000000000101',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', 'محاسب الشركة', 'org-invite-create-0001')$$)
  as s100_replay \gset

select 1/case when :'s100_replay' = '' then 1 else 0 end
  as s100_replay_returns_empty_signal;

select 1/case when (
  select count(*) from public.organization_invites
  where organization_id = '10000000-0000-4000-8000-000000000101'
) = 1 then 1 else 0 end as s100_replay_creates_no_second_invite;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'ORGANIZATION_INVITE_CREATED'
    and organization_id = '10000000-0000-4000-8000-000000000101'
) = 1 then 1 else 0 end as s100_replay_does_not_duplicate_audit_event;

-- Same command key with a changed note is a hard failure.
select 1/case when s100_catch('00000000-0000-4000-8000-000000000101',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', 'مدير المبيعات', 'org-invite-create-0001')$$)
  like '%idempotency key payload mismatch%' then 1 else 0 end
  as s100_changed_payload_same_key_rejected;

-- A plain MEMBER cannot mint invites.
select 1/case when s100_catch('00000000-0000-4000-8000-000000000102',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', null, 'org-invite-create-0002')$$)
  like '%organization owner required%' then 1 else 0 end
  as s100_member_cannot_create_invite;

-- A non-member cannot create either.
select 1/case when s100_catch('00000000-0000-4000-8000-000000000104',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', null, 'org-invite-create-0003')$$)
  like '%forbidden%' then 1 else 0 end
  as s100_outsider_cannot_create_invite;

-- Preview reveals the organization name and status to a signed-in holder.
select s100_run('00000000-0000-4000-8000-000000000103', format(
  $$select organization_name || '|' || invite_status from public.preview_organization_invite(%L)$$,
  :'s100_token')) as s100_preview \gset

select 1/case when :'s100_preview' = 'منظمة الدعوات|PENDING' then 1 else 0 end
  as s100_preview_pending;

-- An unknown token previews nothing.
select 1/case when s100_run('00000000-0000-4000-8000-000000000103',
  $$select coalesce((select organization_name from public.preview_organization_invite('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')), 'NONE')$$)
  = 'NONE' then 1 else 0 end as s100_unknown_token_previews_nothing;

-- Acceptance creates an ACTIVE MEMBER membership and closes the invite.
select s100_run('00000000-0000-4000-8000-000000000103',
  format($$select public.accept_organization_invite(%L)$$, :'s100_token'))
  as s100_accepted_org \gset

select 1/case when :'s100_accepted_org' = '10000000-0000-4000-8000-000000000101' then 1 else 0 end
  as s100_accept_returns_organization;

select 1/case when exists (
  select 1 from public.memberships
  where organization_id = '10000000-0000-4000-8000-000000000101'
    and user_id = '00000000-0000-4000-8000-000000000103'
    and role = 'MEMBER' and status = 'ACTIVE'
) then 1 else 0 end as s100_invitee_is_active_member;

-- A retry by the same invitee replays idempotently.
select 1/case when s100_run('00000000-0000-4000-8000-000000000103',
  format($$select public.accept_organization_invite(%L)$$, :'s100_token'))
  = '10000000-0000-4000-8000-000000000101' then 1 else 0 end
  as s100_accept_retry_is_idempotent;

-- A different user cannot consume a used invite.
select 1/case when s100_catch('00000000-0000-4000-8000-000000000104',
  format($$select public.accept_organization_invite(%L)$$, :'s100_token'))
  like '%invite already used%' then 1 else 0 end
  as s100_used_invite_rejected_for_others;

-- Revocation blocks later acceptance.
select s100_run('00000000-0000-4000-8000-000000000101',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', null, 'org-invite-create-0004')$$)
  as s100_token_revoked \gset

select s100_run('00000000-0000-4000-8000-000000000101', format(
  $$select public.revoke_organization_invite('10000000-0000-4000-8000-000000000101', %L)$$,
  (select id::text from public.organization_invites
   where organization_id = '10000000-0000-4000-8000-000000000101'
     and idempotency_key = 'org-invite-create-0004'))) as s100_revoke_ok \gset

select 1/case when s100_catch('00000000-0000-4000-8000-000000000104',
  format($$select public.accept_organization_invite(%L)$$, :'s100_token_revoked'))
  like '%invite revoked%' then 1 else 0 end
  as s100_revoked_invite_rejected;

-- Expiry blocks acceptance even with a valid token.
select s100_run('00000000-0000-4000-8000-000000000101',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000101', null, 'org-invite-create-0005')$$)
  as s100_token_expired \gset

update public.organization_invites
  set expires_at = now() - interval '1 hour'
where organization_id = '10000000-0000-4000-8000-000000000101'
  and idempotency_key = 'org-invite-create-0005';

select 1/case when s100_catch('00000000-0000-4000-8000-000000000104',
  format($$select public.accept_organization_invite(%L)$$, :'s100_token_expired'))
  like '%invite expired%' then 1 else 0 end
  as s100_expired_invite_rejected;

-- Accepting an invite must never demote an existing OWNER membership.
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000105');
insert into public.organizations(id, name) values
  ('10000000-0000-4000-8000-000000000102', 'منظمة المالك الثانية');
insert into public.memberships(organization_id, user_id, role, status) values
  ('10000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000101', 'OWNER', 'ACTIVE'),
  ('10000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000105', 'MEMBER', 'INACTIVE');

select s100_run('00000000-0000-4000-8000-000000000101',
  $$select public.create_organization_invite('10000000-0000-4000-8000-000000000102', null, 'org-invite-create-0006')$$)
  as s100_token_reactivate \gset

select s100_run('00000000-0000-4000-8000-000000000105',
  format($$select public.accept_organization_invite(%L)$$, :'s100_token_reactivate')) as s100_reactivated \gset

select 1/case when exists (
  select 1 from public.memberships
  where organization_id = '10000000-0000-4000-8000-000000000102'
    and user_id = '00000000-0000-4000-8000-000000000105'
    and role = 'MEMBER' and status = 'ACTIVE'
) then 1 else 0 end as s100_inactive_membership_reactivated;

-- RLS: a non-member sees no invites for the organization, via base table or view.
select 1/case when s100_run('00000000-0000-4000-8000-000000000104',
  $$select count(*)::text from public.organization_invites where organization_id = '10000000-0000-4000-8000-000000000101'$$)
  = '0' then 1 else 0 end as s100_outsider_reads_no_invites;

select 1/case when s100_run('00000000-0000-4000-8000-000000000104',
  $$select count(*)::text from public.organization_invites_read where organization_id = '10000000-0000-4000-8000-000000000101'$$)
  = '0' then 1 else 0 end as s100_outsider_reads_no_invites_via_view;

-- A member sees the invites and the view never exposes the token hash.
select 1/case when s100_run('00000000-0000-4000-8000-000000000102',
  $$select count(*)::text from public.organization_invites_read where organization_id = '10000000-0000-4000-8000-000000000101'$$)
  = '3' then 1 else 0 end as s100_member_reads_invites_via_view;

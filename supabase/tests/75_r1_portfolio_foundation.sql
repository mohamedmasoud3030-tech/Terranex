-- R1 — Portfolio Foundation functional verification.
--
-- Proves the narrow management-only Portfolio slice:
--   * Portfolio creation is idempotent, validated, audited, and starts in
--     DRAFT with an initial append-only status-history row.
--   * The documented lifecycle transitions pass and every other transition
--     (backward, skip, re-assertion, archived mutation) is rejected, with
--     expected-status version awareness and idempotent replay.
--   * Safe metadata updates are allowed before archive and refused after.
--   * Responsible manager must be an ACTIVE member of the same organization.
--   * Project membership is same-organization only, at most one current
--     parent portfolio per project, assignable only to ACTIVE portfolios,
--     removable/movable only through the controlled commands, and
--     membership never mutates the project itself.
--   * Membership and status-history facts are append-only; the
--     authenticated role has no direct write path; anon is denied.
--
-- Fixtures are isolated in a dedicated R1 organization so no earlier
-- suite's data is touched.

create or replace function s75_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s75_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

create or replace function s75_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s75_owner_catch(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    return v_msg;
  end;
  return 'NO_EXCEPTION';
end $$;

-- ---------------------------------------------------------------------------
-- Fixtures: dedicated R1 organization and users.
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000071'),
  ('00000000-0000-4000-8000-000000000072'),
  ('00000000-0000-4000-8000-000000000073'),
  ('00000000-0000-4000-8000-000000000075')
on conflict (id) do nothing;

insert into public.organizations(id, name)
  values ('30000000-0000-4000-8000-000000000071', 'منظمة ر1')
  on conflict (id) do nothing;

insert into public.memberships(organization_id, user_id, role, status) values
  ('30000000-0000-4000-8000-000000000071', '00000000-0000-4000-8000-000000000071', 'OWNER', 'ACTIVE'),
  ('30000000-0000-4000-8000-000000000071', '00000000-0000-4000-8000-000000000072', 'MEMBER', 'ACTIVE'),
  ('30000000-0000-4000-8000-000000000071', '00000000-0000-4000-8000-000000000073', 'MEMBER', 'INACTIVE')
on conflict (organization_id, user_id) do nothing;

-- ---------------------------------------------------------------------------
-- 1. Creation, validation, idempotency.
-- ---------------------------------------------------------------------------
select s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة النمو','تنظيم مشاريع النمو العقاري',null,'r1-75-create-001')$$
) as r1_pf \gset

select 1/case when :'r1_pf' is not null then 1 else 0 end as r1_portfolio_created;

-- Idempotent replay with the identical payload returns the same portfolio.
select 1/case when s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة النمو','تنظيم مشاريع النمو العقاري',null,'r1-75-create-001')$$
) = :'r1_pf' then 1 else 0 end as r1_create_idempotent_replay;

-- Same key with a different payload is rejected.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','اسم مختلف تماما',null,null,'r1-75-create-001')$$
) like '%idempotency key payload mismatch%' then 1 else 0 end as r1_create_payload_mismatch_rejected;

-- Validation rejections.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','أ',null,null,'r1-75-create-badname')$$
) like '%invalid portfolio name%' then 1 else 0 end as r1_create_rejects_short_name;

select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة','غ',null,'r1-75-create-baddesc')$$
) like '%invalid portfolio description%' then 1 else 0 end as r1_create_rejects_short_description;

select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة أخرى',null,null,'short')$$
) like '%invalid idempotency key%' then 1 else 0 end as r1_create_rejects_short_key;

-- A user with no membership cannot create.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000075',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة محظورة',null,null,'r1-75-create-forbidden')$$
) like '%forbidden%' then 1 else 0 end as r1_create_denied_without_membership;

-- ---------------------------------------------------------------------------
-- 2. Initial lifecycle state and history.
-- ---------------------------------------------------------------------------
select 1/case when (
  select status from public.investment_portfolios where id = :'r1_pf'
) = 'DRAFT' then 1 else 0 end as r1_portfolio_starts_draft;

select 1/case when public.investment_portfolio_current_status(:'r1_pf') = 'DRAFT'
  then 1 else 0 end as r1_chain_tip_matches_status;

select 1/case when (
  select count(*) from public.investment_portfolio_state_history
   where portfolio_id = :'r1_pf' and previous_status is null and new_status = 'DRAFT'
) = 1 then 1 else 0 end as r1_initial_history_row;

select 1/case when (
  select count(*) from public.audit_events
   where organization_id = '30000000-0000-4000-8000-000000000071'
     and entity_id = :'r1_pf' and event_type = 'PORTFOLIO_CREATED'
) = 1 then 1 else 0 end as r1_create_audited;

-- ---------------------------------------------------------------------------
-- 3. Responsible manager membership guard.
-- ---------------------------------------------------------------------------
select s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة بإدارة','الغرض','00000000-0000-4000-8000-000000000072','r1-75-create-mgr01')$$
) as r1_pf_mgr \gset

select 1/case when (
  select responsible_manager_id from public.investment_portfolios where id = :'r1_pf_mgr'
) = '00000000-0000-4000-8000-000000000072' then 1 else 0 end as r1_manager_recorded;

select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة مدير غير عضو',null,'00000000-0000-4000-8000-000000000075','r1-75-create-mgr02')$$
) like '%responsible manager must be an active member%' then 1 else 0 end
  as r1_manager_non_member_rejected;

select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة مدير موقوف',null,'00000000-0000-4000-8000-000000000073','r1-75-create-mgr03')$$
) like '%responsible manager must be an active member%' then 1 else 0 end
  as r1_manager_inactive_member_rejected;

-- ---------------------------------------------------------------------------
-- 4. Lifecycle transitions.
-- ---------------------------------------------------------------------------
select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'DRAFT','ACTIVE','جاهزة للإسناد','r1-75-activate-001')$$
  , :'r1_pf')) as r1_activation \gset

select 1/case when :'r1_activation' is not null then 1 else 0 end as r1_activation_recorded;

select 1/case when (
  select status from public.investment_portfolios where id = :'r1_pf'
) = 'ACTIVE' then 1 else 0 end as r1_status_active_after_activation;

select 1/case when public.investment_portfolio_current_status(:'r1_pf') = 'ACTIVE'
  then 1 else 0 end as r1_chain_tip_active;

-- Idempotent replay of the same activation returns the same history row.
select 1/case when s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'DRAFT','ACTIVE','جاهزة للإسناد','r1-75-activate-001')$$
  , :'r1_pf')) = :'r1_activation' then 1 else 0 end as r1_transition_idempotent_replayed;

-- Same key, different payload is rejected.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'DRAFT','ACTIVE','سبب آخر مختلف','r1-75-activate-001')$$
  , :'r1_pf')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as r1_transition_payload_mismatch_rejected;

-- Expected-status version awareness: stale DRAFT expectation is refused.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'DRAFT','ARCHIVED','محاولة بقراءة قديمة','r1-75-stale-001')$$
  , :'r1_pf')) like '%expected portfolio status mismatch%' then 1 else 0 end
  as r1_transition_stale_expectation_rejected;

-- Same-state re-assertion is refused.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'ACTIVE','ACTIVE','إعادة تأكيد','r1-75-reassert-001')$$
  , :'r1_pf')) like '%invalid portfolio transition%' then 1 else 0 end
  as r1_transition_reassertion_rejected;

-- Activation requires a reason.
select s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_portfolio('30000000-0000-4000-8000-000000000071','محفظة بلا سبب',null,null,'r1-75-create-noreason')$$
) as r1_extra_portfolio \gset
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'DRAFT','ACTIVE','س','r1-75-badreason-001')$$
  , :'r1_extra_portfolio')) like '%invalid portfolio transition reason%'
  then 1 else 0 end as r1_transition_short_reason_rejected;

-- Every lifecycle change is audited.
select 1/case when (
  select count(*) from public.audit_events
   where organization_id = '30000000-0000-4000-8000-000000000071'
     and entity_id = :'r1_pf' and event_type = 'PORTFOLIO_TRANSITIONED'
) = 1 then 1 else 0 end as r1_transition_audited;

-- ---------------------------------------------------------------------------
-- 5. Safe metadata update.
-- ---------------------------------------------------------------------------
select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.update_investment_portfolio_metadata('30000000-0000-4000-8000-000000000071',%L,'محفظة النمو المحدثة','غرض إداري محدث','00000000-0000-4000-8000-000000000072','r1-75-update-001')$$
  , :'r1_pf')) as r1_update_result \gset
select 1/case when :'r1_update_result' = :'r1_pf' then 1 else 0 end as r1_metadata_updated;

select 1/case when (
  select name from public.investment_portfolios where id = :'r1_pf'
) = 'محفظة النمو المحدثة' then 1 else 0 end as r1_metadata_name_persisted;

-- Convergent replay: identical payload is a safe no-op.
select 1/case when s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.update_investment_portfolio_metadata('30000000-0000-4000-8000-000000000071',%L,'محفظة النمو المحدثة','غرض إداري محدث','00000000-0000-4000-8000-000000000072','r1-75-update-002')$$
  , :'r1_pf')) = :'r1_pf' then 1 else 0 end as r1_metadata_replay_convergent;

select 1/case when (
  select count(*) from public.audit_events
   where organization_id = '30000000-0000-4000-8000-000000000071'
     and entity_id = :'r1_pf' and event_type = 'PORTFOLIO_METADATA_UPDATED'
) >= 1 then 1 else 0 end as r1_metadata_update_audited;

-- ---------------------------------------------------------------------------
-- 6. Project membership: assignment rules.
-- ---------------------------------------------------------------------------
select s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_project('30000000-0000-4000-8000-000000000071','برج النيل','R1-PROJ-A',null,'REAL_ESTATE')$$
) as r1_project_a \gset
select s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_project('30000000-0000-4000-8000-000000000071','مزرعة الوادي ر1','R1-PROJ-B',null,'AGRICULTURE')$$
) as r1_project_b \gset

-- Assigning to a DRAFT portfolio is refused.
select s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-draft')$$
  , :'r1_pf_mgr', :'r1_project_a')) as r1_assign_draft_error \gset
select 1/case when :'r1_assign_draft_error' like '%only be assigned to an active portfolio%'
  then 1 else 0 end as r1_assign_rejects_draft_portfolio;

-- Assignment to the ACTIVE portfolio succeeds and is audited.
select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-001')$$
  , :'r1_pf', :'r1_project_a')) as r1_assignment_a \gset
select 1/case when :'r1_assignment_a' is not null then 1 else 0 end as r1_assignment_created;

-- Idempotent assignment replay returns the same membership row.
select 1/case when s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-001')$$
  , :'r1_pf', :'r1_project_a')) = :'r1_assignment_a' then 1 else 0 end
  as r1_assignment_idempotent_replayed;

-- Same key with a different project is rejected.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-001')$$
  , :'r1_pf', :'r1_project_b')) like '%idempotency key payload mismatch%'
  then 1 else 0 end as r1_assignment_payload_mismatch_rejected;

-- One current parent per project: a second assignment is refused even
-- when the target portfolio is ACTIVE.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-002')$$
  , :'r1_pf', :'r1_project_a')) like '%project already assigned to a portfolio%'
  then 1 else 0 end as r1_one_current_parent_enforced;

-- Unknown project in the same organization is refused.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,'99999999-0000-4000-8000-000000000099','r1-75-assign-ghost')$$
  , :'r1_pf')) like '%project not found in portfolio organization%'
  then 1 else 0 end as r1_assign_rejects_unknown_project;

select 1/case when (
  select count(*) from public.audit_events
   where organization_id = '30000000-0000-4000-8000-000000000071'
     and entity_id = :'r1_assignment_a'
     and event_type = 'PROJECT_ASSIGNED_TO_PORTFOLIO'
) = 1 then 1 else 0 end as r1_assignment_audited;

-- Membership never rewrites the project itself.
select 1/case when (
  select sector || '|' || lifecycle_state || '|' || name
  from public.investment_projects where id = :'r1_project_a'
) = 'REAL_ESTATE|DRAFT|برج النيل' then 1 else 0 end
  as r1_assignment_does_not_rewrite_project;

-- ---------------------------------------------------------------------------
-- 7. Removal, move, and history preservation.
-- ---------------------------------------------------------------------------
-- Assign the second project, then move it to the other ACTIVE portfolio.
select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'DRAFT','ACTIVE','تنشيط لأغراض النقل','r1-75-activate-mgr')$$
  , :'r1_pf_mgr')) as r1_mgr_activation \gset

select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-003')$$
  , :'r1_pf', :'r1_project_b')) as r1_assignment_b \gset

select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.move_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'إعادة توزيع إدارية','r1-75-move-001')$$
  , :'r1_project_b', :'r1_pf_mgr')) as r1_move_result \gset
select 1/case when :'r1_move_result' is not null then 1 else 0 end as r1_move_created;

-- Move closed the old membership and opened exactly one new current row.
select 1/case when (
  select removed_at is not null from public.portfolio_project_assignments
   where id = :'r1_assignment_b'
) then 1 else 0 end as r1_move_closed_source;

select 1/case when (
  select portfolio_id from public.portfolio_project_assignments
   where investment_project_id = :'r1_project_b' and removed_at is null
) = :'r1_pf_mgr' then 1 else 0 end as r1_move_current_parent_is_target;

-- Move replay is idempotent.
select 1/case when s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.move_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'إعادة توزيع إدارية','r1-75-move-001')$$
  , :'r1_project_b', :'r1_pf_mgr')) = :'r1_move_result' then 1 else 0 end
  as r1_move_idempotent_replayed;

-- Moving an unassigned project is refused.
select s75_run('00000000-0000-4000-8000-000000000071',
  $$select public.create_investment_project('30000000-0000-4000-8000-000000000071','مشروع غير مسند','R1-PROJ-C',null,'REAL_ESTATE')$$
) as r1_project_c \gset
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.move_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'نقل غير صالح','r1-75-move-unassigned')$$
  , :'r1_project_c', :'r1_pf_mgr')) like '%not assigned to a portfolio%'
  then 1 else 0 end as r1_move_unassigned_rejected;

-- Moving into the same portfolio is refused.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.move_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'نقل لنفس المحفظة','r1-75-move-same')$$
  , :'r1_project_a', :'r1_pf')) like '%already in the target portfolio%'
  then 1 else 0 end as r1_move_same_target_rejected;

-- Removal requires a reason.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.remove_project_from_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'س','r1-75-remove-badreason')$$
  , :'r1_pf', :'r1_project_a')) like '%invalid portfolio membership removal reason%'
  then 1 else 0 end as r1_remove_short_reason_rejected;

-- Removal against the wrong portfolio is refused.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.remove_project_from_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'إزالة من محفظة خاطئة','r1-75-remove-wrong')$$
  , :'r1_pf_mgr', :'r1_project_a')) like '%portfolio membership not found%'
  then 1 else 0 end as r1_remove_wrong_portfolio_rejected;

-- Capture project truth before removal.
select sector || '|' || lifecycle_state || '|' || name as r1_project_truth_before
  from public.investment_projects where id = :'r1_project_a' \gset

select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.remove_project_from_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'اكتمال المراجعة الإدارية','r1-75-remove-001')$$
  , :'r1_pf', :'r1_project_a')) as r1_remove_result \gset
select 1/case when :'r1_remove_result' = :'r1_assignment_a' then 1 else 0 end
  as r1_remove_soft_closed_row;

-- Idempotent removal replay returns the same membership row.
select 1/case when s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.remove_project_from_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'اكتمال المراجعة الإدارية','r1-75-remove-001')$$
  , :'r1_pf', :'r1_project_a')) = :'r1_assignment_a' then 1 else 0 end
  as r1_remove_idempotent_replayed;

-- Removal never rewrites the project.
select 1/case when (
  select sector || '|' || lifecycle_state || '|' || name
  from public.investment_projects where id = :'r1_project_a'
) = :'r1_project_truth_before' then 1 else 0 end
  as r1_removal_does_not_rewrite_project;

-- Removed membership history remains explainable.
select 1/case when (
  select removed_by is not null and removal_reason = 'اكتمال المراجعة الإدارية'
  from public.portfolio_project_assignments where id = :'r1_assignment_a'
) then 1 else 0 end as r1_removed_history_explainable;

-- A removed project can be re-assigned later.
select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-004')$$
  , :'r1_pf', :'r1_project_a')) as r1_reassignment \gset
select 1/case when :'r1_reassignment' is not null
  and :'r1_reassignment' <> :'r1_assignment_a' then 1 else 0 end
  as r1_reassignment_after_removal;

-- ---------------------------------------------------------------------------
-- 8. Archiving never touches member projects.
-- ---------------------------------------------------------------------------
select sector || '|' || lifecycle_state as r1_member_truth_before
  from public.investment_projects where id = :'r1_project_a' \gset

select s75_run('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'ACTIVE','ARCHIVED','إغلاق إداري للمحفظة','r1-75-archive-001')$$
  , :'r1_pf')) as r1_archive \gset

select 1/case when (
  select status from public.investment_portfolios where id = :'r1_pf'
) = 'ARCHIVED' then 1 else 0 end as r1_status_archived;

select 1/case when (
  select sector || '|' || lifecycle_state
  from public.investment_projects where id = :'r1_project_a'
) = :'r1_member_truth_before' then 1 else 0 end
  as r1_archiving_does_not_touch_member_projects;

select 1/case when (
  select count(*) from public.portfolio_project_assignments
   where portfolio_id = :'r1_pf' and removed_at is null
) = 1 then 1 else 0 end as r1_membership_survives_archiving;

-- Archived metadata is read-only.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.update_investment_portfolio_metadata('30000000-0000-4000-8000-000000000071',%L,'اسم جديد',null,null,'r1-75-update-archived')$$
  , :'r1_pf')) like '%archived portfolio metadata is read-only%'
  then 1 else 0 end as r1_archived_metadata_read_only;

-- No backward transition from ARCHIVED.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.transition_investment_portfolio('30000000-0000-4000-8000-000000000071',%L,'ARCHIVED','ACTIVE','محاولة إعادة تنشيط','r1-75-revive-001')$$
  , :'r1_pf')) like '%invalid portfolio transition%'
  then 1 else 0 end as r1_backward_transition_rejected;

-- Assignment into an ARCHIVED portfolio is refused.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071', format(
  $$select public.assign_project_to_portfolio('30000000-0000-4000-8000-000000000071',%L,%L,'r1-75-assign-archived')$$
  , :'r1_pf', :'r1_project_b')) like '%only be assigned to an active portfolio%'
  then 1 else 0 end as r1_assign_rejects_archived_portfolio;

-- ---------------------------------------------------------------------------
-- 9. Append-only guards and direct-write denial.
-- ---------------------------------------------------------------------------
select 1/case when s75_owner_catch(format(
  $$update public.investment_portfolio_state_history set new_status='DRAFT' where id=%L$$
  , :'r1_activation')) like '%append-only%' then 1 else 0 end
  as r1_status_history_update_rejected;

select 1/case when s75_owner_catch(format(
  $$delete from public.investment_portfolio_state_history where id=%L$$
  , :'r1_activation')) like '%append-only%' then 1 else 0 end
  as r1_status_history_delete_rejected;

select 1/case when s75_owner_catch(format(
  $$delete from public.portfolio_project_assignments where id=%L$$
  , :'r1_assignment_a')) like '%append-only%' then 1 else 0 end
  as r1_assignment_delete_rejected;

select 1/case when s75_owner_catch(format(
  $$update public.portfolio_project_assignments set portfolio_id=%L where id=%L$$
  , :'r1_pf_mgr', :'r1_reassignment')) like '%immutable%' then 1 else 0 end
  as r1_assignment_fact_rewrite_rejected;

-- Re-closing an already removed membership is refused.
select 1/case when s75_owner_catch(format(
  $$update public.portfolio_project_assignments
      set removed_at=now(), removed_by='00000000-0000-4000-8000-000000000071',
          removal_reason='محاولة ثانية',
          removal_idempotency_key='r1-75-direct-relock', removal_request_hash=repeat('a',64)
    where id=%L$$
  , :'r1_assignment_a')) like '%removal is final%' then 1 else 0 end
  as r1_double_removal_rejected;

-- The authenticated role has no direct write path on R1 tables.
select 1/case when s75_catch('00000000-0000-4000-8000-000000000071',
  $$insert into public.investment_portfolios(organization_id,name,status,created_by,idempotency_key,request_hash)
    values('30000000-0000-4000-8000-000000000071','كتابة مباشرة','DRAFT','00000000-0000-4000-8000-000000000071','r1-75-direct-insert','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
) <> 'NO_EXCEPTION' then 1 else 0 end as r1_direct_insert_denied;

-- RLS read scoping: the owner sees their portfolio through the read view.
select 1/case when s75_count('00000000-0000-4000-8000-000000000071', format(
  $$select count(*) from public.investment_portfolios_read where id=%L$$
  , :'r1_pf')) = 1 then 1 else 0 end as r1_read_view_visible_to_member;

-- anon is denied on tables and read views.
create or replace function s75_with_anon(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('role', 'anon', false);
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

select 1/case when s75_with_anon(format(
  $$select count(*) from public.investment_portfolios where id=%L$$
  , :'r1_pf')) <> 'NO_EXCEPTION' then 1 else 0 end as r1_anon_table_read_denied;

select 1/case when s75_with_anon(format(
  $$select count(*) from public.portfolio_project_assignments_read where portfolio_id=%L$$
  , :'r1_pf')) <> 'NO_EXCEPTION' then 1 else 0 end as r1_anon_view_read_denied;

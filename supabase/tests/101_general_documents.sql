-- General documents: private storage boundary, registration, versioning, RLS.

create or replace function s101_run(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_result text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s101_catch(p_user uuid, p_sql text)
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

-- Fixtures: two organizations, one member each, plus an outsider; one project.
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000202'),
  ('00000000-0000-4000-8000-000000000203');
insert into public.organizations(id, name) values
  ('10000000-0000-4000-8000-000000000201', 'منظمة المستندات'),
  ('10000000-0000-4000-8000-000000000202', 'منظمة أخرى');
insert into public.memberships(organization_id, user_id, role, status) values
  ('10000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000201', 'OWNER', 'ACTIVE'),
  ('10000000-0000-4000-8000-000000000202', '00000000-0000-4000-8000-000000000202', 'OWNER', 'ACTIVE');
insert into public.investment_projects(id, organization_id, name) values
  ('20000000-0000-4000-8000-000000000201', '10000000-0000-4000-8000-000000000201', 'مشروع المستندات');

-- A private object uploaded before registration (as the server action does).
insert into storage.objects(id, bucket_id, name, metadata) values
  (gen_random_uuid(), 'general-documents',
   '10000000-0000-4000-8000-000000000201/11111111-1111-4111-8111-111111111111',
   '{"size": 1234, "mimetype": "application/pdf"}');

select s101_run('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, null,
    'CONTRACT', 'عقد إيجار المحل',
    '10000000-0000-4000-8000-000000000201/11111111-1111-4111-8111-111111111111',
    'lease.pdf', 'application/pdf', 1234,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'gd-upload-0001')$$) as s101_version_1 \gset

select 1/case when exists (
  select 1 from public.general_documents d
  join public.general_document_versions v on v.document_id = d.id
  where d.organization_id = '10000000-0000-4000-8000-000000000201'
    and d.project_id is null and d.category = 'CONTRACT' and v.version_number = 1
) then 1 else 0 end as s101_org_level_document_registered;

-- Exact replay returns the same version and stores nothing twice.
select s101_run('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, null,
    'CONTRACT', 'عقد إيجار المحل',
    '10000000-0000-4000-8000-000000000201/11111111-1111-4111-8111-111111111111',
    'lease.pdf', 'application/pdf', 1234,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'gd-upload-0001')$$) as s101_replay \gset

select 1/case when :'s101_replay' = :'s101_version_1' then 1 else 0 end
  as s101_exact_replay_returns_same_version;

select 1/case when (
  select count(*) from public.general_document_versions
  where organization_id = '10000000-0000-4000-8000-000000000201'
) = 1 then 1 else 0 end as s101_replay_stores_no_second_version;

-- Same command key, different payload: hard failure.
select 1/case when s101_catch('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, null,
    'LICENSE', 'عقد إيجار المحل',
    '10000000-0000-4000-8000-000000000201/11111111-1111-4111-8111-111111111111',
    'lease.pdf', 'application/pdf', 1234,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'gd-upload-0001')$$)
  like '%idempotency key payload mismatch%' then 1 else 0 end
  as s101_changed_payload_same_key_rejected;

-- Registration without the private object is refused.
select 1/case when s101_catch('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, null,
    'GENERAL', 'مستند بلا ملف',
    '10000000-0000-4000-8000-000000000201/22222222-2222-4222-8222-222222222222',
    'ghost.pdf', 'application/pdf', 100,
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'gd-upload-0002')$$)
  like '%document storage object not found%' then 1 else 0 end
  as s101_unuploaded_object_rejected;

-- A storage metadata mismatch is refused.
insert into storage.objects(id, bucket_id, name, metadata) values
  (gen_random_uuid(), 'general-documents',
   '10000000-0000-4000-8000-000000000201/33333333-3333-4333-8333-333333333333',
   '{"size": 999, "mimetype": "application/pdf"}');
select 1/case when s101_catch('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, null,
    'GENERAL', 'مستند حجم مختلف',
    '10000000-0000-4000-8000-000000000201/33333333-3333-4333-8333-333333333333',
    'size.pdf', 'application/pdf', 100,
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    'gd-upload-0003')$$)
  like '%does not match storage object%' then 1 else 0 end
  as s101_size_mismatch_rejected;

-- An outsider cannot register into the organization.
select 1/case when s101_catch('00000000-0000-4000-8000-000000000203', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, null,
    'GENERAL', 'تطفل',
    '10000000-0000-4000-8000-000000000201/11111111-1111-4111-8111-111111111111',
    'lease.pdf', 'application/pdf', 1234,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'gd-upload-0004')$$)
  like '%forbidden%' then 1 else 0 end
  as s101_outsider_cannot_register;

-- A new version of the same document keeps identity and increments.
insert into storage.objects(id, bucket_id, name, metadata) values
  (gen_random_uuid(), 'general-documents',
   '10000000-0000-4000-8000-000000000201/44444444-4444-4444-8444-444444444444',
   '{"size": 1500, "mimetype": "application/pdf"}');
select s101_run('00000000-0000-4000-8000-000000000201', format($$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', null, %L,
    'CONTRACT', 'عقد إيجار المحل',
    '10000000-0000-4000-8000-000000000201/44444444-4444-4444-8444-444444444444',
    'lease-v2.pdf', 'application/pdf', 1500,
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    'gd-upload-0005')$$,
  (select document_id::text from public.general_document_versions where id = :'s101_version_1')))
  as s101_version_2 \gset

select 1/case when exists (
  select 1 from public.general_document_versions
  where id = :'s101_version_2' and version_number = 2
) then 1 else 0 end as s101_second_version_increments;

-- Project-linked document registers with its project.
insert into storage.objects(id, bucket_id, name, metadata) values
  (gen_random_uuid(), 'general-documents',
   '10000000-0000-4000-8000-000000000201/55555555-5555-4555-8555-555555555555',
   '{"size": 10, "mimetype": "image/png"}');
select 1/case when s101_run('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', '20000000-0000-4000-8000-000000000201', null,
    'LICENSE', 'ترخيص المشروع',
    '10000000-0000-4000-8000-000000000201/55555555-5555-4555-8555-555555555555',
    'license.png', 'image/png', 10,
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    'gd-upload-0006')$$) is not null then 1 else 0 end
  as s101_project_linked_document_registers;

-- A project from another organization is rejected.
select 1/case when s101_catch('00000000-0000-4000-8000-000000000201', $$
  select public.register_general_document(
    '10000000-0000-4000-8000-000000000201', '20000000-0000-4000-8000-000000000299', null,
    'LICENSE', 'مشروع غير موجود',
    '10000000-0000-4000-8000-000000000201/55555555-5555-4555-8555-555555555555',
    'license.png', 'image/png', 10,
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    'gd-upload-0007')$$)
  like '%project not found%' then 1 else 0 end
  as s101_unknown_project_rejected;

-- RLS: the other organization and the outsider see none of these documents.
select 1/case when s101_run('00000000-0000-4000-8000-000000000202',
  $$select count(*)::text from public.general_documents_read$$) = '0' then 1 else 0 end
  as s101_other_org_reads_no_documents;

select 1/case when s101_run('00000000-0000-4000-8000-000000000203',
  $$select count(*)::text from public.general_documents_read$$) = '0' then 1 else 0 end
  as s101_outsider_reads_no_documents;

-- The owner reads all versions through the view.
select 1/case when s101_run('00000000-0000-4000-8000-000000000201',
  $$select count(*)::text from public.general_documents_read
    where organization_id = '10000000-0000-4000-8000-000000000201'$$) = '3' then 1 else 0 end
  as s101_owner_reads_all_versions;

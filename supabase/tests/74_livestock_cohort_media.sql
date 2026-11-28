-- Livestock cohort media gate (photos and video attached to a batch).
--
-- Proves: the private bucket exists with the media envelope; a member can
-- attach an uploaded object to a cohort in their own project; the command
-- rejects a cohort from another project, an unsupported file type, an
-- oversized file and a non-member; the attachment creates no quantity fact;
-- and the read view is cohort-scoped.

create or replace function lcm_call(
  p_org uuid, p_project uuid, p_cohort uuid, p_title text, p_name text,
  p_filename text, p_mime text, p_size bigint, p_sha text, p_key text
) returns text language sql immutable as $$
  select format(
    'select public.register_livestock_cohort_media(%L,%L,%L,%L,%L,%L,%L,%s,%L,%L)',
    p_org, p_project, p_cohort, p_title, p_name, p_filename, p_mime, p_size, p_sha, p_key)
$$;

create or replace function lcm_attach(
  p_org uuid, p_project uuid, p_cohort uuid, p_title text, p_name text,
  p_filename text, p_mime text, p_size bigint, p_key text
) returns uuid language plpgsql as $$
begin
  return public.register_livestock_cohort_media(
    p_org,p_project,p_cohort,p_title,p_name,p_filename,p_mime,p_size,
    encode(sha256(convert_to(p_key,'UTF8')),'hex'),p_key);
end $$;

create or replace function lcm_catch(p_sql text) returns text language plpgsql as $$
begin
  begin execute p_sql; exception when others then return sqlerrm; end;
  return 'NO_EXCEPTION';
end $$;

do $$
declare
  v_org uuid; v_project uuid; v_cohort uuid; v_owner uuid;
  v_other_project uuid; v_other_cohort uuid; v_other_user uuid;
  v_name text; v_version uuid; v_media bigint; v_qty_before bigint; v_qty_after bigint;
  v_error text;
begin
  select c.organization_id, c.project_id, c.id into v_org, v_project, v_cohort
    from public.livestock_cohorts c order by c.created_at limit 1;
  if v_cohort is null then raise exception 'LCM_FAIL no seeded livestock cohort'; end if;
  select m.user_id into v_owner from public.memberships m
   where m.organization_id=v_org and m.status='ACTIVE' order by m.created_at limit 1;

  select c.project_id, c.id into v_other_project, v_other_cohort
    from public.livestock_cohorts c where c.project_id <> v_project limit 1;
  if v_other_cohort is null then
    select p.id into v_other_project from public.investment_projects p
     where p.id <> v_project limit 1;
  end if;
  select m.user_id into v_other_user from public.memberships m
   where m.organization_id <> v_org and m.status='ACTIVE' limit 1;

  v_name := v_org::text || '/' || gen_random_uuid()::text;
  insert into storage.objects(id,bucket_id,name,owner_id,metadata)
  values (gen_random_uuid(),public.livestock_media_bucket(),v_name,v_owner::text,
          jsonb_build_object('size',2048,'mimetype','image/jpeg'));

  select count(*) into v_qty_before from public.livestock_quantity_events where cohort_id=v_cohort;

  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('role','authenticated',false);
  v_version := lcm_attach(v_org,v_project,v_cohort,'صورة الدفعة',v_name,
                          'batch.jpg','image/jpeg',2048,'lcm-media-key-0001');
  execute 'reset role';

  select count(*) into v_media from public.livestock_cohort_media_read
   where cohort_id=v_cohort and storage_object_name=v_name;
  if v_media <> 1 then raise exception 'LCM_FAIL attachment not visible on the cohort'; end if;

  select count(*) into v_qty_after from public.livestock_quantity_events where cohort_id=v_cohort;
  if v_qty_after <> v_qty_before then raise exception 'LCM_FAIL media changed the quantity ledger'; end if;

  if not exists (
    select 1 from public.audit_events
     where event_type='LIVESTOCK_COHORT_MEDIA_REGISTERED' and entity_id=v_version
  ) then raise exception 'LCM_FAIL no audit fact'; end if;

  -- Idempotent replay returns the same version.
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('role','authenticated',false);
  if lcm_attach(v_org,v_project,v_cohort,'صورة الدفعة',v_name,'batch.jpg','image/jpeg',2048,
                'lcm-media-key-0001') <> v_version then
    raise exception 'LCM_FAIL replay created a second version';
  end if;
  execute 'reset role';

  -- Cross-project cohort, non-member, unsupported type and oversized file.
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('role','authenticated',false);
  if v_other_cohort is not null then
    v_error := lcm_catch(lcm_call(v_org,v_other_project,v_other_cohort,'صورة',v_name,
      'x.jpg','image/jpeg',2048,repeat('a',64),'lcm-media-key-0002'));
    if v_error not like '%livestock cohort not found%' then
      raise exception 'LCM_FAIL cross-project cohort accepted: %', v_error;
    end if;
  end if;
  v_error := lcm_catch(lcm_call(v_org,v_project,v_cohort,'ملف',v_name,
    'x.exe','application/x-msdownload',2048,repeat('c',64),'lcm-media-key-0004'));
  if v_error not like '%unsupported media file type%' then
    raise exception 'LCM_FAIL unsupported type accepted: %', v_error;
  end if;
  v_error := lcm_catch(lcm_call(v_org,v_project,v_cohort,'فيديو',v_name,
    'clip.mp4','video/mp4',public.livestock_media_max_bytes()+1,repeat('d',64),'lcm-media-key-0005'));
  execute 'reset role';
  if v_error not like '%media file size is invalid%' then
    raise exception 'LCM_FAIL oversized file accepted: %', v_error;
  end if;

  if v_other_user is not null then
    perform set_config('request.jwt.claim.sub',v_other_user::text,true);
    perform set_config('role','authenticated',false);
    v_error := lcm_catch(lcm_call(v_org,v_project,v_cohort,'صورة',v_name,
      'x.jpg','image/jpeg',2048,repeat('b',64),'lcm-media-key-0003'));
    execute 'reset role';
    if v_error not like '%forbidden%' then
      raise exception 'LCM_FAIL non-member accepted: %', v_error;
    end if;
  end if;

  -- The bucket carries the media envelope and stays private.
  if not exists (
    select 1 from storage.buckets b
     where b.id = public.livestock_media_bucket() and b.public = false
       and b.file_size_limit = public.livestock_media_max_bytes()
       and b.allowed_mime_types @> array['image/jpeg','image/png','image/webp','video/mp4']::text[]
  ) then raise exception 'LCM_FAIL media bucket envelope'; end if;

  raise notice 'LCM_OK cohort media attached, isolated and inert';
end $$;

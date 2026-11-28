-- Livestock cohort media (photos and video attached to a batch).
--
-- Operators already record what a batch cost and what it produced; the owner's
-- promise to investors is that they can also SEE the animals. This adds a
-- private media bucket and one command that attaches an already-uploaded photo
-- or video to a livestock cohort, reusing the general-document library (one
-- table, one version chain, one append-only rule) instead of a second file
-- system.
--
-- Scope: storage bucket + policy, one nullable cohort reference on
-- general_documents, the media MIME/size envelope on the version chain, one
-- SECURITY DEFINER command, one read view, RLS. No posting, no valuation, no
-- quantity effect: a photo is evidence, never an accounting fact.

-- ---------------------------------------------------------------------------
-- 1. Private media bucket. Object names stay server-generated as
--    <organization>/<uuid>, exactly like the document library.
-- ---------------------------------------------------------------------------
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'livestock-media', 'livestock-media', false, 52428800,
  array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.livestock_media_can_upload_object(p_name text)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select split_part(p_name,'/',3)=''
    and split_part(p_name,'/',2) ~ '^[0-9a-f-]{36}$'
    and public.is_active_member(case
      when split_part(p_name,'/',1) ~ '^[0-9a-f-]{36}$'
        then split_part(p_name,'/',1)::uuid else null end)
$$;
revoke all on function public.livestock_media_can_upload_object(text) from public,anon;
grant execute on function public.livestock_media_can_upload_object(text) to authenticated;

create policy livestock_media_object_insert on storage.objects
for insert to authenticated with check (
  bucket_id='livestock-media' and public.livestock_media_can_upload_object(name)
);

-- ---------------------------------------------------------------------------
-- 2. The batch reference. A media document always names its cohort; the
--    composite foreign key makes a cross-project or cross-organization
--    attachment impossible at the database boundary.
-- ---------------------------------------------------------------------------
alter table public.general_documents
  add column livestock_cohort_id uuid;

alter table public.general_documents
  add constraint general_documents_livestock_cohort_fkey
  foreign key (livestock_cohort_id, organization_id, project_id)
  references public.livestock_cohorts(id, organization_id, project_id)
  on delete restrict;

alter table public.general_documents
  add constraint general_documents_livestock_cohort_project_check
  check (livestock_cohort_id is null or project_id is not null);

create index general_documents_livestock_cohort_idx
  on public.general_documents(livestock_cohort_id, created_at desc);

-- The version chain already stores transport metadata for every file. Widen
-- its envelope to admit the private media bucket, its MIME types and a
-- 50 MiB ceiling; the document library's own PDF/JPEG/PNG rows stay valid.
alter table public.general_document_versions
  drop constraint general_document_versions_storage_bucket_check;
alter table public.general_document_versions
  add constraint general_document_versions_storage_bucket_check
  check (storage_bucket in ('general-documents','livestock-media'));

alter table public.general_document_versions
  drop constraint general_document_versions_mime_type_check;
alter table public.general_document_versions
  add constraint general_document_versions_mime_type_check
  check (mime_type in (
    'application/pdf','image/jpeg','image/png',
    'image/webp','video/mp4','video/quicktime','video/webm'
  ));

alter table public.general_document_versions
  drop constraint general_document_versions_size_bytes_check;
alter table public.general_document_versions
  add constraint general_document_versions_size_bytes_check
  check (size_bytes between 1 and 52428800);

-- ---------------------------------------------------------------------------
-- 3. One atomic command: attach an already-uploaded object to a cohort.
-- ---------------------------------------------------------------------------
create or replace function public.register_livestock_cohort_media(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_title text,
  p_storage_object_name text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_sha256 text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_object record;
  v_storage_size bigint;
  v_storage_mime text;
  v_existing public.general_document_versions%rowtype;
  v_document_id uuid;
  v_version_id uuid;
  v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.livestock_cohorts c
     where c.id=p_cohort_id and c.organization_id=p_organization_id and c.project_id=p_project_id
  ) then
    raise exception 'livestock cohort not found';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 200 then
    raise exception 'invalid media title';
  end if;
  if p_original_filename is null or char_length(trim(p_original_filename)) not between 1 and 240
     or p_original_filename ~ E'[\\\\/\\n\\r]' then
    raise exception 'invalid media filename';
  end if;
  if p_mime_type not in ('image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm') then
    raise exception 'unsupported media file type';
  end if;
  if p_size_bytes is null or p_size_bytes not between 1 and 52428800 then
    raise exception 'media file size is invalid';
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid media checksum';
  end if;
  if p_storage_object_name is null or p_storage_object_name !~
    ('^' || p_organization_id::text || '/[0-9a-f-]{36}$') then
    raise exception 'invalid media storage path';
  end if;

  v_hash := encode(digest(
    p_project_id::text || '|' || p_cohort_id::text || '|' || trim(p_title) || '|'
    || p_storage_object_name || '|' || trim(p_original_filename) || '|'
    || p_mime_type || '|' || p_size_bytes::text || '|' || lower(p_sha256), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-media:' || trim(p_idempotency_key), 0));

  -- Storage is authoritative for existence and transport metadata.
  select o.bucket_id,o.name,o.metadata into v_object
    from storage.objects o
   where o.bucket_id='livestock-media' and o.name=p_storage_object_name
   for share;
  if not found then raise exception 'media storage object not found'; end if;
  if coalesce(v_object.metadata->>'size','') !~ '^[0-9]+$' then
    raise exception 'media storage object has invalid size metadata';
  end if;
  v_storage_size := (v_object.metadata->>'size')::bigint;
  v_storage_mime := lower(coalesce(v_object.metadata->>'mimetype',''));
  if v_storage_size is distinct from p_size_bytes then
    raise exception 'media size does not match storage object';
  end if;
  if v_storage_mime is distinct from lower(p_mime_type) then
    raise exception 'media MIME type does not match storage object';
  end if;

  select * into v_existing from public.general_document_versions
    where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.general_documents(
    organization_id,project_id,livestock_cohort_id,category,title,created_by
  ) values (
    p_organization_id,p_project_id,p_cohort_id,'GENERAL',trim(p_title),v_actor
  ) returning id into v_document_id;

  insert into public.general_document_versions(
    organization_id,document_id,version_number,storage_bucket,storage_object_name,
    original_filename,mime_type,size_bytes,sha256,uploaded_by,
    idempotency_key,request_hash
  ) values (
    p_organization_id,v_document_id,1,'livestock-media',p_storage_object_name,
    trim(p_original_filename),p_mime_type,p_size_bytes,lower(p_sha256),v_actor,
    trim(p_idempotency_key),v_hash
  ) returning id into v_version_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id,v_actor,'LIVESTOCK_COHORT_MEDIA_REGISTERED','general_document_version',v_version_id,
    jsonb_build_object('project_id',p_project_id,'cohort_id',p_cohort_id,'document_id',v_document_id,
      'mime_type',p_mime_type,'size_bytes',p_size_bytes,'sha256',lower(p_sha256)));
  return v_version_id;
end $$;

revoke all on function public.register_livestock_cohort_media(uuid,uuid,uuid,text,text,text,text,bigint,text,text)
  from public,anon;
grant execute on function public.register_livestock_cohort_media(uuid,uuid,uuid,text,text,text,text,bigint,text,text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Read projection: one row per uploaded media object, latest version first.
-- ---------------------------------------------------------------------------
create view public.livestock_cohort_media_read with (security_invoker=on) as
select
  v.id,
  d.organization_id,
  d.project_id,
  d.livestock_cohort_id as cohort_id,
  c.cohort_reference,
  d.id as document_id,
  d.title,
  v.version_number,
  v.storage_bucket,
  v.storage_object_name,
  v.original_filename,
  v.mime_type,
  v.size_bytes,
  v.sha256,
  v.uploaded_by,
  v.uploaded_at
from public.general_document_versions v
join public.general_documents d
  on (d.id, d.organization_id) = (v.document_id, v.organization_id)
join public.livestock_cohorts c
  on (c.id, c.organization_id, c.project_id) = (d.livestock_cohort_id, d.organization_id, d.project_id)
where v.storage_bucket = 'livestock-media';

revoke all on public.livestock_cohort_media_read from public,anon;
grant select on public.livestock_cohort_media_read to authenticated;

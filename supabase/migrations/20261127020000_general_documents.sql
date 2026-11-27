-- General documents (first-trial readiness, Stream B).
--
-- Organization-level private document library NOT tied to Procurement: any
-- active member uploads contracts, licenses, certificates and other files,
-- versioned and append-only, reusing the R4 private-storage boundary
-- (server-generated object names, SHA-256 checksums, immutable versions,
-- signed-url reads). No purchase order, receipt or supplier invoice link is
-- required; an optional project link scopes a document to one project.

-- ---------------------------------------------------------------------------
-- 1. Private storage boundary. Object names are server-generated as
--    <organization>/<uuid>; original filenames live only in metadata.
-- ---------------------------------------------------------------------------
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'general-documents', 'general-documents', false, 10485760,
  array['application/pdf','image/jpeg','image/png']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.gd_can_upload_document_object(p_name text)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select split_part(p_name,'/',3)=''
    and split_part(p_name,'/',2) ~ '^[0-9a-f-]{36}$'
    and public.is_active_member(case
      when split_part(p_name,'/',1) ~ '^[0-9a-f-]{36}$'
        then split_part(p_name,'/',1)::uuid else null end)
$$;
revoke all on function public.gd_can_upload_document_object(text) from public,anon;
grant execute on function public.gd_can_upload_document_object(text) to authenticated;

create policy general_documents_object_insert on storage.objects
for insert to authenticated with check (
  bucket_id='general-documents' and public.gd_can_upload_document_object(name)
);

-- ---------------------------------------------------------------------------
-- 2. Versioned document metadata (append-only).
-- ---------------------------------------------------------------------------
create table public.general_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid,
  category text not null check (category in (
    'CONTRACT','LICENSE','CERTIFICATE','CORRESPONDENCE','FINANCIAL','GENERAL'
  )),
  title text not null check (char_length(trim(title)) between 3 and 200),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  unique (id, organization_id)
);
create index general_documents_org_idx
  on public.general_documents(organization_id, created_at);

create table public.general_document_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  document_id uuid not null references public.general_documents(id) on delete restrict,
  version_number integer not null check (version_number > 0),
  storage_bucket text not null default 'general-documents'
    check (storage_bucket = 'general-documents'),
  storage_object_name text not null,
  original_filename text not null check (
    char_length(trim(original_filename)) between 1 and 240
    and original_filename !~ E'[\\\\/\\n\\r]'
  ),
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  foreign key (document_id, organization_id)
    references public.general_documents(id, organization_id) on delete restrict,
  unique (document_id, version_number),
  unique (storage_bucket, storage_object_name),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  check (storage_object_name = organization_id::text || '/'
    || split_part(storage_object_name, '/', 2))
);
create index general_document_versions_document_idx
  on public.general_document_versions(document_id, version_number desc);

create or replace function public.gd_documents_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'general documents are append-only';
end $$;
create trigger general_documents_append_only
before update or delete on public.general_documents
for each row execute function public.gd_documents_append_only();
create trigger general_document_versions_append_only
before update or delete on public.general_document_versions
for each row execute function public.gd_documents_append_only();

-- One atomic command creates a document (or a new version of an existing one)
-- from an already-uploaded private object.
create or replace function public.register_general_document(
  p_organization_id uuid,
  p_project_id uuid,
  p_document_id uuid,
  p_category text,
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
  v_document public.general_documents%rowtype;
  v_existing public.general_document_versions%rowtype;
  v_object record;
  v_storage_size bigint;
  v_storage_mime text;
  v_document_id uuid;
  v_version_id uuid;
  v_version_number integer;
  v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_project_id is not null and not exists (select 1 from public.investment_projects p
    where p.id=p_project_id and p.organization_id=p_organization_id) then
    raise exception 'project not found';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_category not in ('CONTRACT','LICENSE','CERTIFICATE','CORRESPONDENCE','FINANCIAL','GENERAL') then
    raise exception 'invalid document category';
  end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 200 then raise exception 'invalid document title'; end if;
  if p_original_filename is null or char_length(trim(p_original_filename)) not between 1 and 240
     or p_original_filename ~ E'[\\\\/\\n\\r]' then raise exception 'invalid document filename'; end if;
  if p_mime_type not in ('application/pdf','image/jpeg','image/png') then raise exception 'unsupported document file type'; end if;
  if p_size_bytes is null or p_size_bytes not between 1 and 10485760 then raise exception 'document file size is invalid'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid document checksum'; end if;
  if p_storage_object_name is null or p_storage_object_name !~
    ('^' || p_organization_id::text || '/[0-9a-f-]{36}$') then
    raise exception 'invalid document storage path';
  end if;

  v_hash := encode(digest(
    coalesce(p_project_id::text,'') || '|' || coalesce(p_document_id::text,'') || '|' || p_category || '|'
    || trim(p_title) || '|' || p_storage_object_name || '|' || trim(p_original_filename) || '|'
    || p_mime_type || '|' || p_size_bytes::text || '|' || lower(p_sha256), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gd-document:' || trim(p_idempotency_key), 0));

  -- The Storage catalog is authoritative for object existence and transport
  -- metadata; lock the row for the transaction as in R4 evidence.
  select o.bucket_id,o.name,o.metadata into v_object
    from storage.objects o
   where o.bucket_id='general-documents' and o.name=p_storage_object_name
   for share;
  if not found then raise exception 'document storage object not found'; end if;
  if coalesce(v_object.metadata->>'size','') !~ '^[0-9]+$' then
    raise exception 'document storage object has invalid size metadata';
  end if;
  v_storage_size := (v_object.metadata->>'size')::bigint;
  v_storage_mime := lower(coalesce(v_object.metadata->>'mimetype',''));
  if v_storage_size is distinct from p_size_bytes then
    raise exception 'document size does not match storage object';
  end if;
  if v_storage_mime is distinct from lower(p_mime_type) then
    raise exception 'document MIME type does not match storage object';
  end if;

  select * into v_existing from public.general_document_versions
    where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if p_document_id is null then
    insert into public.general_documents(
      organization_id,project_id,category,title,created_by
    ) values (p_organization_id,p_project_id,p_category,trim(p_title),v_actor)
    returning id into v_document_id;
    v_version_number := 1;
  else
    select * into v_document from public.general_documents
      where id=p_document_id and organization_id=p_organization_id for update;
    if not found then raise exception 'document not found'; end if;
    if v_document.category <> p_category or v_document.title <> trim(p_title) then
      raise exception 'document identity and category are immutable across versions';
    end if;
    v_document_id := v_document.id;
    select coalesce(max(version_number),0)+1 into v_version_number
      from public.general_document_versions where document_id=v_document_id;
  end if;

  insert into public.general_document_versions(
    organization_id,document_id,version_number,storage_object_name,
    original_filename,mime_type,size_bytes,sha256,uploaded_by,
    idempotency_key,request_hash
  ) values (
    p_organization_id,v_document_id,v_version_number,p_storage_object_name,
    trim(p_original_filename),p_mime_type,p_size_bytes,lower(p_sha256),v_actor,
    trim(p_idempotency_key),v_hash
  ) returning id into v_version_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id,v_actor,'GENERAL_DOCUMENT_REGISTERED','general_document_version',v_version_id,
    jsonb_build_object('project_id',p_project_id,'document_id',v_document_id,'version_number',v_version_number,
      'category',p_category,'sha256',lower(p_sha256),'size_bytes',p_size_bytes));
  return v_version_id;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Tenant isolation and read projection.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['general_documents','general_document_versions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
  end loop;
end $$;
revoke all on public.general_documents, public.general_document_versions from public,anon,authenticated;
grant select on public.general_documents, public.general_document_versions to authenticated;

create policy general_documents_object_read on storage.objects
for select to authenticated using (
  bucket_id='general-documents' and exists (
    select 1 from public.general_document_versions v
    where v.storage_bucket=storage.objects.bucket_id and v.storage_object_name=storage.objects.name
      and public.is_active_member(v.organization_id)
  )
);
create policy general_documents_unregistered_delete on storage.objects
for delete to authenticated using (
  bucket_id='general-documents'
  and public.gd_can_upload_document_object(name)
  and not exists (select 1 from public.general_document_versions v
    where v.storage_bucket=storage.objects.bucket_id and v.storage_object_name=storage.objects.name)
);

create or replace view public.general_documents_read with (security_invoker=on) as
select d.id as document_id,d.organization_id,d.project_id,d.category,d.title,
  v.id as version_id,v.version_number,v.original_filename,v.mime_type,
  v.size_bytes::text as size_bytes,v.sha256,v.storage_bucket,v.storage_object_name,
  v.uploaded_by,v.uploaded_at
from public.general_documents d
join public.general_document_versions v on v.document_id=d.id;
grant select on public.general_documents_read to authenticated;

revoke all on function public.register_general_document(uuid,uuid,uuid,text,text,text,text,text,bigint,text,text) from public,anon;
grant execute on function public.register_general_document(uuid,uuid,uuid,text,text,text,text,text,bigint,text,text) to authenticated;

-- A registered immutable version must never outlive its Storage object. Where
-- storage.objects has a unique (bucket_id,name) key (CI shim, self-hosted),
-- close the registration/delete MVCC race with an FK as R4 did; elsewhere the
-- RPC lock and validation remain the guard.
do $gd_fk$
begin
  if exists (
    select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'storage' and t.relname = 'objects'
       and c.contype in ('p','u')
       and (select array_agg(a.attname::text order by a.attname::text)
              from unnest(c.conkey) k
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k) = array['bucket_id','name']
  ) then
    alter table public.general_document_versions
      add constraint general_document_versions_storage_object_fk
      foreign key (storage_bucket, storage_object_name)
      references storage.objects(bucket_id, name)
      on update restrict
      on delete restrict;
  else
    raise notice 'storage.objects has no unique (bucket_id, name); general-documents FK skipped';
  end if;
end
$gd_fk$;

-- Qualify pgcrypto digest for the hosted `extensions` schema layout (see
-- 20260813000500_pgcrypto_digest_schema_compat.sql).
do $gd_pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
  r record;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';
  if v_pgcrypto_schema is null then
    raise exception 'pgcrypto extension is required';
  end if;
  for r in
    select p.oid, p.oid::regprocedure::text as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'register_general_document'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\('
  loop
    v_definition := pg_get_functiondef(r.oid);
    v_rewritten := regexp_replace(
      v_definition,
      '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
      E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
      'g'
    );
    if v_rewritten = v_definition then
      raise exception 'failed to qualify pgcrypto digest in %', r.signature;
    end if;
    execute v_rewritten;
  end loop;
end
$gd_pgcrypto_compat$;

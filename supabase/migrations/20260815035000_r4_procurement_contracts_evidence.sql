-- R4 Contracts & Evidence Closure.
--
-- Adds the bounded, shared document/evidence capability used by Procurement:
-- private object storage, immutable/versioned document metadata, typed links to
-- Purchase Orders, Receipts and Supplier Invoices, and approval gates over the
-- exact evidence versions. It does not add a contract-management suite,
-- signature workflow, retention policy, tax logic or a second audit system.

-- ---------------------------------------------------------------------------
-- 1. Private storage boundary. Object names are server-generated as
--    <organization>/<project>/<uuid>; original filenames live only in metadata.
-- ---------------------------------------------------------------------------
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'procurement-evidence', 'procurement-evidence', false, 10485760,
  array['application/pdf','image/jpeg','image/png']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.r4_can_upload_evidence_object(p_name text)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select split_part(p_name,'/',4)=''
    and split_part(p_name,'/',3) ~ '^[0-9a-f-]{36}$'
    and public.is_active_member(case
      when split_part(p_name,'/',1) ~ '^[0-9a-f-]{36}$'
        then split_part(p_name,'/',1)::uuid else null end)
    and exists (
      select 1 from public.investment_projects p
      where p.organization_id::text=split_part(p_name,'/',1)
        and p.id::text=split_part(p_name,'/',2)
    )
$$;
revoke all on function public.r4_can_upload_evidence_object(text) from public,anon;
grant execute on function public.r4_can_upload_evidence_object(text) to authenticated;

create policy procurement_evidence_object_insert on storage.objects
for insert to authenticated with check (
  bucket_id='procurement-evidence' and public.r4_can_upload_evidence_object(name)
);

-- SELECT is added after the authoritative version table exists. No UPDATE
-- policy is ever granted. DELETE is allowed only for an upload which failed
-- before metadata registration, enabling safe application compensation.

-- ---------------------------------------------------------------------------
-- 2. Versioned evidence metadata and typed Procurement links.
-- ---------------------------------------------------------------------------
create table public.procurement_evidence_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  classification text not null check (classification in (
    'CONTRACT','PURCHASE_ORDER','RECEIPT','SUPPLIER_INVOICE'
  )),
  title text not null check (char_length(trim(title)) between 3 and 200),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  unique (id, project_id, organization_id),
  unique (id, organization_id)
);

create table public.procurement_evidence_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  document_id uuid not null references public.procurement_evidence_documents(id) on delete restrict,
  version_number integer not null check (version_number > 0),
  storage_bucket text not null default 'procurement-evidence'
    check (storage_bucket = 'procurement-evidence'),
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
  foreign key (document_id, project_id, organization_id)
    references public.procurement_evidence_documents(id, project_id, organization_id) on delete restrict,
  unique (document_id, version_number),
  unique (storage_bucket, storage_object_name),
  unique (id, project_id, organization_id),
  unique (id, organization_id),
  check (storage_object_name = organization_id::text || '/' || project_id::text || '/'
    || split_part(storage_object_name, '/', 3))
);

create table public.procurement_evidence_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  evidence_version_id uuid not null references public.procurement_evidence_versions(id) on delete restrict,
  purchase_order_id uuid,
  purchase_receipt_id uuid,
  supplier_invoice_id uuid,
  linked_by uuid not null references auth.users(id) on delete restrict,
  linked_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  check (num_nonnulls(purchase_order_id, purchase_receipt_id, supplier_invoice_id) = 1),
  foreign key (evidence_version_id, project_id, organization_id)
    references public.procurement_evidence_versions(id, project_id, organization_id) on delete restrict,
  foreign key (purchase_order_id, project_id, organization_id)
    references public.purchase_orders(id, project_id, organization_id) on delete restrict,
  foreign key (purchase_receipt_id, project_id, organization_id)
    references public.purchase_receipts(id, project_id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict,
  unique (organization_id, idempotency_key),
  unique (evidence_version_id, purchase_order_id),
  unique (evidence_version_id, purchase_receipt_id),
  unique (evidence_version_id, supplier_invoice_id)
);

create index procurement_evidence_documents_project_idx
  on public.procurement_evidence_documents(organization_id, project_id, created_at);
create index procurement_evidence_versions_document_idx
  on public.procurement_evidence_versions(document_id, version_number desc);
create index procurement_evidence_links_order_idx
  on public.procurement_evidence_links(purchase_order_id) where purchase_order_id is not null;
create index procurement_evidence_links_receipt_idx
  on public.procurement_evidence_links(purchase_receipt_id) where purchase_receipt_id is not null;
create index procurement_evidence_links_invoice_idx
  on public.procurement_evidence_links(supplier_invoice_id) where supplier_invoice_id is not null;

create or replace function public.r4_evidence_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'procurement evidence and its links are append-only';
end $$;
create trigger procurement_evidence_documents_append_only
before update or delete on public.procurement_evidence_documents
for each row execute function public.r4_evidence_append_only();
create trigger procurement_evidence_versions_append_only
before update or delete on public.procurement_evidence_versions
for each row execute function public.r4_evidence_append_only();
create trigger procurement_evidence_links_append_only
before update or delete on public.procurement_evidence_links
for each row execute function public.r4_evidence_append_only();

-- One atomic metadata command creates a document (or a new version) and links
-- that exact immutable version to one authoritative Procurement subject.
create or replace function public.register_procurement_evidence(
  p_organization_id uuid,
  p_project_id uuid,
  p_document_id uuid,
  p_classification text,
  p_title text,
  p_storage_object_name text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_sha256 text,
  p_purchase_order_id uuid,
  p_purchase_receipt_id uuid,
  p_supplier_invoice_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_document public.procurement_evidence_documents%rowtype;
  v_existing public.procurement_evidence_links%rowtype;
  v_object record;
  v_storage_size bigint;
  v_storage_mime text;
  v_document_id uuid;
  v_version_id uuid;
  v_link_id uuid;
  v_version_number integer;
  v_hash text;
  v_subject_count integer := num_nonnulls(p_purchase_order_id, p_purchase_receipt_id, p_supplier_invoice_id);
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.investment_projects p
    where p.id=p_project_id and p.organization_id=p_organization_id) then
    raise exception 'project not found';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_classification not in ('CONTRACT','PURCHASE_ORDER','RECEIPT','SUPPLIER_INVOICE') then
    raise exception 'invalid evidence classification';
  end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 200 then raise exception 'invalid evidence title'; end if;
  if p_original_filename is null or char_length(trim(p_original_filename)) not between 1 and 240
     or p_original_filename ~ E'[\\\\/\\n\\r]' then raise exception 'invalid evidence filename'; end if;
  if p_mime_type not in ('application/pdf','image/jpeg','image/png') then raise exception 'unsupported evidence file type'; end if;
  if p_size_bytes is null or p_size_bytes not between 1 and 10485760 then raise exception 'evidence file size is invalid'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid evidence checksum'; end if;
  if p_storage_object_name is null or p_storage_object_name !~
    ('^' || p_organization_id::text || '/' || p_project_id::text || '/[0-9a-f-]{36}$') then
    raise exception 'invalid evidence storage path';
  end if;
  if v_subject_count <> 1 then raise exception 'exactly one procurement evidence subject is required'; end if;

  if p_purchase_order_id is not null then
    if p_classification not in ('CONTRACT','PURCHASE_ORDER') then raise exception 'purchase order requires contract or purchase order evidence'; end if;
    if not exists (select 1 from public.purchase_orders where id=p_purchase_order_id
      and project_id=p_project_id and organization_id=p_organization_id) then raise exception 'purchase order not found'; end if;
  elsif p_purchase_receipt_id is not null then
    if p_classification <> 'RECEIPT' then raise exception 'receipt requires receipt evidence'; end if;
    if not exists (select 1 from public.purchase_receipts where id=p_purchase_receipt_id
      and project_id=p_project_id and organization_id=p_organization_id) then raise exception 'purchase receipt not found'; end if;
  else
    if p_classification <> 'SUPPLIER_INVOICE' then raise exception 'supplier invoice requires invoice evidence'; end if;
    if not exists (select 1 from public.supplier_invoices where id=p_supplier_invoice_id
      and project_id=p_project_id and organization_id=p_organization_id) then raise exception 'supplier invoice not found'; end if;
  end if;

  v_hash := encode(digest(
    p_project_id::text || '|' || coalesce(p_document_id::text,'') || '|' || p_classification || '|'
    || trim(p_title) || '|' || p_storage_object_name || '|' || trim(p_original_filename) || '|'
    || p_mime_type || '|' || p_size_bytes::text || '|' || lower(p_sha256) || '|'
    || coalesce(p_purchase_order_id::text,'') || '|' || coalesce(p_purchase_receipt_id::text,'') || '|'
    || coalesce(p_supplier_invoice_id::text,''), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r4-evidence:' || trim(p_idempotency_key), 0));

  -- The Storage catalog is authoritative for object existence and transport
  -- metadata. Lock the row through this transaction: an unregistered-object
  -- delete racing registration must finish first, or wait and then be denied
  -- once the immutable version exists.
  select o.bucket_id,o.name,o.metadata into v_object
    from storage.objects o
   where o.bucket_id='procurement-evidence' and o.name=p_storage_object_name
   for share;
  if not found then raise exception 'procurement evidence storage object not found'; end if;
  if coalesce(v_object.metadata->>'size','') !~ '^[0-9]+$' then
    raise exception 'procurement evidence storage object has invalid size metadata';
  end if;
  v_storage_size := (v_object.metadata->>'size')::bigint;
  v_storage_mime := lower(coalesce(v_object.metadata->>'mimetype',''));
  if v_storage_size is distinct from p_size_bytes then
    raise exception 'procurement evidence size does not match storage object';
  end if;
  if v_storage_mime is distinct from lower(p_mime_type) then
    raise exception 'procurement evidence MIME type does not match storage object';
  end if;

  select * into v_existing from public.procurement_evidence_links
    where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if p_document_id is null then
    insert into public.procurement_evidence_documents(
      organization_id,project_id,classification,title,created_by
    ) values (p_organization_id,p_project_id,p_classification,trim(p_title),v_actor)
    returning id into v_document_id;
    v_version_number := 1;
  else
    select * into v_document from public.procurement_evidence_documents
      where id=p_document_id and project_id=p_project_id and organization_id=p_organization_id for update;
    if not found then raise exception 'evidence document not found'; end if;
    if v_document.classification <> p_classification or v_document.title <> trim(p_title) then
      raise exception 'document identity and classification are immutable across versions';
    end if;
    v_document_id := v_document.id;
    select coalesce(max(version_number),0)+1 into v_version_number
      from public.procurement_evidence_versions where document_id=v_document_id;
  end if;

  insert into public.procurement_evidence_versions(
    organization_id,project_id,document_id,version_number,storage_object_name,
    original_filename,mime_type,size_bytes,sha256,uploaded_by
  ) values (
    p_organization_id,p_project_id,v_document_id,v_version_number,p_storage_object_name,
    trim(p_original_filename),p_mime_type,p_size_bytes,lower(p_sha256),v_actor
  ) returning id into v_version_id;

  insert into public.procurement_evidence_links(
    organization_id,project_id,evidence_version_id,purchase_order_id,purchase_receipt_id,
    supplier_invoice_id,linked_by,idempotency_key,request_hash
  ) values (
    p_organization_id,p_project_id,v_version_id,p_purchase_order_id,p_purchase_receipt_id,
    p_supplier_invoice_id,v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_link_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id,v_actor,'PROCUREMENT_EVIDENCE_LINKED','procurement_evidence_version',v_version_id,
    jsonb_build_object('project_id',p_project_id,'document_id',v_document_id,'version_number',v_version_number,
      'classification',p_classification,'sha256',lower(p_sha256),'size_bytes',p_size_bytes,
      'purchase_order_id',p_purchase_order_id,'purchase_receipt_id',p_purchase_receipt_id,
      'supplier_invoice_id',p_supplier_invoice_id));
  return v_link_id;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Approval gates. Commercial references remain useful labels, but actual
--    evidence now means a registered immutable file version.
-- ---------------------------------------------------------------------------
create or replace function public.r4_require_purchase_order_evidence()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status='SUBMITTED' and new.status='APPROVED' and not exists (
    select 1 from public.procurement_evidence_links l
    join public.procurement_evidence_versions v on v.id=l.evidence_version_id
    join public.procurement_evidence_documents d on d.id=v.document_id
    join storage.objects o
      on o.bucket_id=v.storage_bucket and o.name=v.storage_object_name
    where l.purchase_order_id=new.id and l.organization_id=new.organization_id
      and d.classification in ('CONTRACT','PURCHASE_ORDER')
      and case when coalesce(o.metadata->>'size','') ~ '^[0-9]+$'
        then (o.metadata->>'size')::bigint else null end = v.size_bytes
      and lower(coalesce(o.metadata->>'mimetype',''))=v.mime_type
  ) then raise exception 'purchase order approval requires an immutable contract or purchase order file'; end if;
  return new;
end $$;
create trigger r4_purchase_order_evidence_gate
before update of status on public.purchase_orders
for each row execute function public.r4_require_purchase_order_evidence();

create or replace function public.r4_require_supplier_invoice_evidence()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status='SUBMITTED' and new.status='APPROVED' then
    if not exists (
      select 1 from public.procurement_evidence_links l
      join public.procurement_evidence_versions v on v.id=l.evidence_version_id
      join public.procurement_evidence_documents d on d.id=v.document_id
      join storage.objects o
        on o.bucket_id=v.storage_bucket and o.name=v.storage_object_name
      where l.supplier_invoice_id=new.id and l.organization_id=new.organization_id
        and d.classification='SUPPLIER_INVOICE'
        and case when coalesce(o.metadata->>'size','') ~ '^[0-9]+$'
          then (o.metadata->>'size')::bigint else null end = v.size_bytes
        and lower(coalesce(o.metadata->>'mimetype',''))=v.mime_type
    ) then raise exception 'supplier invoice approval requires an immutable invoice file'; end if;
    if exists (
      select 1 from public.supplier_invoice_lines il
      join public.purchase_receipt_lines rl on rl.id=il.purchase_receipt_line_id
      where il.supplier_invoice_id=new.id and not exists (
        select 1 from public.procurement_evidence_links l
        join public.procurement_evidence_versions v on v.id=l.evidence_version_id
        join public.procurement_evidence_documents d on d.id=v.document_id
        join storage.objects o
          on o.bucket_id=v.storage_bucket and o.name=v.storage_object_name
        where l.purchase_receipt_id=rl.purchase_receipt_id
          and l.organization_id=new.organization_id and d.classification='RECEIPT'
          and case when coalesce(o.metadata->>'size','') ~ '^[0-9]+$'
            then (o.metadata->>'size')::bigint else null end = v.size_bytes
          and lower(coalesce(o.metadata->>'mimetype',''))=v.mime_type
      )
    ) then raise exception 'supplier invoice approval requires immutable evidence for every matched receipt'; end if;
  end if;
  return new;
end $$;
create trigger r4_supplier_invoice_evidence_gate
before update of status on public.supplier_invoices
for each row execute function public.r4_require_supplier_invoice_evidence();

-- ---------------------------------------------------------------------------
-- 4. RLS, object access and audit-ready read model.
-- ---------------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['procurement_evidence_documents','procurement_evidence_versions','procurement_evidence_links'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
  end loop;
end $$;
revoke all on public.procurement_evidence_documents, public.procurement_evidence_versions,
  public.procurement_evidence_links from public,anon,authenticated;
grant select on public.procurement_evidence_documents, public.procurement_evidence_versions,
  public.procurement_evidence_links to authenticated;

create policy procurement_evidence_object_read on storage.objects
for select to authenticated using (
  bucket_id='procurement-evidence' and exists (
    select 1 from public.procurement_evidence_versions v
    where v.storage_bucket=storage.objects.bucket_id and v.storage_object_name=storage.objects.name
      and public.is_active_member(v.organization_id)
  )
);
create policy procurement_evidence_unregistered_delete on storage.objects
for delete to authenticated using (
  bucket_id='procurement-evidence'
  and public.r4_can_upload_evidence_object(name)
  and not exists (select 1 from public.procurement_evidence_versions v
    where v.storage_bucket=storage.objects.bucket_id and v.storage_object_name=storage.objects.name)
);

create or replace view public.procurement_evidence_read with (security_invoker=on) as
select l.id as evidence_link_id,l.organization_id,l.project_id,d.id as document_id,
  v.id as evidence_version_id,d.classification,d.title,v.version_number,
  v.original_filename,v.mime_type,v.size_bytes::text as size_bytes,v.sha256,
  v.storage_bucket,v.storage_object_name,v.uploaded_by,v.uploaded_at,
  l.purchase_order_id,l.purchase_receipt_id,l.supplier_invoice_id,l.linked_by,l.linked_at
from public.procurement_evidence_links l
join public.procurement_evidence_versions v on v.id=l.evidence_version_id
join public.procurement_evidence_documents d on d.id=v.document_id;
grant select on public.procurement_evidence_read to authenticated;

revoke all on function public.register_procurement_evidence(
  uuid,uuid,uuid,text,text,text,text,text,bigint,text,uuid,uuid,uuid,text
) from public,anon;
grant execute on function public.register_procurement_evidence(
  uuid,uuid,uuid,text,text,text,text,text,bigint,text,uuid,uuid,uuid,text
) to authenticated;

-- Hosted Supabase commonly installs pgcrypto in `extensions`, while disposable
-- PostgreSQL may install it in `public`. Keep the SECURITY DEFINER search path
-- narrow and qualify digest at migration time for the actual extension schema.
do $pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
begin
  select n.nspname into v_pgcrypto_schema
    from pg_extension e join pg_namespace n on n.oid=e.extnamespace
   where e.extname='pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;
  select pg_get_functiondef(p.oid) into v_definition
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='register_procurement_evidence' and p.prokind='f';
  if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
    v_rewritten := regexp_replace(v_definition,
      '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
      E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(', 'g');
    if v_rewritten=v_definition then raise exception 'failed to qualify pgcrypto digest in R4 evidence command'; end if;
    execute v_rewritten;
  end if;
end
$pgcrypto_compat$;

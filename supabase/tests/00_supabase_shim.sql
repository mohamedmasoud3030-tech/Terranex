create schema if not exists auth;
create table if not exists auth.users(id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create role authenticated nologin; create role anon nologin;

-- Minimal Supabase Storage catalog used only by disposable PostgreSQL replay.
-- Hosted Supabase already supplies this schema, tables and foldername helper.
create schema if not exists storage;
create table if not exists storage.buckets(
  id text primary key,
  name text not null unique,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table if not exists storage.objects(
  id uuid primary key,
  bucket_id text not null references storage.buckets(id),
  name text not null,
  owner_id text,
  metadata jsonb,
  created_at timestamptz not null default now(),
  unique(bucket_id,name)
);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text)
returns text[] language sql immutable as $$
  select case when array_length(string_to_array(name,'/'),1)>1
    then (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1]
    else array[]::text[] end
$$;
grant usage on schema storage to authenticated,anon;
grant select,insert,update,delete on storage.objects to authenticated;

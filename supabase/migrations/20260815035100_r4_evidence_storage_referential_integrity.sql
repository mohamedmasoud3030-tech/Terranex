-- R4 evidence storage referential-integrity hardening.
--
-- A registered immutable evidence version must never outlive the exact private
-- Storage object it proves. The registration RPC already locks and validates
-- storage.objects, but a DELETE statement that started before registration
-- could otherwise pass its RLS snapshot, wait on that row lock, then delete the
-- object after registration commits. The database FK closes that MVCC race at
-- the final write boundary.

-- Hosted Supabase Storage (versioned objects) no longer keeps a unique
-- (bucket_id, name) constraint on storage.objects, so the FK can only be
-- created where such a key exists (self-hosted/older Storage and the CI shim).
-- Elsewhere the registration RPC's own lock and validation of storage.objects
-- remain the guard, and this migration is a no-op.
do $r4fk$
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
    alter table public.procurement_evidence_versions
      add constraint procurement_evidence_versions_storage_object_fk
      foreign key (storage_bucket, storage_object_name)
      references storage.objects(bucket_id, name)
      on update restrict
      on delete restrict;
    comment on constraint procurement_evidence_versions_storage_object_fk
      on public.procurement_evidence_versions is
      'Registered procurement evidence cannot become orphaned from its immutable private Storage object, including concurrent registration/delete races.';
  else
    raise notice 'storage.objects has no unique (bucket_id, name); evidence FK skipped';
  end if;
end
$r4fk$;

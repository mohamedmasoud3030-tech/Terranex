-- R4 evidence storage referential-integrity hardening.
--
-- A registered immutable evidence version must never outlive the exact private
-- Storage object it proves. The registration RPC already locks and validates
-- storage.objects, but a DELETE statement that started before registration
-- could otherwise pass its RLS snapshot, wait on that row lock, then delete the
-- object after registration commits. The database FK closes that MVCC race at
-- the final write boundary.

alter table public.procurement_evidence_versions
  add constraint procurement_evidence_versions_storage_object_fk
  foreign key (storage_bucket, storage_object_name)
  references storage.objects(bucket_id, name)
  on update restrict
  on delete restrict;

comment on constraint procurement_evidence_versions_storage_object_fk
  on public.procurement_evidence_versions is
  'Registered procurement evidence cannot become orphaned from its immutable private Storage object, including concurrent registration/delete races.';

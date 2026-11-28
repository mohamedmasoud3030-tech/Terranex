import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20261128010000_livestock_cohort_media.sql');
const gate = read('supabase/tests/74_livestock_cohort_media.sql');

describe('livestock cohort media', () => {
  it('keeps media in a private bucket with a photo and video envelope', () => {
    expect(migration).toContain("select 'livestock-media'::text");
    for (const mime of ['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/webm']) {
      expect(migration).toContain(`'${mime}'`);
    }
    expect(migration).toContain('select 52428800::bigint');
    expect(migration).toContain('livestock_media_can_upload_object');
    expect(migration).toContain('bucket_id = public.livestock_media_bucket()');
  });

  it('ties every media document to one cohort inside the same project and organization', () => {
    expect(migration).toContain('add column livestock_cohort_id uuid');
    expect(migration).toContain('references public.livestock_cohorts(id, organization_id, project_id)');
    expect(migration).toContain('livestock_cohort_id is null or project_id is not null');
  });

  it('registers through one authenticated command that validates storage truth', () => {
    expect(migration).toContain('create or replace function public.register_livestock_cohort_media(');
    expect(migration).toContain('security definer set search_path=pg_catalog,public');
    expect(migration).toContain('where o.bucket_id = public.livestock_media_bucket() and o.name=p_storage_object_name');
    expect(migration).toContain('media size does not match storage object');
    expect(migration).toContain('media MIME type does not match storage object');
    expect(migration).toContain("raise exception 'livestock cohort not found'");
    expect(migration).toContain("raise exception 'forbidden'");
    expect(migration).toContain("raise exception 'idempotency key payload mismatch'");
    expect(migration).toContain('revoke all on function public.register_livestock_cohort_media');
    expect(migration).toContain('to authenticated;');
  });

  it('never creates a quantity, money or valuation fact', () => {
    expect(migration).not.toMatch(/insert into public\.livestock_quantity_events/);
    expect(migration).not.toMatch(/insert into public\.journal_(batches|lines)/);
    expect(migration).not.toMatch(/livestock_cohort_cost_attributions/);
    expect(migration).not.toMatch(/update public\.livestock_cohorts/);
  });

  it('exposes a tenant-scoped read view', () => {
    expect(migration).toContain('create view public.livestock_cohort_media_read with (security_invoker=on)');
    expect(migration).toContain('where v.storage_bucket = public.livestock_media_bucket()');
    expect(migration).toContain('grant select on public.livestock_cohort_media_read to authenticated');
    expect(migration).toContain('revoke all on public.livestock_cohort_media_read from public,anon');
  });

  it('proves the boundary in the disposable database gate', () => {
    expect(gate).toContain('LCM_OK');
    expect(gate).toContain('livestock cohort not found');
    expect(gate).toContain("'%forbidden%'");
    expect(gate).toContain('unsupported media file type');
    expect(gate).toContain('media file size is invalid');
    expect(gate).toContain('media changed the quantity ledger');
    expect(gate).toContain('replay created a second version');
  });
});

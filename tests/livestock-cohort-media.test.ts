import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync('supabase/migrations/20261128010000_livestock_cohort_media.sql', 'utf8');
const gate = readFileSync('supabase/tests/74_livestock_cohort_media.sql', 'utf8');

const present = (source: string, needles: string[]) => {
  const missing = needles.filter((needle) => !source.includes(needle));
  expect(missing).toEqual([]);
};

describe('livestock cohort media', () => {
  it('keeps media in a private bucket with a photo and video envelope', () => {
    present(migration, [
      "select 'livestock-media'::text",
      'select 52428800::bigint',
      'livestock_media_can_upload_object',
      'bucket_id = public.livestock_media_bucket()',
    ]);
    for (const mime of ['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/webm']) {
      expect(migration).toContain(`'${mime}'`);
    }
  });

  it('ties every media document to one cohort inside the same project and organization', () => {
    present(migration, [
      'add column livestock_cohort_id uuid',
      'references public.livestock_cohorts(id, organization_id, project_id)',
      'livestock_cohort_id is null or project_id is not null',
    ]);
  });

  it('registers through one authenticated command that validates storage truth', () => {
    present(migration, [
      'create or replace function public.register_livestock_cohort_media(',
      'security definer set search_path=pg_catalog,public',
      'from storage.objects o',
      'for share',
      'media object does not match the declared file',
      "raise exception 'livestock cohort not found'",
      "raise exception 'forbidden'",
      "raise exception 'idempotency key payload mismatch'",
      'revoke all on function public.register_livestock_cohort_media',
      'to authenticated;',
    ]);
  });

  it('never creates a quantity, money or valuation fact', () => {
    expect(migration).not.toMatch(/insert into public\.livestock_quantity_events/);
    expect(migration).not.toMatch(/insert into public\.journal_(batches|lines)/);
    expect(migration).not.toMatch(/livestock_cohort_cost_attributions/);
    expect(migration).not.toMatch(/update public\.livestock_cohorts/);
  });

  it('exposes a tenant-scoped read view', () => {
    present(migration, [
      'create view public.livestock_cohort_media_read with (security_invoker=on)',
      'where v.storage_bucket = public.livestock_media_bucket()',
      'grant select on public.livestock_cohort_media_read to authenticated',
      'revoke all on public.livestock_cohort_media_read from public,anon',
    ]);
  });

  it('proves the boundary in the disposable database gate', () => {
    present(gate, [
      'LCM_OK',
      'livestock cohort not found',
      "'%forbidden%'",
      'unsupported media file type',
      'media file size is invalid',
      'media changed the quantity ledger',
      'replay created a second version',
    ]);
  });
});

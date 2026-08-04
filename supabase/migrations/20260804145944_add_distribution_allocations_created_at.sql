alter table public.distribution_allocations
  add column if not exists created_at timestamptz not null default now();

comment on column public.distribution_allocations.created_at is
  'Creation timestamp used for deterministic ordering and UI portfolio queries.';

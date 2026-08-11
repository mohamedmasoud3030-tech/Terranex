-- GF-004 / S2 integrity hardening discovered during independent PR review.
--
-- Two invariants are enforced here at the database boundary:
--   1) a payment can only be inserted while its obligation authorization has
--      an active (non-reversed) journal posting;
--   2) the one-active-posting-per-source rule is safe under concurrent
--      requests even when the callers use different idempotency keys.

-- Serialize by financial source, not only by request idempotency key. Without
-- this source-scoped lock, two transactions using different retry keys can
-- both pass the BEFORE INSERT existence check before either commits.
create or replace function public.s2_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT') then
    perform pg_advisory_xact_lock(hashtextextended(
      's2-active-source:' || new.organization_id::text || ':' || new.source_type || ':' || new.source_id::text,
      0
    ));

    if exists (
      select 1 from public.journal_batches jb
      where jb.source_type = new.source_type
        and jb.source_id = new.source_id
        and jb.organization_id = new.organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then
      raise exception 'source already has an active posting';
    end if;
  end if;
  return new;
end $$;

-- Defense in depth for the payment lifecycle. The original obligation row is
-- intentionally immutable and remains AUTHORIZED after its journal batch is
-- reversed, so status alone cannot prove that the authorization is active.
-- Every payment insert therefore verifies the journal relationship itself.
create or replace function public.s2_guard_payment_requires_active_obligation_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1
    from public.journal_batches jb
    where jb.organization_id = new.organization_id
      and jb.project_id = new.project_id
      and jb.source_type = 'COST_OBLIGATION'
      and jb.source_id = new.obligation_id
      and not exists (
        select 1 from public.journal_batches rb
        where rb.reversal_of_batch_id = jb.id
      )
  ) then
    raise exception 'payment requires an active obligation authorization posting';
  end if;
  return new;
end $$;

drop trigger if exists project_payments_active_obligation_guard on public.project_payments;
create trigger project_payments_active_obligation_guard
before insert on public.project_payments
for each row execute function public.s2_guard_payment_requires_active_obligation_posting();

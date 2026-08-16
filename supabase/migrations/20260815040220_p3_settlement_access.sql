-- P3 — read models, tenant isolation, command grants, pgcrypto compatibility.

create view public.unapplied_payments_read with (security_invoker=on) as
select p.id as unapplied_payment_id,p.organization_id,p.project_id,p.party_id,
       party.legal_name as party_name,p.cash_account_id,ca.name as cash_account_name,
       p.amount_minor_units::text as amount_minor_units,p.currency,p.payment_date,
       p.description,p.evidence_reference,p.journal_batch_id,p.recorded_by,p.recorded_at,
       coalesce(a.allocated_minor_units,0)::text as allocated_minor_units,
       coalesce(sa.applied_minor_units,0)::text as advance_applied_minor_units,
       greatest(p.amount_minor_units-coalesce(a.allocated_minor_units,0)-coalesce(sa.applied_minor_units,0),0)::text as remaining_minor_units
from public.unapplied_payments p
join public.project_cash_accounts ca on ca.id=p.cash_account_id and ca.organization_id=p.organization_id
join public.parties party on party.id=p.party_id and party.organization_id=p.organization_id
left join (
  select unapplied_payment_id,sum(allocated_minor_units) as allocated_minor_units
  from public.payment_allocations pa
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=pa.journal_batch_id)
  group by unapplied_payment_id
) a on a.unapplied_payment_id=p.id
left join (
  select adv.unapplied_payment_id,sum(app.applied_amount_minor_units) as applied_minor_units
  from public.supplier_advances adv
  join public.supplier_advance_applications app on app.advance_id=adv.id
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=app.journal_batch_id)
  group by adv.unapplied_payment_id
) sa on sa.unapplied_payment_id=p.id;

create view public.payment_allocations_read with (security_invoker=on) as
select pa.id as allocation_id,pa.organization_id,pa.project_id,pa.unapplied_payment_id,
       pa.obligation_id,pa.allocated_minor_units::text as allocated_minor_units,pa.currency,
       pa.allocation_date,pa.journal_batch_id,pa.allocated_by,pa.allocated_at
from public.payment_allocations pa;

create view public.supplier_advances_read with (security_invoker=on) as
select a.id as advance_id,a.organization_id,a.project_id,a.supplier_party_id,
       p.legal_name as supplier_name,a.advance_reference,a.advance_date,a.currency,
       a.amount_minor_units::text as amount_minor_units,
       coalesce(x.applied_minor_units,0)::text as applied_minor_units,
       greatest(a.amount_minor_units-coalesce(x.applied_minor_units,0),0)::text as remaining_minor_units,
       case when coalesce(x.applied_minor_units,0)=0 then 'UNAPPLIED'
            when coalesce(x.applied_minor_units,0)<a.amount_minor_units then 'PARTIALLY_APPLIED'
            else 'FULLY_APPLIED' end as status,
       a.unapplied_payment_id,a.recorded_by,a.recorded_at
from public.supplier_advances a
join public.parties p on p.id=a.supplier_party_id and p.organization_id=a.organization_id
left join (
  select advance_id,sum(applied_amount_minor_units) as applied_minor_units
  from public.supplier_advance_applications app
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=app.journal_batch_id)
  group by advance_id
) x on x.advance_id=a.id;

create view public.supplier_advance_applications_read with (security_invoker=on) as
select app.id as application_id,app.organization_id,app.project_id,app.advance_id,
       app.supplier_invoice_id,app.obligation_id,
       app.applied_amount_minor_units::text as applied_amount_minor_units,app.currency,
       app.application_date,app.journal_batch_id,app.applied_by,app.applied_at
from public.supplier_advance_applications app;

create view public.supplier_credit_notes_read with (security_invoker=on) as
select c.id as credit_note_id,c.organization_id,c.project_id,c.supplier_invoice_id,c.obligation_id,
       c.credit_reference,c.credit_date,c.currency,c.amount_minor_units::text as amount_minor_units,
       c.reason,c.evidence_reference,c.status,c.authorization_batch_id,
       c.recorded_by,c.recorded_at,c.approved_by,c.approved_at
from public.supplier_credit_notes c;

do $$ declare t text; begin
  foreach t in array array[
    'unapplied_payments','payment_allocations','supplier_advances',
    'supplier_advance_applications','supplier_credit_notes'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

grant select on public.unapplied_payments_read,public.payment_allocations_read,
  public.supplier_advances_read,public.supplier_advance_applications_read,
  public.supplier_credit_notes_read to authenticated;

revoke all on function public.record_unapplied_payment(uuid,uuid,uuid,uuid,bigint,text,date,text,text,text) from public,anon;
revoke all on function public.allocate_payment(uuid,uuid,uuid,bigint,date,text) from public,anon;
revoke all on function public.record_supplier_advance(uuid,uuid,uuid,uuid,text,date,text,bigint,text,text,text) from public,anon;
revoke all on function public.apply_supplier_advance(uuid,uuid,uuid,bigint,date,text) from public,anon;
revoke all on function public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text) from public,anon;
revoke all on function public.approve_supplier_credit_note(uuid,uuid,text) from public,anon;

grant execute on function public.record_unapplied_payment(uuid,uuid,uuid,uuid,bigint,text,date,text,text,text) to authenticated;
grant execute on function public.allocate_payment(uuid,uuid,uuid,bigint,date,text) to authenticated;
grant execute on function public.record_supplier_advance(uuid,uuid,uuid,uuid,text,date,text,bigint,text,text,text) to authenticated;
grant execute on function public.apply_supplier_advance(uuid,uuid,uuid,bigint,date,text) to authenticated;
grant execute on function public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text) to authenticated;
grant execute on function public.approve_supplier_credit_note(uuid,uuid,text) to authenticated;

revoke all on function public.p3_guard_append_only(),public.p3_guard_credit_note_transition(),
  public.obligation_active_outstanding_minor_units(uuid,uuid),public.p3_guard_project_payment_settlement()
  from public,anon,authenticated;

-- Hosted Supabase may install pgcrypto outside public. Qualify digest() in the
-- P3 commands after their definitions, following existing repository practice.
do $pgcrypto_compat_p3$
declare
  v_pgcrypto_schema text; v_record record; v_definition text; v_rewritten text;
  v_commands text[]:=array[
    'record_unapplied_payment','allocate_payment','record_supplier_advance',
    'apply_supplier_advance','record_supplier_credit_note','approve_supplier_credit_note'
  ];
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace
  where e.extname='pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;
  for v_record in
    select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname=any(v_commands::text[])
  loop
    v_definition:=pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten:=regexp_replace(v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1'||quote_ident(v_pgcrypto_schema)||'.digest(','g');
      if v_rewritten=v_definition then raise exception 'failed to qualify pgcrypto digest in %',v_record.proname; end if;
      execute v_rewritten;
    end if;
  end loop;
end
$pgcrypto_compat_p3$;

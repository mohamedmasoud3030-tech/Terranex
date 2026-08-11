-- GF-006 / S4 — Revenue & Realized Result vertical slice.
-- Delivers: disposition lifecycle, revenue recognition on control transfer,
-- carrying-cost derecognition, collection lifecycle, and realized project result.
-- No allocation, distribution, period close, or external GL in this slice.

-- 1. Project lifecycle gains EXITING (entered when a disposition is confirmed).
alter table public.investment_projects
  drop constraint if exists investment_projects_lifecycle_state_check;
alter table public.investment_projects
  add constraint investment_projects_lifecycle_state_check
  check (lifecycle_state in ('DRAFT','FUNDING','OPERATING','EXITING','CLOSED'));

-- 2. Dispositions: sale/disposal of property assets with explicit lifecycle.
create table if not exists public.dispositions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null references public.property_assets(id) on delete restrict,
  buyer_party_id uuid not null references public.parties(id) on delete restrict,
  status text not null default 'DRAFT' check (status in (
    'DRAFT','APPROVED','CONTROL_TRANSFERRED','SETTLED','CANCELLED'
  )),
  agreed_proceeds_minor_units bigint not null check (agreed_proceeds_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  agreement_date date not null,
  control_transfer_date date,
  selling_costs_minor_units bigint not null default 0 check (selling_costs_minor_units >= 0),
  contract_reference text,
  evidence_document_ids jsonb,
  recognized_at timestamptz,
  recognized_by uuid references auth.users(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, property_asset_id)
    references public.property_assets(organization_id, id) on delete restrict,
  foreign key (organization_id, buyer_party_id)
    references public.parties(organization_id, id) on delete restrict
);
create index if not exists dispositions_project_idx on public.dispositions(project_id);
create index if not exists dispositions_asset_idx on public.dispositions(property_asset_id);

-- 3. Sale recognition: immutable business facts with balanced postings.
create table if not exists public.sale_recognitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  disposition_id uuid not null references public.dispositions(id) on delete restrict,
  recognized_revenue_minor_units bigint not null check (recognized_revenue_minor_units > 0),
  derecognized_carrying_cost_minor_units bigint not null check (derecognized_carrying_cost_minor_units >= 0),
  selling_costs_minor_units bigint not null default 0 check (selling_costs_minor_units >= 0),
  realized_result_minor_units bigint not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  control_transfer_date date not null,
  revenue_journal_batch_id uuid not null references public.journal_batches(id) on delete restrict,
  cost_derecognition_journal_batch_id uuid references public.journal_batches(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  recognized_by uuid references auth.users(id) on delete restrict,
  recognized_at timestamptz not null default now(),
  unique (disposition_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, disposition_id)
    references public.dispositions(organization_id, id) on delete restrict,
  foreign key (organization_id, revenue_journal_batch_id)
    references public.journal_batches(organization_id, id) on delete restrict,
  foreign key (organization_id, cost_derecognition_journal_batch_id)
    references public.journal_batches(organization_id, id) on delete restrict
);

-- 4. Receivables: derived from sale recognitions minus collections.
create table if not exists public.sale_receivables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  sale_recognition_id uuid not null references public.sale_recognitions(id) on delete restrict,
  receivable_minor_units bigint not null check (receivable_minor_units >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'OUTSTANDING' check (status in ('OUTSTANDING','PARTIAL','COLLECTED')),
  created_at timestamptz not null default now(),
  unique (sale_recognition_id),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, sale_recognition_id)
    references public.sale_recognitions(organization_id, id) on delete restrict
);

-- 5. Collections: append-only cash receipts against receivables.
create table if not exists public.collections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  sale_receivable_id uuid not null references public.sale_receivables(id) on delete restrict,
  collection_minor_units bigint not null check (collection_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  collected_on date not null,
  cash_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  journal_batch_id uuid not null references public.journal_batches(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  collected_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, sale_receivable_id)
    references public.sale_receivables(organization_id, id) on delete restrict,
  foreign key (organization_id, cash_account_id)
    references public.financial_accounts(organization_id, id) on delete restrict,
  foreign key (organization_id, journal_batch_id)
    references public.journal_batches(organization_id, id) on delete restrict
);
create index if not exists collections_receivable_idx on public.collections(sale_receivable_id);

-- 6. RLS: default deny, member reads, no browser writes.
alter table public.dispositions enable row level security;
alter table public.sale_recognitions enable row level security;
alter table public.sale_receivables enable row level security;
alter table public.collections enable row level security;
alter table public.dispositions force row level security;
alter table public.sale_recognitions force row level security;
alter table public.sale_receivables force row level security;
alter table public.collections force row level security;

create policy dispositions_read on public.dispositions for select to authenticated
  using (public.is_active_member(organization_id));
create policy sale_recognitions_read on public.sale_recognitions for select to authenticated
  using (public.is_active_member(organization_id));
create policy sale_receivables_read on public.sale_receivables for select to authenticated
  using (public.is_active_member(organization_id));
create policy collections_read on public.collections for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.dispositions, public.sale_recognitions, public.sale_receivables,
  public.collections from anon, authenticated;
grant select on public.dispositions, public.sale_recognitions, public.sale_receivables,
  public.collections to authenticated;

-- 7. Immutability guards.
create or replace function public.s4_guard_disposition_lifecycle() returns trigger
language plpgsql as $$
begin
  if old is not null and old.status in ('CONTROL_TRANSFERRED','SETTLED') then
    if new.status <> old.status and new.status <> 'CANCELLED' then
      raise exception 'disposition is immutable after control transfer except via cancellation';
    end if;
  end if;
  if old is not null and old.status = 'CANCELLED' then
    raise exception 'cancelled disposition cannot be modified';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists disposition_lifecycle_guard on public.dispositions;
create trigger disposition_lifecycle_guard before update on public.dispositions
  for each row execute function public.s4_guard_disposition_lifecycle();

create or replace function public.s4_guard_append_only() returns trigger
language plpgsql as $$
begin
  raise exception using
    message = case tg_table_name
      when 'sale_recognitions' then 'sale recognitions are immutable business facts'
      when 'collections' then 'collections are append-only posted facts'
      else 'record is append-only' end,
    errcode = 'P0001';
end $$;

drop trigger if exists sale_recognitions_immutable on public.sale_recognitions;
create trigger sale_recognitions_immutable before update or delete on public.sale_recognitions
  for each row execute function public.s4_guard_append_only();
drop trigger if exists collections_immutable on public.collections;
create trigger collections_immutable before update or delete on public.collections
  for each row execute function public.s4_guard_append_only();

-- 8. Prevent double-sale: asset cannot be sold twice without explicit reversal.
create or replace function public.s4_guard_no_double_sale() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if exists (
    select 1 from public.dispositions d
    join public.sale_recognitions sr on sr.disposition_id = d.id
    where d.property_asset_id = new.property_asset_id
      and d.organization_id = new.organization_id
      and d.status in ('CONTROL_TRANSFERRED','SETTLED')
  ) then
    raise exception 'property asset already sold; reversal required before re-sale';
  end if;
  return new;
end $$;

drop trigger if exists no_double_sale_guard on public.dispositions;
create trigger no_double_sale_guard before insert on public.dispositions
  for each row execute function public.s4_guard_no_double_sale();

-- 9. Read views: cast int8 to text for exact JavaScript transport.
create or replace view public.dispositions_read with (security_invoker=on) as
select id, organization_id, project_id, property_asset_id, buyer_party_id, status,
       agreed_proceeds_minor_units::text as agreed_proceeds_minor_units, currency,
       agreement_date, control_transfer_date,
       selling_costs_minor_units::text as selling_costs_minor_units,
       contract_reference, evidence_document_ids, recognized_at, created_at
from public.dispositions;

create or replace view public.sale_recognitions_read with (security_invoker=on) as
select id, organization_id, project_id, disposition_id,
       recognized_revenue_minor_units::text as recognized_revenue_minor_units,
       derecognized_carrying_cost_minor_units::text as derecognized_carrying_cost_minor_units,
       selling_costs_minor_units::text as selling_costs_minor_units,
       realized_result_minor_units::text as realized_result_minor_units,
       currency, control_transfer_date, recognized_at
from public.sale_recognitions;

create or replace view public.sale_receivables_read with (security_invoker=on) as
select id, organization_id, project_id, sale_recognition_id,
       receivable_minor_units::text as receivable_minor_units, currency, status, created_at
from public.sale_receivables;

create or replace view public.collections_read with (security_invoker=on) as
select id, organization_id, project_id, sale_receivable_id,
       collection_minor_units::text as collection_minor_units, currency, collected_on, created_at
from public.collections;

-- 10. Realized project result: authoritative read model from posted facts.
create or replace view public.project_realized_result with (security_invoker=on) as
select
  p.organization_id,
  p.id as project_id,
  p.reporting_currency as currency,
  coalesce(sum(sr.recognized_revenue_minor_units), 0) as recognized_revenue_minor_units,
  coalesce(sum(sr.derecognized_carrying_cost_minor_units), 0) as derecognized_carrying_cost_minor_units,
  coalesce(sum(sr.selling_costs_minor_units), 0) as selling_costs_minor_units,
  coalesce(sum(sr.realized_result_minor_units), 0) as realized_result_minor_units,
  coalesce(sum(c.collection_minor_units), 0) as collected_cash_minor_units,
  coalesce(sum(sr.recognized_revenue_minor_units), 0) -
    coalesce(sum(c.collection_minor_units), 0) as outstanding_receivable_minor_units
from public.investment_projects p
left join public.sale_recognitions sr
  on sr.project_id = p.id and sr.organization_id = p.organization_id
left join public.sale_receivables srec
  on srec.sale_recognition_id = sr.id and srec.organization_id = p.organization_id
left join public.collections c
  on c.sale_receivable_id = srec.id and c.organization_id = p.organization_id
group by p.organization_id, p.id, p.reporting_currency;

-- 11. Latest management valuation per project (separate from realized result).
create or replace view public.project_latest_valuation with (security_invoker=on) as
select distinct on (pv.project_id, pv.organization_id)
  pv.organization_id,
  pv.project_id,
  pv.id as valuation_id,
  pv.effective_date,
  pv.valuer_source,
  pv.method,
  pv.valuation_minor_units,
  pv.currency,
  pv.confidence,
  pv.status,
  pv.approved_at
from public.property_valuations pv
where pv.status = 'APPROVED'
order by pv.project_id, pv.organization_id, pv.effective_date desc, pv.created_at desc;

grant select on public.dispositions_read, public.sale_recognitions_read,
  public.sale_receivables_read, public.collections_read,
  public.project_realized_result, public.project_latest_valuation to authenticated;

-- 12. Server-authoritative commands.
create or replace function public.create_disposition(
  p_organization_id uuid,
  p_project_id uuid,
  p_property_asset_id uuid,
  p_buyer_party_id uuid,
  p_agreed_proceeds_minor_units bigint,
  p_currency text,
  p_agreement_date date,
  p_selling_costs_minor_units bigint,
  p_contract_reference text,
  p_evidence_document_ids jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_project_currency text; v_existing uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_agreed_proceeds_minor_units is null or p_agreed_proceeds_minor_units <= 0 then
    raise exception 'agreed proceeds must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_agreement_date is null then raise exception 'agreement date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  if not exists (select 1 from public.property_assets
                 where id = p_property_asset_id and organization_id = p_organization_id
                   and project_id = p_project_id and lifecycle_state <> 'DISPOSED') then
    raise exception 'property asset not found or already disposed';
  end if;

  if not exists (select 1 from public.parties
                 where id = p_buyer_party_id and organization_id = p_organization_id) then
    raise exception 'buyer party not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':disposition:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.dispositions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  insert into public.dispositions(
    organization_id, project_id, property_asset_id, buyer_party_id, status,
    agreed_proceeds_minor_units, currency, agreement_date, selling_costs_minor_units,
    contract_reference, evidence_document_ids, idempotency_key, created_by
  ) values (
    p_organization_id, p_project_id, p_property_asset_id, p_buyer_party_id, 'DRAFT',
    p_agreed_proceeds_minor_units, p_currency, p_agreement_date,
    coalesce(p_selling_costs_minor_units, 0), p_contract_reference, p_evidence_document_ids,
    trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'DISPOSITION_CREATED','disposition', v_id,
          jsonb_build_object('project_id', p_project_id, 'property_asset_id', p_property_asset_id,
                             'buyer_party_id', p_buyer_party_id,
                             'agreed_proceeds_minor_units', p_agreed_proceeds_minor_units,
                             'currency', p_currency));
  return v_id;
end $$;

create or replace function public.approve_disposition(
  p_organization_id uuid, p_disposition_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  update public.dispositions
  set status = 'APPROVED'
  where id = p_disposition_id and organization_id = p_organization_id and status = 'DRAFT';
  if not found then raise exception 'disposition not found or not in draft status'; end if;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'DISPOSITION_APPROVED','disposition', p_disposition_id, '{}');
  return p_disposition_id;
end $$;

create or replace function public.recognize_sale(
  p_organization_id uuid,
  p_project_id uuid,
  p_disposition_id uuid,
  p_control_transfer_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_project_currency text; v_existing uuid;
  v_disposition record; v_carrying_amount bigint;
  v_revenue_batch_id uuid; v_cost_batch_id uuid;
  v_receivable_account uuid; v_revenue_account uuid;
  v_cost_of_sale_account uuid; v_inventory_account uuid;
  v_recognition_id uuid; v_realized_result bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_control_transfer_date is null then raise exception 'control transfer date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':sale-recognition:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.sale_recognitions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  -- Lock disposition and validate state.
  select * into v_disposition from public.dispositions
  where id = p_disposition_id and organization_id = p_organization_id and project_id = p_project_id
  for update;
  if v_disposition is null then raise exception 'disposition not found'; end if;
  if v_disposition.status not in ('APPROVED') then
    raise exception 'disposition must be approved before sale recognition';
  end if;

  -- Compute carrying amount from authoritative posted cost facts.
  select carrying_amount_minor_units into v_carrying_amount
  from public.property_carrying_amount
  where property_asset_id = v_disposition.property_asset_id
    and organization_id = p_organization_id;
  if v_carrying_amount is null then
    raise exception 'cannot compute carrying amount; no authoritative cost data available';
  end if;

  -- Create revenue recognition journal: Dr receivable, Cr revenue.
  v_receivable_account := public.ensure_financial_account(p_organization_id, 'receivable', 'ذمم العملاء', p_project_currency);
  v_revenue_account := public.ensure_financial_account(p_organization_id, 'property_sale_revenue', 'إيرادات مبيعات العقارات', p_project_currency);

  insert into public.journal_batches(
    organization_id, project_id, status, source_type, source_id, source_version,
    posting_date, description, idempotency_key, posted_by
  ) values (
    p_organization_id, p_project_id, 'POSTED', 'sale_recognition', p_disposition_id, 1,
    p_control_transfer_date, 'اعتراف بإيراد بيع عقار',
    trim(p_idempotency_key) || ':revenue', v_actor
  ) returning id into v_revenue_batch_id;

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, counterparty_party_id, sector_object_type, sector_object_id, description)
  values (p_organization_id, v_revenue_batch_id, v_receivable_account, v_disposition.agreed_proceeds_minor_units, 0, p_project_currency, v_disposition.buyer_party_id, 'property_asset', v_disposition.property_asset_id, 'إيراد معترف به');

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, sector_object_type, sector_object_id, description)
  values (p_organization_id, v_revenue_batch_id, v_revenue_account, 0, v_disposition.agreed_proceeds_minor_units, p_project_currency, 'property_asset', v_disposition.property_asset_id, 'إيراد معترف به');

  -- Create carrying-cost derecognition journal: Dr cost of sale, Cr inventory/WIP.
  if v_carrying_amount > 0 then
    v_cost_of_sale_account := public.ensure_financial_account(p_organization_id, 'cost_of_sale', 'تكلفة المبيعات', p_project_currency);
    v_inventory_account := public.ensure_financial_account(p_organization_id, 'development_wip', 'أعمال تحت التنفيذ', p_project_currency);

    insert into public.journal_batches(
      organization_id, project_id, status, source_type, source_id, source_version,
      posting_date, description, idempotency_key, posted_by
    ) values (
      p_organization_id, p_project_id, 'POSTED', 'cost_derecognition', p_disposition_id, 1,
      p_control_transfer_date, 'ترحيل تكلفة المبيعات',
      trim(p_idempotency_key) || ':cost', v_actor
    ) returning id into v_cost_batch_id;

    insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, sector_object_type, sector_object_id, description)
    values (p_organization_id, v_cost_batch_id, v_cost_of_sale_account, v_carrying_amount, 0, p_project_currency, 'property_asset', v_disposition.property_asset_id, 'تكلفة مرحّلة للبيع');

    insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, sector_object_type, sector_object_id, description)
    values (p_organization_id, v_cost_batch_id, v_inventory_account, 0, v_carrying_amount, p_project_currency, 'property_asset', v_disposition.property_asset_id, 'تكلفة مرحّلة للبيع');
  end if;

  -- Compute realized result.
  v_realized_result := v_disposition.agreed_proceeds_minor_units - v_carrying_amount - v_disposition.selling_costs_minor_units;

  -- Insert sale recognition fact.
  insert into public.sale_recognitions(
    organization_id, project_id, disposition_id, recognized_revenue_minor_units,
    derecognized_carrying_cost_minor_units, selling_costs_minor_units, realized_result_minor_units,
    currency, control_transfer_date, revenue_journal_batch_id, cost_derecognition_journal_batch_id,
    idempotency_key, recognized_by
  ) values (
    p_organization_id, p_project_id, p_disposition_id, v_disposition.agreed_proceeds_minor_units,
    v_carrying_amount, v_disposition.selling_costs_minor_units, v_realized_result,
    p_project_currency, p_control_transfer_date, v_revenue_batch_id, v_cost_batch_id,
    trim(p_idempotency_key), v_actor
  ) returning id into v_recognition_id;

  -- Create receivable.
  insert into public.sale_receivables(
    organization_id, project_id, sale_recognition_id, receivable_minor_units, currency, status
  ) values (
    p_organization_id, p_project_id, v_recognition_id, v_disposition.agreed_proceeds_minor_units,
    p_project_currency, 'OUTSTANDING'
  );

  -- Update disposition status.
  update public.dispositions
  set status = 'CONTROL_TRANSFERRED', control_transfer_date = p_control_transfer_date,
      recognized_at = now(), recognized_by = v_actor
  where id = p_disposition_id;

  -- Update property asset lifecycle.
  update public.property_assets
  set lifecycle_state = 'DISPOSED'
  where id = v_disposition.property_asset_id and organization_id = p_organization_id;

  -- Update project lifecycle.
  update public.investment_projects
  set lifecycle_state = 'EXITING'
  where id = p_project_id and lifecycle_state in ('OPERATING','FUNDING');

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'SALE_RECOGNIZED','sale_recognition', v_recognition_id,
          jsonb_build_object('project_id', p_project_id, 'disposition_id', p_disposition_id,
                             'recognized_revenue_minor_units', v_disposition.agreed_proceeds_minor_units,
                             'derecognized_carrying_cost_minor_units', v_carrying_amount,
                             'realized_result_minor_units', v_realized_result,
                             'currency', p_project_currency, 'control_transfer_date', p_control_transfer_date));
  return v_recognition_id;
end $$;

create or replace function public.record_collection(
  p_organization_id uuid,
  p_project_id uuid,
  p_sale_receivable_id uuid,
  p_collection_minor_units bigint,
  p_currency text,
  p_collected_on date,
  p_cash_account_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_batch_id uuid; v_cash_account uuid; v_receivable_account uuid;
  v_project_currency text; v_existing uuid;
  v_receivable_amount bigint; v_already_collected bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_collection_minor_units is null or p_collection_minor_units <= 0 then
    raise exception 'collection amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_collected_on is null then raise exception 'collection date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':collection:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.collections
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  -- Lock receivable and check collection ceiling.
  select receivable_minor_units into v_receivable_amount
  from public.sale_receivables
  where id = p_sale_receivable_id and organization_id = p_organization_id and project_id = p_project_id
  for update;
  if v_receivable_amount is null then raise exception 'receivable not found'; end if;

  select coalesce(sum(collection_minor_units),0) into v_already_collected
  from public.collections
  where sale_receivable_id = p_sale_receivable_id and organization_id = p_organization_id;
  if v_already_collected + p_collection_minor_units > v_receivable_amount then
    raise exception 'collection exceeds outstanding receivable';
  end if;

  -- Create balanced journal batch: Dr cash, Cr receivable.
  v_receivable_account := public.ensure_financial_account(p_organization_id, 'receivable', 'ذمم العملاء', p_currency);

  insert into public.journal_batches(
    organization_id, project_id, status, source_type, source_id, source_version,
    posting_date, description, idempotency_key, posted_by
  ) values (
    p_organization_id, p_project_id, 'POSTED', 'collection', gen_random_uuid(), 1,
    p_collected_on, 'تحصيل من عميل',
    trim(p_idempotency_key) || ':collection', v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, description)
  values (p_organization_id, v_batch_id, p_cash_account_id, p_collection_minor_units, 0, p_currency, 'تحصيل');

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, description)
  values (p_organization_id, v_batch_id, v_receivable_account, 0, p_collection_minor_units, p_currency, 'تحصيل');

  insert into public.collections(
    organization_id, project_id, sale_receivable_id, collection_minor_units, currency,
    collected_on, cash_account_id, journal_batch_id, idempotency_key, collected_by
  ) values (
    p_organization_id, p_project_id, p_sale_receivable_id, p_collection_minor_units, p_currency,
    p_collected_on, p_cash_account_id, v_batch_id, trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  -- Update receivable status.
  if v_already_collected + p_collection_minor_units = v_receivable_amount then
    update public.sale_receivables set status = 'COLLECTED' where id = p_sale_receivable_id;
    update public.dispositions d
    set status = 'SETTLED'
    from public.sale_recognitions sr
    where sr.id = p_sale_receivable_id
      and sr.disposition_id = d.id
      and d.organization_id = p_organization_id;
  elsif v_already_collected + p_collection_minor_units > 0 then
    update public.sale_receivables set status = 'PARTIAL' where id = p_sale_receivable_id;
  end if;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'COLLECTION_RECORDED','collection', v_id,
          jsonb_build_object('project_id', p_project_id, 'sale_receivable_id', p_sale_receivable_id,
                             'collection_minor_units', p_collection_minor_units, 'currency', p_currency,
                             'collected_on', p_collected_on));
  return v_id;
end $$;

revoke all on function public.create_disposition(uuid,uuid,uuid,uuid,bigint,text,date,bigint,text,jsonb,text) from public, anon;
revoke all on function public.approve_disposition(uuid,uuid) from public, anon;
revoke all on function public.recognize_sale(uuid,uuid,uuid,date,text) from public, anon;
revoke all on function public.record_collection(uuid,uuid,uuid,bigint,text,date,uuid,text) from public, anon;
grant execute on function public.create_disposition(uuid,uuid,uuid,uuid,bigint,text,date,bigint,text,jsonb,text),
  public.approve_disposition(uuid,uuid),
  public.recognize_sale(uuid,uuid,uuid,date,text),
  public.record_collection(uuid,uuid,uuid,bigint,text,date,uuid,text)
to authenticated;

-- GF-019 / Agriculture Profitability, Cycle Closeout & Technical Gate.
--
-- Finance Core remains the only monetary truth. This migration adds an
-- append-only dimension from an active, posted PROJECT_EXPENSE journal line to
-- a CropCycle (and optionally one of its assigned Fields); it does not post an
-- Agriculture journal or derive expense from payment. Result and closeout
-- projections remain reproducible from immutable operational and Finance facts.

-- ===========================================================================
-- 1. Append-only posted-cost attribution and immutable close metadata
-- ===========================================================================
create table public.crop_cycle_cost_attributions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  field_id uuid,
  source_journal_line_id uuid not null,
  attributed_amount_minor_units bigint not null check (attributed_amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  cost_category text not null check (cost_category in (
    'INPUTS','LABOR','EQUIPMENT','IRRIGATION','HARVEST','STORAGE','OTHER'
  )),
  policy_reference text not null check (char_length(trim(policy_reference)) between 3 and 200),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  reversal_of_attribution_id uuid,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (id,organization_id),
  unique (organization_id,idempotency_key),
  unique (reversal_of_attribution_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (crop_cycle_id,organization_id,project_id)
    references public.crop_cycles(id,organization_id,project_id) on delete restrict,
  foreign key (organization_id,crop_cycle_id,field_id)
    references public.crop_cycle_field_assignments(organization_id,crop_cycle_id,field_id) on delete restrict,
  foreign key (source_journal_line_id,organization_id)
    references public.journal_lines(id,organization_id) on delete restrict,
  foreign key (reversal_of_attribution_id,organization_id)
    references public.crop_cycle_cost_attributions(id,organization_id) on delete restrict
);
create index crop_cycle_cost_attributions_cycle_idx
  on public.crop_cycle_cost_attributions(crop_cycle_id,recorded_at);
create index crop_cycle_cost_attributions_source_idx
  on public.crop_cycle_cost_attributions(source_journal_line_id);

alter table public.crop_cycle_state_history
  add constraint crop_cycle_state_history_closeout_scope_key
  unique (id,organization_id,project_id,crop_cycle_id);

create table public.crop_cycle_closeouts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  closing_state_history_id uuid not null,
  close_reason text not null check (char_length(trim(close_reason)) between 3 and 500),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  closed_by uuid not null references auth.users(id) on delete restrict,
  closed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (crop_cycle_id),
  unique (closing_state_history_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id,project_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (crop_cycle_id,organization_id,project_id)
    references public.crop_cycles(id,organization_id,project_id) on delete restrict,
  foreign key (closing_state_history_id,organization_id,project_id,crop_cycle_id)
    references public.crop_cycle_state_history(id,organization_id,project_id,crop_cycle_id) on delete restrict
);
create index crop_cycle_closeouts_project_idx on public.crop_cycle_closeouts(project_id,closed_at desc);

-- ===========================================================================
-- 2. Structural guards: source authority, ceiling, correction and immutability
-- ===========================================================================
create or replace function public.gf019_guard_cost_attribution_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_line public.journal_lines%rowtype;
  v_batch public.journal_batches%rowtype;
  v_role text;
  v_existing_amount numeric;
  v_original public.crop_cycle_cost_attributions%rowtype;
begin
  select * into v_line from public.journal_lines
  where id=new.source_journal_line_id and organization_id=new.organization_id
  for update;
  if not found then raise exception 'authoritative posted cost source not found'; end if;
  select * into v_batch from public.journal_batches
  where id=v_line.batch_id and organization_id=new.organization_id;
  select role into v_role from public.semantic_accounts where id=v_line.account_id;

  if v_line.project_id<>new.project_id or v_batch.project_id<>new.project_id then
    raise exception 'posted cost source does not belong to crop cycle project';
  end if;
  if v_batch.source_type<>'COST_OBLIGATION' or v_role<>'PROJECT_EXPENSE'
     or v_line.debit_minor_units<=0 or v_line.credit_minor_units<>0
     or v_line.currency<>new.currency then
    raise exception 'source is not an authoritative posted operating expense';
  end if;
  if exists(select 1 from public.journal_batches r
            where r.reversal_of_batch_id=v_batch.id) then
    raise exception 'posted cost source has been reversed';
  end if;
  -- Land purchase consideration is investment position, never a seasonal
  -- operating expense under the current approved policy.
  if exists(
    select 1 from public.agricultural_land_assets a
    where a.organization_id=new.organization_id and a.project_id=new.project_id
      and a.control_basis='PURCHASED'
      and a.consideration_obligation_id=v_batch.source_id
  ) then
    raise exception 'land acquisition consideration is not eligible for crop cycle operating cost';
  end if;

  if new.reversal_of_attribution_id is not null then
    select * into v_original from public.crop_cycle_cost_attributions
    where id=new.reversal_of_attribution_id and organization_id=new.organization_id
    for update;
    if not found or v_original.reversal_of_attribution_id is not null then
      raise exception 'cost attribution reversal target is invalid';
    end if;
    if exists(select 1 from public.crop_cycle_cost_attributions
              where reversal_of_attribution_id=v_original.id) then
      raise exception 'cost attribution is already reversed';
    end if;
    if new.project_id<>v_original.project_id
       or new.crop_cycle_id<>v_original.crop_cycle_id
       or new.field_id is distinct from v_original.field_id
       or new.source_journal_line_id<>v_original.source_journal_line_id
       or new.attributed_amount_minor_units<>v_original.attributed_amount_minor_units
       or new.currency<>v_original.currency
       or new.cost_category<>v_original.cost_category then
      raise exception 'cost attribution reversal must exactly offset the original attribution';
    end if;
    return new;
  end if;

  select coalesce(sum(a.attributed_amount_minor_units::numeric),0)
    into v_existing_amount
  from public.crop_cycle_cost_attributions a
  where a.source_journal_line_id=new.source_journal_line_id
    and a.reversal_of_attribution_id is null
    and not exists(select 1 from public.crop_cycle_cost_attributions r
                   where r.reversal_of_attribution_id=a.id);
  if v_existing_amount+new.attributed_amount_minor_units>v_line.debit_minor_units then
    raise exception 'crop cycle cost attribution exceeds authoritative source amount';
  end if;
  return new;
end $$;
create trigger crop_cycle_cost_attributions_insert_guard
before insert on public.crop_cycle_cost_attributions
for each row execute function public.gf019_guard_cost_attribution_insert();

create or replace function public.gf019_guard_facts_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'crop cycle cost attribution and closeout facts are append-only';
end $$;
create trigger crop_cycle_cost_attributions_immutable
before update or delete on public.crop_cycle_cost_attributions
for each row execute function public.gf019_guard_facts_immutable();
create trigger crop_cycle_closeouts_immutable
before update or delete on public.crop_cycle_closeouts
for each row execute function public.gf019_guard_facts_immutable();

-- A shared S6 reversal remains the correction mechanism for Finance Core. An
-- attributed source must first receive an explicit attribution offset so the
-- dimension cannot silently point at reversed monetary truth.
create or replace function public.gf019_guard_attributed_cost_source_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type='REVERSAL' and exists(
    select 1
    from public.crop_cycle_cost_attributions a
    join public.journal_lines jl on jl.id=a.source_journal_line_id
    where jl.batch_id=new.source_id
      and a.reversal_of_attribution_id is null
      and not exists(select 1 from public.crop_cycle_cost_attributions r
                     where r.reversal_of_attribution_id=a.id)
  ) then
    raise exception 'reverse active crop cycle cost attributions before reversing the Finance source';
  end if;
  return new;
end $$;
create trigger journal_batches_gf019_attributed_cost_reversal_guard
before insert on public.journal_batches
for each row execute function public.gf019_guard_attributed_cost_source_reversal();

-- ===========================================================================
-- 3. Cost attribution commands. Replay lookup precedes source/cycle state.
-- ===========================================================================
create or replace function public.attribute_crop_cycle_cost(
  p_organization_id uuid,p_project_id uuid,p_crop_cycle_id uuid,p_field_id uuid,
  p_source_journal_line_id uuid,p_amount_minor_units bigint,p_cost_category text,
  p_policy_reference text,p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid; v_hash text;
  v_existing public.crop_cycle_cost_attributions%rowtype; v_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then
    raise exception 'attributed cost amount must be positive';
  end if;
  if p_cost_category not in ('INPUTS','LABOR','EQUIPMENT','IRRIGATION','HARVEST','STORAGE','OTHER') then
    raise exception 'invalid crop cycle cost category';
  end if;
  if p_policy_reference is null or char_length(trim(p_policy_reference)) not between 3 and 200 then
    raise exception 'cost attribution policy reference is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'cost attribution evidence is required';
  end if;

  select encode(digest(jsonb_build_object(
    'project_id',p_project_id,'crop_cycle_id',p_crop_cycle_id,'field_id',p_field_id,
    'source_journal_line_id',p_source_journal_line_id,
    'amount_minor_units',p_amount_minor_units,'cost_category',p_cost_category,
    'policy_reference',trim(p_policy_reference),'evidence_reference',trim(p_evidence_reference)
  )::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':gf019-cost:'||trim(p_idempotency_key),0));
  select * into v_existing from public.crop_cycle_cost_attributions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if not exists(select 1 from public.investment_projects p
    where p.id=p_project_id and p.organization_id=p_organization_id and p.sector='AGRICULTURE') then
    raise exception 'agriculture project not found';
  end if;
  if not exists(select 1 from public.crop_cycles c
    where c.id=p_crop_cycle_id and c.organization_id=p_organization_id and c.project_id=p_project_id) then
    raise exception 'crop cycle not found in project';
  end if;
  if p_field_id is not null and not exists(select 1 from public.crop_cycle_field_assignments a
    where a.organization_id=p_organization_id and a.crop_cycle_id=p_crop_cycle_id
      and a.field_id=p_field_id and a.project_id=p_project_id) then
    raise exception 'field is not assigned to crop cycle';
  end if;
  select jl.currency into v_currency from public.journal_lines jl
    where jl.id=p_source_journal_line_id and jl.organization_id=p_organization_id;
  if v_currency is null then raise exception 'authoritative posted cost source not found'; end if;

  insert into public.crop_cycle_cost_attributions(
    organization_id,project_id,crop_cycle_id,field_id,source_journal_line_id,
    attributed_amount_minor_units,currency,cost_category,policy_reference,
    evidence_reference,recorded_by,idempotency_key,request_hash
  ) values(
    p_organization_id,p_project_id,p_crop_cycle_id,p_field_id,p_source_journal_line_id,
    p_amount_minor_units,v_currency,p_cost_category,trim(p_policy_reference),
    trim(p_evidence_reference),v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'CROP_CYCLE_COST_ATTRIBUTED','crop_cycle_cost_attribution',v_id,
    jsonb_build_object('project_id',p_project_id,'crop_cycle_id',p_crop_cycle_id,
      'field_id',p_field_id,'source_journal_line_id',p_source_journal_line_id,
      'attributed_amount_minor_units',p_amount_minor_units,'currency',v_currency,
      'cost_category',p_cost_category,'monetary_effect','NONE'));
  return v_id;
end $$;

create or replace function public.reverse_crop_cycle_cost_attribution(
  p_organization_id uuid,p_attribution_id uuid,p_reason text,
  p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_original public.crop_cycle_cost_attributions%rowtype;
  v_existing public.crop_cycle_cost_attributions%rowtype; v_hash text; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'cost attribution reversal reason is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'cost attribution reversal evidence is required';
  end if;
  select encode(digest(jsonb_build_object('attribution_id',p_attribution_id,
    'reason',trim(p_reason),'evidence_reference',trim(p_evidence_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':gf019-cost-reverse:'||trim(p_idempotency_key),0));
  select * into v_existing from public.crop_cycle_cost_attributions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_original from public.crop_cycle_cost_attributions
  where id=p_attribution_id and organization_id=p_organization_id for update;
  if not found or v_original.reversal_of_attribution_id is not null then
    raise exception 'cost attribution not found';
  end if;
  insert into public.crop_cycle_cost_attributions(
    organization_id,project_id,crop_cycle_id,field_id,source_journal_line_id,
    attributed_amount_minor_units,currency,cost_category,policy_reference,
    evidence_reference,reversal_of_attribution_id,recorded_by,idempotency_key,request_hash
  ) values(
    p_organization_id,v_original.project_id,v_original.crop_cycle_id,v_original.field_id,
    v_original.source_journal_line_id,v_original.attributed_amount_minor_units,
    v_original.currency,v_original.cost_category,
    'عكس: '||left(trim(p_reason),194),trim(p_evidence_reference),v_original.id,
    v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'CROP_CYCLE_COST_ATTRIBUTION_REVERSED','crop_cycle_cost_attribution',v_id,
    jsonb_build_object('project_id',v_original.project_id,'crop_cycle_id',v_original.crop_cycle_id,
      'reversal_of_attribution_id',v_original.id,'reason',trim(p_reason),'monetary_effect','NONE'));
  return v_id;
end $$;

-- ===========================================================================
-- 4. Read models: eligible sources, attribution lineage and cycle result
-- ===========================================================================
create or replace view public.crop_cycle_cost_sources_read with (security_invoker=on) as
select jl.id as source_journal_line_id,jl.organization_id,jl.project_id,jl.batch_id,
  jb.source_id as cost_obligation_id,o.description,o.transaction_date,o.party_id,
  jl.debit_minor_units::text as posted_amount_minor_units,jl.currency,
  coalesce((select sum(a.attributed_amount_minor_units::numeric)
    from public.crop_cycle_cost_attributions a
    where a.source_journal_line_id=jl.id and a.reversal_of_attribution_id is null
      and not exists(select 1 from public.crop_cycle_cost_attributions r
                     where r.reversal_of_attribution_id=a.id)),0)::text as attributed_amount_minor_units,
  (jl.debit_minor_units::numeric-coalesce((select sum(a.attributed_amount_minor_units::numeric)
    from public.crop_cycle_cost_attributions a
    where a.source_journal_line_id=jl.id and a.reversal_of_attribution_id is null
      and not exists(select 1 from public.crop_cycle_cost_attributions r
                     where r.reversal_of_attribution_id=a.id)),0))::text as available_amount_minor_units,
  'FINANCE_CORE_POSTED_JOURNAL_LINE'::text as authoritative_source
from public.journal_lines jl
join public.journal_batches jb on jb.id=jl.batch_id and jb.organization_id=jl.organization_id
join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='PROJECT_EXPENSE'
join public.cost_obligations o on o.id=jb.source_id and o.organization_id=jl.organization_id
where jb.source_type='COST_OBLIGATION' and jl.debit_minor_units>0 and jl.credit_minor_units=0
  and not exists(select 1 from public.journal_batches r where r.reversal_of_batch_id=jb.id)
  and not exists(select 1 from public.agricultural_land_assets la
    where la.organization_id=jl.organization_id and la.project_id=jl.project_id
      and la.control_basis='PURCHASED' and la.consideration_obligation_id=jb.source_id);

create or replace view public.crop_cycle_cost_attributions_read with (security_invoker=on) as
select a.id,a.organization_id,a.project_id,a.crop_cycle_id,a.field_id,
  a.source_journal_line_id,jl.batch_id as source_journal_batch_id,jl.obligation_id,
  o.description as source_description,o.transaction_date as source_transaction_date,
  a.attributed_amount_minor_units::text as attributed_amount_minor_units,a.currency,
  a.cost_category,a.policy_reference,a.evidence_reference,a.reversal_of_attribution_id,
  (a.reversal_of_attribution_id is null and not exists(
    select 1 from public.crop_cycle_cost_attributions r where r.reversal_of_attribution_id=a.id
  ) and not exists(
    select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jl.batch_id
  )) as is_active,
  a.recorded_by,a.recorded_at,'FINANCE_CORE_POSTED_JOURNAL_LINE'::text as authoritative_source
from public.crop_cycle_cost_attributions a
join public.journal_lines jl on jl.id=a.source_journal_line_id
left join public.cost_obligations o on o.id=jl.obligation_id;

-- Dependency shell; replaced below by the complete integrity projection. Its
-- stable column contract lets the result view aggregate exceptions without a
-- procedural migration or circular dependency.
create or replace view public.crop_cycle_integrity_issues_read with (security_invoker=on) as
select c.organization_id,c.project_id,c.id as crop_cycle_id,
  ''::text as code,''::text as severity,''::text as message_ar
from public.crop_cycles c where false;

create or replace view public.crop_cycle_results_read with (security_invoker=on) as
with assignment_summary as (
  select a.crop_cycle_id,
    string_agg(distinct f.identifier,'، ' order by f.identifier) as field_identifiers,
    string_agg(distinct fm.name,'، ' order by fm.name) as farm_names,
    count(*) as assignment_count,
    case when count(distinct a.assigned_area_unit)=1 then sum(a.assigned_area_quantity) end as assigned_area,
    case when count(distinct a.assigned_area_unit)=1 then min(a.assigned_area_unit) end as area_unit
  from public.crop_cycle_field_assignments a
  join public.fields f on f.id=a.field_id
  join public.farms fm on fm.id=f.farm_id
  group by a.crop_cycle_id
), harvest_summary as (
  select e.crop_cycle_id,count(*) as harvest_event_count,
    case when count(distinct e.quantity_unit)=1 then sum(e.gross_quantity) end as gross_quantity,
    case when count(distinct e.quantity_unit)=1 then sum(e.net_quantity) end as net_quantity,
    case when count(distinct e.quantity_unit)=1 then sum(e.gross_quantity-e.net_quantity) end as harvest_loss,
    case when count(distinct e.quantity_unit)=1 then min(e.quantity_unit) end as quantity_unit,
    count(*) filter(where e.evidence_reference is null) as harvest_missing_evidence
  from public.harvest_events e group by e.crop_cycle_id
), movement_summary as (
  select l.crop_cycle_id,
    case when count(distinct l.quantity_unit)=1 then sum(coalesce((
      select sum(m.quantity) from public.harvest_inventory_movements m
      where m.harvest_lot_id=l.id and m.movement_type='SPOILAGE'),0)) end as spoilage_quantity,
    case when count(distinct l.quantity_unit)=1 then sum(coalesce((
      select sum(m.quantity) from public.harvest_inventory_movements m
      where m.harvest_lot_id=l.id and m.movement_type='SALE_ISSUE'),0)) end as sold_quantity,
    case when count(distinct l.quantity_unit)=1 then sum(public.harvest_lot_total_balance(l.id)) end as remaining_inventory
  from public.harvest_lots l group by l.crop_cycle_id
), sale_cycle_amounts as (
  select sl.sale_id,l.crop_cycle_id,sum(sl.line_amount_minor_units)::bigint as cycle_amount,
    sum(sum(sl.line_amount_minor_units)) over(partition by sl.sale_id)::bigint as sale_amount
  from public.agriculture_sale_lines sl
  join public.harvest_lots l on l.id=sl.harvest_lot_id
  join public.agriculture_sale_recognitions r on r.sale_id=sl.sale_id
  group by sl.sale_id,l.crop_cycle_id
), collection_totals as (
  select r.sale_id,coalesce(sum(c.amount_minor_units),0)::bigint as collected
  from public.agriculture_sale_recognitions r
  left join public.agriculture_sale_collections c on c.recognition_id=r.id
  group by r.sale_id
), cash_base as (
  select sca.*,
    floor(ct.collected::numeric*sca.cycle_amount/sca.sale_amount)::bigint as base_amount,
    (ct.collected::numeric*sca.cycle_amount/sca.sale_amount
      -floor(ct.collected::numeric*sca.cycle_amount/sca.sale_amount)) as fraction,
    ct.collected
  from sale_cycle_amounts sca join collection_totals ct on ct.sale_id=sca.sale_id
), cash_ranked as (
  select cb.*,
    row_number() over(partition by sale_id order by fraction desc,crop_cycle_id) as fraction_rank,
    collected-sum(base_amount) over(partition by sale_id) as remainder
  from cash_base cb
), commercial_summary as (
  select sca.crop_cycle_id,sum(sca.cycle_amount)::bigint as recognized_revenue,
    sum(cr.base_amount+case when cr.fraction_rank<=cr.remainder then 1 else 0 end)::bigint as collected
  from sale_cycle_amounts sca join cash_ranked cr
    on cr.sale_id=sca.sale_id and cr.crop_cycle_id=sca.crop_cycle_id
  group by sca.crop_cycle_id
), cost_summary as (
  select a.crop_cycle_id,sum(a.attributed_amount_minor_units)::bigint as operating_cost
  from public.crop_cycle_cost_attributions a
  join public.journal_lines jl on jl.id=a.source_journal_line_id
  where a.reversal_of_attribution_id is null
    and not exists(select 1 from public.crop_cycle_cost_attributions r where r.reversal_of_attribution_id=a.id)
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jl.batch_id)
  group by a.crop_cycle_id
), activity_summary as (
  select crop_cycle_id,count(*) as activity_count,
    count(*) filter(where evidence_reference is null) as activity_missing_evidence
  from public.field_activities group by crop_cycle_id
), input_summary as (
  select crop_cycle_id,count(*) as input_application_count,
    count(*) filter(where evidence_reference is null) as input_missing_evidence
  from public.input_applications group by crop_cycle_id
), cycle_land_assets as (
  select distinct a.crop_cycle_id,la.id,la.name,la.control_basis,la.agreed_consideration_minor_units
  from public.crop_cycle_field_assignments a
  join public.fields f on f.id=a.field_id
  join public.farm_land_asset_links fl on fl.farm_id=f.farm_id
  join public.agricultural_land_assets la on la.id=fl.land_asset_id
), land_summary as (
  select crop_cycle_id,
    string_agg(name,'، ' order by name) as land_asset_names,
    string_agg(distinct control_basis,'، ' order by control_basis) as land_control_bases,
    coalesce(sum(agreed_consideration_minor_units) filter(where control_basis='PURCHASED'),0) as land_consideration
  from cycle_land_assets group by crop_cycle_id
), exception_summary as (
  select crop_cycle_id,count(*) as exception_count,
    count(*) filter(where severity='HARD') as hard_exception_count,
    string_agg(code,',' order by severity,code) as exception_codes
  from public.crop_cycle_integrity_issues_read group by crop_cycle_id
)
select c.id as crop_cycle_id,c.organization_id,c.project_id,c.crop,c.variety,c.season_reference,
  public.agriculture_current_cycle_state(c.id) as operational_state,
  coalesce(a.farm_names,'—') as farm_names,coalesce(a.field_identifiers,'—') as field_identifiers,
  coalesce(a.assignment_count,0) as assignment_count,a.assigned_area::text as assigned_area_quantity,a.area_unit,
  coalesce(h.harvest_event_count,0) as harvest_event_count,h.gross_quantity::text as gross_harvest_quantity,
  h.net_quantity::text as net_accepted_harvest_quantity,h.harvest_loss::text as harvest_loss,
  m.spoilage_quantity::text as spoilage_quantity,m.sold_quantity::text as quantity_sold,
  m.remaining_inventory::text as remaining_physical_inventory,h.quantity_unit,
  coalesce(cs.recognized_revenue,0)::text as recognized_revenue_minor_units,
  coalesce(cs.collected,0)::text as cash_collected_minor_units,
  greatest(coalesce(cs.recognized_revenue,0)-coalesce(cs.collected,0),0)::text as receivable_outstanding_minor_units,
  coalesce(cost.operating_cost,0)::text as attributed_operating_cost_minor_units,
  (coalesce(cs.recognized_revenue,0)-coalesce(cost.operating_cost,0))::text as operating_result_to_date_minor_units,
  p.reporting_currency as currency,
  case when a.assigned_area>0 and h.net_quantity is not null then (h.net_quantity/a.assigned_area)::text end as yield_per_area,
  case when a.assigned_area>0 then round(coalesce(cs.recognized_revenue,0)::numeric/a.assigned_area)::bigint::text end as recognized_revenue_minor_units_per_area,
  case when a.assigned_area>0 then round(coalesce(cost.operating_cost,0)::numeric/a.assigned_area)::bigint::text end as operating_cost_minor_units_per_area,
  case when m.sold_quantity>0 then round(coalesce(cs.recognized_revenue,0)::numeric/m.sold_quantity)::bigint::text end as realized_average_selling_price_minor_units,
  coalesce(act.activity_count,0) as activity_count,coalesce(inp.input_application_count,0) as input_application_count,
  case when coalesce(h.harvest_event_count,0)=0 then 'INCOMPLETE'
       when coalesce(h.harvest_missing_evidence,0)+coalesce(act.activity_missing_evidence,0)+coalesce(inp.input_missing_evidence,0)>0 then 'PARTIAL'
       else 'COMPLETE' end as source_evidence_completeness,
  coalesce(ex.exception_count,0) as open_exception_count,
  coalesce(ex.hard_exception_count,0) as hard_exception_count,ex.exception_codes as open_exception_codes,
  land.land_asset_names,land.land_control_bases,coalesce(land.land_consideration,0)::text as land_consideration_minor_units,
  'EXCLUDED_FROM_CROP_CYCLE_OPERATING_COST'::text as land_cost_treatment,
  'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text as remaining_inventory_value_status,
  'NOT_GUESSED'::text as cogs_status,
  co.closed_by,co.closed_at,co.close_reason,co.evidence_reference as close_evidence_reference
from public.crop_cycles c
join public.investment_projects p on p.id=c.project_id and p.organization_id=c.organization_id
left join assignment_summary a on a.crop_cycle_id=c.id
left join harvest_summary h on h.crop_cycle_id=c.id
left join movement_summary m on m.crop_cycle_id=c.id
left join commercial_summary cs on cs.crop_cycle_id=c.id
left join cost_summary cost on cost.crop_cycle_id=c.id
left join activity_summary act on act.crop_cycle_id=c.id
left join input_summary inp on inp.crop_cycle_id=c.id
left join land_summary land on land.crop_cycle_id=c.id
left join exception_summary ex on ex.crop_cycle_id=c.id
left join public.crop_cycle_closeouts co on co.crop_cycle_id=c.id;

-- ===========================================================================
-- 5. Reproducible integrity exceptions. Open inventory/receivable are WARN,
--    not close blockers; incoherent lineage/ceilings are HARD.
-- ===========================================================================
create or replace view public.crop_cycle_integrity_issues_read with (security_invoker=on) as
select c.organization_id,c.project_id,c.id as crop_cycle_id,'NO_ASSIGNMENT'::text as code,
  'HARD'::text as severity,'لا يوجد حقل مخصص لهذه الدورة.'::text as message_ar
from public.crop_cycles c where not exists(select 1 from public.crop_cycle_field_assignments a where a.crop_cycle_id=c.id)
union all
select c.organization_id,c.project_id,c.id,'NO_HARVEST','HARD',
  'لا يمكن إغلاق دورة حصاد ناجحة دون حدث حصاد؛ الفشل التشغيلي له مسار FAILED.'
from public.crop_cycles c where public.agriculture_current_cycle_state(c.id)='HARVESTING'
  and not exists(select 1 from public.harvest_events e where e.crop_cycle_id=c.id)
union all
select c.organization_id,c.project_id,c.id,'BROKEN_LIFECYCLE_CHAIN','HARD','سلسلة حالة الدورة غير مكتملة أو متفرعة.'
from public.crop_cycles c where (select count(*) from public.crop_cycle_state_history h
  where h.crop_cycle_id=c.id and not exists(select 1 from public.crop_cycle_state_history n where n.previous_history_id=h.id))<>1
union all
select l.organization_id,l.project_id,l.crop_cycle_id,'NEGATIVE_INVENTORY','HARD','رصيد مخزون حصاد سالب.'
from public.harvest_lots l where public.harvest_lot_total_balance(l.id)<0
union all
select distinct l.organization_id,l.project_id,l.crop_cycle_id,'NEGATIVE_INVENTORY','HARD','رصيد تشغيلة حصاد سالب في موقع تخزين.'
from public.harvest_lots l
join lateral (
  select storage_id from (
    select m.from_storage_id as storage_id from public.harvest_inventory_movements m
      where m.harvest_lot_id=l.id and m.from_storage_id is not null
    union
    select m.to_storage_id from public.harvest_inventory_movements m
      where m.harvest_lot_id=l.id and m.to_storage_id is not null
  ) locations where public.harvest_lot_storage_balance(l.id,storage_id)<0
) negative_location on true
union all
select l.organization_id,l.project_id,l.crop_cycle_id,'BROKEN_HARVEST_RECEIPT','HARD','استلام تشغيلة الحصاد لا يطابق صافي حدث الحصاد.'
from public.harvest_lots l where (select count(*) from public.harvest_inventory_movements m
  where m.harvest_lot_id=l.id and m.movement_type='HARVEST_RECEIPT')<>1
  or (select coalesce(sum(m.quantity),0) from public.harvest_inventory_movements m
      where m.harvest_lot_id=l.id and m.movement_type='HARVEST_RECEIPT')<>l.initial_quantity
union all
select e.organization_id,e.project_id,e.crop_cycle_id,'BROKEN_HARVEST_RECEIPT','HARD','حدث حصاد لا يملك تشغيلة واستلامًا متماسكين.'
from public.harvest_events e where not exists(select 1 from public.harvest_lots l where l.harvest_event_id=e.id)
union all
select sl.organization_id,sl.project_id,l.crop_cycle_id,'BROKEN_SALE_ISSUE','HARD','كمية البيع لا تتطابق مع حركة صرف SALE_ISSUE.'
from public.agriculture_sale_lines sl
join public.harvest_lots l on l.id=sl.harvest_lot_id
join public.agriculture_sale_recognitions r on r.sale_id=sl.sale_id
where (select count(*) from public.harvest_inventory_movements m where m.agriculture_sale_line_id=sl.id)<>1
   or not exists(select 1 from public.harvest_inventory_movements m where m.agriculture_sale_line_id=sl.id
      and m.movement_type='SALE_ISSUE' and m.quantity=sl.quantity and m.unit=sl.unit
      and m.from_storage_id=sl.source_storage_id)
union all
select r.organization_id,r.project_id,l.crop_cycle_id,'BROKEN_REVENUE_SOURCE','HARD','الإيراد المعترف به لا يطابق سطور البيع أو القيد المشترك.'
from public.agriculture_sale_recognitions r
join public.agriculture_sale_lines sl on sl.sale_id=r.sale_id
join public.harvest_lots l on l.id=sl.harvest_lot_id
where r.recognized_revenue_minor_units<>(select sum(x.line_amount_minor_units) from public.agriculture_sale_lines x where x.sale_id=r.sale_id)
   or not exists(select 1 from public.journal_batches jb where jb.id=r.journal_batch_id
     and jb.source_type='AGRICULTURE_SALE_RECOGNITION' and jb.source_id=r.id)
union all
select r.organization_id,r.project_id,l.crop_cycle_id,'COLLECTION_CEILING_BROKEN','HARD','التحصيل يتجاوز الذمة المعترف بها.'
from public.agriculture_sale_recognitions r
join public.agriculture_sale_lines sl on sl.sale_id=r.sale_id
join public.harvest_lots l on l.id=sl.harvest_lot_id
where (select coalesce(sum(c.amount_minor_units),0) from public.agriculture_sale_collections c where c.recognition_id=r.id)>r.recognized_revenue_minor_units
union all
select a.organization_id,a.project_id,a.crop_cycle_id,'COST_ATTRIBUTION_CEILING_BROKEN','HARD','توزيع تكلفة التشغيل يتجاوز مصدره المالي المعتمد.'
from public.crop_cycle_cost_attributions a join public.journal_lines jl on jl.id=a.source_journal_line_id
where a.reversal_of_attribution_id is null and
  (select coalesce(sum(x.attributed_amount_minor_units),0) from public.crop_cycle_cost_attributions x
   where x.source_journal_line_id=a.source_journal_line_id and x.reversal_of_attribution_id is null
     and not exists(select 1 from public.crop_cycle_cost_attributions z where z.reversal_of_attribution_id=x.id))>jl.debit_minor_units
union all
select l.organization_id,l.project_id,l.crop_cycle_id,'OPEN_INVENTORY','WARN','يوجد مخزون حصاد فعلي متبقٍ بعد انتهاء النشاط.'
from public.harvest_lots l group by l.organization_id,l.project_id,l.crop_cycle_id
having sum(public.harvest_lot_total_balance(l.id))>0
union all
select s.organization_id,s.project_id,l.crop_cycle_id,'OPEN_RECEIVABLE','WARN','توجد ذمة بيع متبقية للتحصيل.'
from public.agriculture_sales_read s
join public.agriculture_sale_lines sl on sl.sale_id=s.sale_id
join public.harvest_lots l on l.id=sl.harvest_lot_id
where s.recognition_id is not null and s.outstanding_receivable_minor_units::bigint>0
group by s.organization_id,s.project_id,l.crop_cycle_id
union all
select s.organization_id,s.project_id,l.crop_cycle_id,'OPEN_SALE','WARN','توجد مسودة/عملية بيع معتمدة لم تنتقل السيطرة فيها بعد.'
from public.agriculture_sales s
join public.agriculture_sale_lines sl on sl.sale_id=s.id
join public.harvest_lots l on l.id=sl.harvest_lot_id
where s.status in ('DRAFT','APPROVED')
group by s.organization_id,s.project_id,l.crop_cycle_id;

-- PostgreSQL resolves view dependencies at creation. The result projection
-- above refers to the issue view, so rebuild it now that the issue view exists.
-- The temporary dependency ordering is handled by creating a harmless empty
-- shell before the result view in environments that replay this migration.

-- ===========================================================================
-- 6. Close command: existing HARVESTING -> CLOSED transition, no second state
--    engine. Inventory and receivable warnings remain open and visible.
-- ===========================================================================
create or replace function public.close_crop_cycle(
  p_organization_id uuid,p_project_id uuid,p_crop_cycle_id uuid,
  p_close_reason text,p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_existing public.crop_cycle_closeouts%rowtype;
  v_hash text; v_history_id uuid; v_id uuid; v_issue record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_close_reason is null or char_length(trim(p_close_reason)) not between 3 and 500 then
    raise exception 'crop cycle close reason is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'crop cycle close evidence is required';
  end if;
  select encode(digest(jsonb_build_object('project_id',p_project_id,
    'crop_cycle_id',p_crop_cycle_id,'close_reason',trim(p_close_reason),
    'evidence_reference',trim(p_evidence_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':gf019-close:'||trim(p_idempotency_key),0));
  select * into v_existing from public.crop_cycle_closeouts
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform 1 from public.crop_cycles c where c.id=p_crop_cycle_id
    and c.organization_id=p_organization_id and c.project_id=p_project_id for update;
  if not found then raise exception 'crop cycle not found in project'; end if;
  if public.agriculture_current_cycle_state(p_crop_cycle_id)<>'HARVESTING' then
    raise exception 'crop cycle must be HARVESTING before close';
  end if;
  select * into v_issue from public.crop_cycle_integrity_issues_read i
    where i.crop_cycle_id=p_crop_cycle_id and i.severity='HARD' order by i.code limit 1;
  if found then raise exception 'crop cycle close blocked: %',v_issue.code; end if;

  v_history_id:=public.transition_crop_cycle(
    p_organization_id,p_crop_cycle_id,'HARVESTING','CLOSED',trim(p_close_reason),
    trim(p_evidence_reference),'gf019-close-'||substr(v_hash,1,40));
  insert into public.crop_cycle_closeouts(
    organization_id,project_id,crop_cycle_id,closing_state_history_id,
    close_reason,evidence_reference,closed_by,idempotency_key,request_hash
  ) values(
    p_organization_id,p_project_id,p_crop_cycle_id,v_history_id,
    trim(p_close_reason),trim(p_evidence_reference),v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  -- transition_crop_cycle already emits the single canonical lifecycle audit
  -- carrying actor, reason and evidence. Do not append a redundant success audit.
  return v_id;
end $$;

create or replace view public.crop_cycle_closeouts_read with (security_invoker=on) as
select co.id,co.organization_id,co.project_id,co.crop_cycle_id,co.closing_state_history_id,
  co.close_reason,co.evidence_reference,co.closed_by,co.closed_at,
  r.recognized_revenue_minor_units,r.cash_collected_minor_units,
  r.receivable_outstanding_minor_units,r.attributed_operating_cost_minor_units,
  r.operating_result_to_date_minor_units,r.remaining_physical_inventory,
  r.remaining_inventory_value_status,r.open_exception_count,r.open_exception_codes
from public.crop_cycle_closeouts co join public.crop_cycle_results_read r on r.crop_cycle_id=co.crop_cycle_id;

-- ===========================================================================
-- 7. Tenant security, command-only writes and portable pgcrypto qualification
-- ===========================================================================
do $$ declare t text; begin
  foreach t in array array['crop_cycle_cost_attributions','crop_cycle_closeouts'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;
grant select on public.crop_cycle_cost_sources_read,public.crop_cycle_cost_attributions_read,
  public.crop_cycle_integrity_issues_read,public.crop_cycle_results_read,
  public.crop_cycle_closeouts_read to authenticated;

revoke all on function public.attribute_crop_cycle_cost(uuid,uuid,uuid,uuid,uuid,bigint,text,text,text,text) from public,anon;
revoke all on function public.reverse_crop_cycle_cost_attribution(uuid,uuid,text,text,text) from public,anon;
revoke all on function public.close_crop_cycle(uuid,uuid,uuid,text,text,text) from public,anon;
grant execute on function public.attribute_crop_cycle_cost(uuid,uuid,uuid,uuid,uuid,bigint,text,text,text,text),
  public.reverse_crop_cycle_cost_attribution(uuid,uuid,text,text,text),
  public.close_crop_cycle(uuid,uuid,uuid,text,text,text) to authenticated;

-- Trigger/helper functions are internal only.
revoke all on function public.gf019_guard_cost_attribution_insert(),
  public.gf019_guard_facts_immutable(),public.gf019_guard_attributed_cost_source_reversal()
from public,anon,authenticated;

do $pgcrypto_compat$ declare v_schema text; v record; d text; r text; begin
  select n.nspname into v_schema from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  if v_schema is null then raise exception 'GF-019 requires pgcrypto'; end if;
  for v in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname in (
      'attribute_crop_cycle_cost','reverse_crop_cycle_cost_attribution','close_crop_cycle'
    ) loop
    d:=pg_get_functiondef(v.oid);
    if d~'(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      r:=regexp_replace(d,'(^|[^[:alnum:]_.])digest[[:space:]]*\(',E'\\1'||quote_ident(v_schema)||'.digest(','g');
      execute r;
    end if;
  end loop;
end $pgcrypto_compat$;

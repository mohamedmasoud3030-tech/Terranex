-- GF-020 — Livestock Sector Foundation.
-- Cohort-first operational truth: Project -> Site -> Herd -> Cohort.
-- A site is an operating location, never evidence of land/property ownership.
-- Purchased origin is quantity provenance only and creates no Finance artifact.

-- Extend the applied project-sector invariant through a forward migration.
alter table public.investment_projects drop constraint investment_projects_sector_check;
alter table public.investment_projects add constraint investment_projects_sector_check
  check (sector in ('REAL_ESTATE','AGRICULTURE','LIVESTOCK'));

create or replace function public.create_investment_project(
  p_organization_id uuid, p_name text, p_internal_reference text,
  p_description text, p_sector text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_sector text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then raise exception 'invalid project name'; end if;
  if p_internal_reference is not null and char_length(trim(p_internal_reference)) > 80 then raise exception 'invalid internal reference'; end if;
  if p_description is not null and char_length(trim(p_description)) > 2000 then raise exception 'invalid description'; end if;
  v_sector:=upper(trim(coalesce(p_sector,'')));
  if v_sector not in ('REAL_ESTATE','AGRICULTURE','LIVESTOCK') then raise exception 'invalid sector'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':project:'||lower(trim(p_name))||':'||v_sector,0));
  select * into v_existing from public.investment_projects
   where organization_id=p_organization_id and sector=v_sector and lower(trim(name))=lower(trim(p_name)) limit 1;
  if found then return v_existing.id; end if;
  insert into public.investment_projects(organization_id,name,internal_reference,description,sector)
  values(p_organization_id,trim(p_name),nullif(trim(p_internal_reference),''),nullif(trim(p_description),''),v_sector)
  returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROJECT_CREATED','investment_project',v_id,jsonb_build_object('name',trim(p_name),'sector',v_sector));
  return v_id;
end $$;

create table public.livestock_project_profiles(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null,
 project_id uuid not null, notes text check(notes is null or char_length(trim(notes)) between 3 and 2000),
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 idempotency_key text not null check(char_length(idempotency_key) between 8 and 120), request_hash text not null check(char_length(request_hash)=64),
 unique(project_id), unique(id,organization_id,project_id), unique(organization_id,idempotency_key),
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id) on delete restrict
);

create table public.livestock_sites(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, project_id uuid not null,
 name text not null check(char_length(trim(name)) between 2 and 160),
 internal_reference text not null check(char_length(trim(internal_reference)) between 1 and 80),
 site_type text not null check(site_type in ('FARM','BARN','PASTURE','OTHER')),
 location_description text check(location_description is null or char_length(trim(location_description)) between 2 and 500),
 notes text check(notes is null or char_length(trim(notes)) between 3 and 2000),
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 idempotency_key text not null check(char_length(idempotency_key) between 8 and 120), request_hash text not null check(char_length(request_hash)=64),
 unique(id,organization_id,project_id), unique(organization_id,idempotency_key), unique(organization_id,project_id,internal_reference),
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id) on delete restrict
);
create index livestock_sites_project_idx on public.livestock_sites(project_id);

create table public.livestock_herds(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, project_id uuid not null, site_id uuid not null,
 name text not null check(char_length(trim(name)) between 2 and 160),
 internal_reference text not null check(char_length(trim(internal_reference)) between 1 and 80),
 species text not null check(species in ('CATTLE','BUFFALO','SHEEP','GOAT')),
 purpose text not null check(purpose in ('MEAT','BREEDING','MIXED')),
 breed_descriptor text check(breed_descriptor is null or char_length(trim(breed_descriptor)) between 2 and 120),
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 idempotency_key text not null check(char_length(idempotency_key) between 8 and 120), request_hash text not null check(char_length(request_hash)=64),
 unique(id,organization_id,project_id), unique(organization_id,idempotency_key), unique(organization_id,project_id,internal_reference),
 foreign key(site_id,organization_id,project_id) references public.livestock_sites(id,organization_id,project_id) on delete restrict,
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id) on delete restrict
);
create index livestock_herds_project_idx on public.livestock_herds(project_id);

create table public.livestock_cohorts(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, project_id uuid not null, herd_id uuid not null,
 cohort_reference text not null check(char_length(trim(cohort_reference)) between 1 and 100),
 origin_type text not null check(origin_type in ('PURCHASED','BORN','CONTRIBUTED_IN_KIND','TRANSFERRED_IN','OPENING_BALANCE')),
 origin_date date not null, opening_headcount integer not null check(opening_headcount > 0),
 sex_composition text check(sex_composition is null or sex_composition in ('MALE','FEMALE','MIXED')),
 breed_descriptor text check(breed_descriptor is null or char_length(trim(breed_descriptor)) between 2 and 120),
 opening_weight_value numeric(18,3) check(opening_weight_value is null or opening_weight_value > 0),
 opening_weight_unit text check(opening_weight_unit is null or opening_weight_unit='KG'),
 opening_weight_basis text check(opening_weight_basis is null or opening_weight_basis in ('INDIVIDUAL_MEASURED','COHORT_TOTAL','SAMPLED_AVERAGE','ESTIMATED')),
 origin_evidence_reference text check(origin_evidence_reference is null or char_length(trim(origin_evidence_reference)) between 2 and 200),
 notes text check(notes is null or char_length(trim(notes)) between 3 and 2000),
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 idempotency_key text not null check(char_length(idempotency_key) between 8 and 120), request_hash text not null check(char_length(request_hash)=64),
 constraint livestock_cohort_weight_complete check(
   (opening_weight_value is null and opening_weight_unit is null and opening_weight_basis is null) or
   (opening_weight_value is not null and opening_weight_unit is not null and opening_weight_basis is not null)),
 unique(id,organization_id,project_id), unique(organization_id,idempotency_key), unique(organization_id,project_id,cohort_reference),
 foreign key(herd_id,organization_id,project_id) references public.livestock_herds(id,organization_id,project_id) on delete restrict,
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id) on delete restrict
);
create index livestock_cohorts_project_idx on public.livestock_cohorts(project_id);

create table public.livestock_cohort_state_history(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, project_id uuid not null, cohort_id uuid not null,
 previous_history_id uuid, previous_state text check(previous_state is null or previous_state in ('PLANNED','ACTIVE')),
 new_state text not null check(new_state in ('PLANNED','ACTIVE')),
 reason text not null check(char_length(trim(reason)) between 3 and 500),
 evidence_reference text check(evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
 changed_by uuid not null references auth.users(id) on delete restrict, changed_at timestamptz not null default now(),
 idempotency_key text not null check(char_length(idempotency_key) between 8 and 120), request_hash text not null check(char_length(request_hash)=64),
 unique(id,organization_id,project_id), unique(organization_id,idempotency_key), unique(previous_history_id),
 foreign key(cohort_id,organization_id,project_id) references public.livestock_cohorts(id,organization_id,project_id) on delete restrict,
 foreign key(previous_history_id,organization_id,project_id) references public.livestock_cohort_state_history(id,organization_id,project_id) on delete restrict
);
create index livestock_cohort_history_idx on public.livestock_cohort_state_history(cohort_id,changed_at);

create function public.gf020_hash(p text) returns text language sql immutable set search_path=pg_catalog
as $$ select md5(p)||md5('gf020|'||p) $$;

create function public.gf020_require_project(p_org uuid,p_project uuid) returns void
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if not exists(select 1 from public.investment_projects where id=p_project and organization_id=p_org and sector='LIVESTOCK')
 then raise exception 'livestock project not found'; end if;
end $$;

-- Privileged/import paths cannot bypass sector identity either.
create function public.gf020_sector_guard() returns trigger language plpgsql
set search_path=pg_catalog,public as $$ begin
 if not exists(select 1 from public.investment_projects p where p.id=new.project_id and p.organization_id=new.organization_id and p.sector='LIVESTOCK')
 then raise exception 'livestock project not found'; end if; return new;
end $$;
create trigger livestock_profiles_sector_guard before insert on public.livestock_project_profiles for each row execute function public.gf020_sector_guard();
create trigger livestock_sites_sector_guard before insert on public.livestock_sites for each row execute function public.gf020_sector_guard();
create trigger livestock_herds_sector_guard before insert on public.livestock_herds for each row execute function public.gf020_sector_guard();
create trigger livestock_cohorts_sector_guard before insert on public.livestock_cohorts for each row execute function public.gf020_sector_guard();
create trigger livestock_history_sector_guard before insert on public.livestock_cohort_state_history for each row execute function public.gf020_sector_guard();

create function public.create_livestock_profile(p_organization_id uuid,p_project_id uuid,p_notes text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid;
begin
 if v_actor is null then raise exception 'authentication required'; end if;
 if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
 v_hash:=public.gf020_hash(p_project_id::text||'|'||coalesce(trim(p_notes),''));
 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ls-profile:'||trim(p_idempotency_key),0));
 select * into v_row from public.livestock_project_profiles where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
 if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
 perform public.gf020_require_project(p_organization_id,p_project_id);
 perform pg_advisory_xact_lock(hashtextextended(p_project_id::text||':livestock-profile',0));
 if exists(select 1 from public.livestock_project_profiles where project_id=p_project_id) then raise exception 'livestock profile already exists'; end if;
 insert into public.livestock_project_profiles(organization_id,project_id,notes,created_by,idempotency_key,request_hash)
 values(p_organization_id,p_project_id,nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
 insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
 values(p_organization_id,v_actor,'LIVESTOCK_PROFILE_CREATED','livestock_project_profile',v_id,jsonb_build_object('project_id',p_project_id)); return v_id;
end $$;

create function public.create_livestock_site(p_organization_id uuid,p_project_id uuid,p_name text,p_internal_reference text,p_site_type text,p_location_description text,p_notes text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_type text:=upper(trim(coalesce(p_site_type,'')));
begin
 if v_actor is null then raise exception 'authentication required'; end if;
 if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
 v_hash:=public.gf020_hash(p_project_id::text||'|'||trim(coalesce(p_name,''))||'|'||upper(trim(coalesce(p_internal_reference,'')))||'|'||v_type||'|'||coalesce(trim(p_location_description),'')||'|'||coalesce(trim(p_notes),''));
 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ls-site:'||trim(p_idempotency_key),0));
 select * into v_row from public.livestock_sites where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
 if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
 perform public.gf020_require_project(p_organization_id,p_project_id);
 perform pg_advisory_xact_lock(hashtextextended(p_project_id::text||':livestock-site-ref:'||upper(trim(coalesce(p_internal_reference,''))),0));
 if v_type not in ('FARM','BARN','PASTURE','OTHER') then raise exception 'invalid livestock site type'; end if;
 if p_name is null or char_length(trim(p_name)) not between 2 and 160 then raise exception 'invalid livestock site name'; end if;
 if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then raise exception 'invalid livestock site reference'; end if;
 if exists(select 1 from public.livestock_sites where organization_id=p_organization_id and project_id=p_project_id and internal_reference=upper(trim(p_internal_reference))) then raise exception 'livestock site reference already exists'; end if;
 insert into public.livestock_sites(organization_id,project_id,name,internal_reference,site_type,location_description,notes,created_by,idempotency_key,request_hash)
 values(p_organization_id,p_project_id,trim(p_name),upper(trim(p_internal_reference)),v_type,nullif(trim(p_location_description),''),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
 insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
 values(p_organization_id,v_actor,'LIVESTOCK_SITE_CREATED','livestock_site',v_id,jsonb_build_object('project_id',p_project_id,'site_type',v_type)); return v_id;
end $$;

create function public.create_livestock_herd(p_organization_id uuid,p_project_id uuid,p_site_id uuid,p_name text,p_internal_reference text,p_species text,p_purpose text,p_breed_descriptor text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_species text:=upper(trim(coalesce(p_species,''))); v_purpose text:=upper(trim(coalesce(p_purpose,'')));
begin
 if v_actor is null then raise exception 'authentication required'; end if; if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
 v_hash:=public.gf020_hash(p_project_id::text||'|'||p_site_id::text||'|'||trim(coalesce(p_name,''))||'|'||upper(trim(coalesce(p_internal_reference,'')))||'|'||v_species||'|'||v_purpose||'|'||coalesce(trim(p_breed_descriptor),''));
 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ls-herd:'||trim(p_idempotency_key),0));
 select * into v_row from public.livestock_herds where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
 if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
 perform public.gf020_require_project(p_organization_id,p_project_id);
 perform pg_advisory_xact_lock(hashtextextended(p_project_id::text||':livestock-herd-ref:'||upper(trim(coalesce(p_internal_reference,''))),0));
 if not exists(select 1 from public.livestock_sites where id=p_site_id and organization_id=p_organization_id and project_id=p_project_id) then raise exception 'livestock site not found'; end if;
 if v_species not in ('CATTLE','BUFFALO','SHEEP','GOAT') then raise exception 'invalid livestock species'; end if;
 if v_purpose not in ('MEAT','BREEDING','MIXED') then raise exception 'invalid livestock purpose'; end if;
 if p_name is null or char_length(trim(p_name)) not between 2 and 160 then raise exception 'invalid livestock herd name'; end if;
 if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then raise exception 'invalid livestock herd reference'; end if;
 if exists(select 1 from public.livestock_herds where organization_id=p_organization_id and project_id=p_project_id and internal_reference=upper(trim(p_internal_reference))) then raise exception 'livestock herd reference already exists'; end if;
 insert into public.livestock_herds(organization_id,project_id,site_id,name,internal_reference,species,purpose,breed_descriptor,created_by,idempotency_key,request_hash)
 values(p_organization_id,p_project_id,p_site_id,trim(p_name),upper(trim(p_internal_reference)),v_species,v_purpose,nullif(trim(p_breed_descriptor),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
 insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
 values(p_organization_id,v_actor,'LIVESTOCK_HERD_CREATED','livestock_herd',v_id,jsonb_build_object('project_id',p_project_id,'site_id',p_site_id,'species',v_species,'purpose',v_purpose)); return v_id;
end $$;

create function public.create_livestock_cohort(p_organization_id uuid,p_project_id uuid,p_herd_id uuid,p_cohort_reference text,p_origin_type text,p_origin_date date,p_opening_headcount integer,p_sex_composition text,p_breed_descriptor text,p_opening_weight_value numeric,p_opening_weight_unit text,p_opening_weight_basis text,p_origin_evidence_reference text,p_notes text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_history uuid; v_origin text:=upper(trim(coalesce(p_origin_type,''))); v_sex text:=nullif(upper(trim(coalesce(p_sex_composition,''))),''); v_unit text:=nullif(upper(trim(coalesce(p_opening_weight_unit,''))),''); v_basis text:=nullif(upper(trim(coalesce(p_opening_weight_basis,''))),'');
begin
 if v_actor is null then raise exception 'authentication required'; end if; if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
 v_hash:=public.gf020_hash(p_project_id::text||'|'||p_herd_id::text||'|'||upper(trim(coalesce(p_cohort_reference,'')))||'|'||v_origin||'|'||coalesce(p_origin_date::text,'')||'|'||coalesce(p_opening_headcount::text,'')||'|'||coalesce(v_sex,'')||'|'||coalesce(trim(p_breed_descriptor),'')||'|'||coalesce(p_opening_weight_value::text,'')||'|'||coalesce(v_unit,'')||'|'||coalesce(v_basis,'')||'|'||coalesce(trim(p_origin_evidence_reference),'')||'|'||coalesce(trim(p_notes),''));
 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ls-cohort:'||trim(p_idempotency_key),0));
 select * into v_row from public.livestock_cohorts where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
 if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
 perform public.gf020_require_project(p_organization_id,p_project_id);
 perform pg_advisory_xact_lock(hashtextextended(p_project_id::text||':livestock-cohort-ref:'||upper(trim(coalesce(p_cohort_reference,''))),0));
 if not exists(select 1 from public.livestock_herds where id=p_herd_id and organization_id=p_organization_id and project_id=p_project_id) then raise exception 'livestock herd not found'; end if;
 if v_origin not in ('PURCHASED','BORN','CONTRIBUTED_IN_KIND','TRANSFERRED_IN','OPENING_BALANCE') then raise exception 'invalid livestock cohort origin'; end if;
 if p_origin_date is null then raise exception 'invalid livestock cohort origin date'; end if;
 if p_opening_headcount is null or p_opening_headcount<=0 then raise exception 'invalid livestock opening headcount'; end if;
 if v_sex is not null and v_sex not in ('MALE','FEMALE','MIXED') then raise exception 'invalid livestock sex composition'; end if;
 if (p_opening_weight_value is null)!=(v_unit is null) or (p_opening_weight_value is null)!=(v_basis is null) then raise exception 'invalid livestock opening weight'; end if;
 if p_opening_weight_value is not null and (p_opening_weight_value<=0 or v_unit<>'KG' or v_basis not in ('INDIVIDUAL_MEASURED','COHORT_TOTAL','SAMPLED_AVERAGE','ESTIMATED')) then raise exception 'invalid livestock opening weight'; end if;
 if p_cohort_reference is null or char_length(trim(p_cohort_reference)) not between 1 and 100 then raise exception 'invalid livestock cohort reference'; end if;
 if exists(select 1 from public.livestock_cohorts where organization_id=p_organization_id and project_id=p_project_id and cohort_reference=upper(trim(p_cohort_reference))) then raise exception 'livestock cohort reference already exists'; end if;
 insert into public.livestock_cohorts(organization_id,project_id,herd_id,cohort_reference,origin_type,origin_date,opening_headcount,sex_composition,breed_descriptor,opening_weight_value,opening_weight_unit,opening_weight_basis,origin_evidence_reference,notes,created_by,idempotency_key,request_hash)
 values(p_organization_id,p_project_id,p_herd_id,upper(trim(p_cohort_reference)),v_origin,p_origin_date,p_opening_headcount,v_sex,nullif(trim(p_breed_descriptor),''),p_opening_weight_value,v_unit,v_basis,nullif(trim(p_origin_evidence_reference),''),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
 insert into public.livestock_cohort_state_history(organization_id,project_id,cohort_id,previous_history_id,previous_state,new_state,reason,changed_by,idempotency_key,request_hash)
 values(p_organization_id,p_project_id,v_id,null,null,'PLANNED','إنشاء الدفعة',v_actor,'initial-'||v_id::text,public.gf020_hash(v_id::text||'|PLANNED')) returning id into v_history;
 insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
 values(p_organization_id,v_actor,'LIVESTOCK_COHORT_CREATED','livestock_cohort',v_id,jsonb_build_object('project_id',p_project_id,'herd_id',p_herd_id,'origin_type',v_origin,'opening_headcount',p_opening_headcount,'initial_state','PLANNED')); return v_id;
end $$;

create function public.livestock_current_cohort_tip(p_cohort_id uuid) returns uuid language sql stable security invoker set search_path=pg_catalog,public as $$
 select h.id from public.livestock_cohort_state_history h where h.cohort_id=p_cohort_id and not exists(select 1 from public.livestock_cohort_state_history n where n.previous_history_id=h.id) limit 1
$$;
create function public.livestock_current_cohort_state(p_cohort_id uuid) returns text language sql stable security invoker set search_path=pg_catalog,public as $$
 select new_state from public.livestock_cohort_state_history where id=public.livestock_current_cohort_tip(p_cohort_id)
$$;

create function public.transition_livestock_cohort(p_organization_id uuid,p_project_id uuid,p_cohort_id uuid,p_expected_state text,p_new_state text,p_reason text,p_evidence_reference text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_cohort record; v_tip uuid; v_state text; v_id uuid;
begin
 if v_actor is null then raise exception 'authentication required'; end if; if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
 v_hash:=public.gf020_hash(p_project_id::text||'|'||p_cohort_id::text||'|'||upper(trim(coalesce(p_expected_state,'')))||'|'||upper(trim(coalesce(p_new_state,'')))||'|'||trim(coalesce(p_reason,''))||'|'||coalesce(trim(p_evidence_reference),''));
 perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ls-transition:'||trim(p_idempotency_key),0));
 select * into v_row from public.livestock_cohort_state_history where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
 if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
 perform public.gf020_require_project(p_organization_id,p_project_id);
 select * into v_cohort from public.livestock_cohorts where id=p_cohort_id and organization_id=p_organization_id and project_id=p_project_id for update;
 if not found then raise exception 'livestock cohort not found'; end if;
 v_tip:=public.livestock_current_cohort_tip(p_cohort_id); select new_state into v_state from public.livestock_cohort_state_history where id=v_tip;
 if v_state<>upper(trim(p_expected_state)) then raise exception 'expected livestock cohort state mismatch'; end if;
 if not(v_state='PLANNED' and upper(trim(p_new_state))='ACTIVE') then raise exception 'invalid livestock cohort transition'; end if;
 if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'invalid livestock transition reason'; end if;
 insert into public.livestock_cohort_state_history(organization_id,project_id,cohort_id,previous_history_id,previous_state,new_state,reason,evidence_reference,changed_by,idempotency_key,request_hash)
 values(p_organization_id,p_project_id,p_cohort_id,v_tip,v_state,'ACTIVE',trim(p_reason),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
 insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
 values(p_organization_id,v_actor,'LIVESTOCK_COHORT_STATE_CHANGED','livestock_cohort',p_cohort_id,jsonb_build_object('project_id',p_project_id,'previous_state',v_state,'new_state','ACTIVE','reason',trim(p_reason))); return v_id;
end $$;

create function public.gf020_immutable() returns trigger language plpgsql set search_path=pg_catalog,public as $$ begin raise exception 'livestock origin and lifecycle facts are append-only'; end $$;
create trigger livestock_cohorts_no_change before update or delete on public.livestock_cohorts for each row execute function public.gf020_immutable();
create trigger livestock_cohort_history_no_change before update or delete on public.livestock_cohort_state_history for each row execute function public.gf020_immutable();

-- Site is derived through Herd; cohort does not duplicate a mutable site/species/purpose.
create view public.livestock_sites_read with(security_invoker=on) as select id,organization_id,project_id,name,internal_reference,site_type,location_description,notes,created_by,created_at from public.livestock_sites;
create view public.livestock_herds_read with(security_invoker=on) as
 select h.id,h.organization_id,h.project_id,h.site_id,s.name site_name,h.name,h.internal_reference,h.species,h.purpose,h.breed_descriptor,h.created_by,h.created_at from public.livestock_herds h join public.livestock_sites s on (s.id,s.organization_id,s.project_id)=(h.site_id,h.organization_id,h.project_id);
create view public.livestock_cohorts_read with(security_invoker=on) as
 select c.id,c.organization_id,c.project_id,c.herd_id,h.name herd_name,h.internal_reference herd_reference,h.species,h.purpose,h.site_id,s.name site_name,c.cohort_reference,c.origin_type,c.origin_date,c.opening_headcount,c.sex_composition,coalesce(c.breed_descriptor,h.breed_descriptor) breed_descriptor,c.opening_weight_value::text opening_weight_value,c.opening_weight_unit,c.opening_weight_basis,c.origin_evidence_reference,c.notes,c.created_by,c.created_at,public.livestock_current_cohort_state(c.id) lifecycle_state
 from public.livestock_cohorts c join public.livestock_herds h on (h.id,h.organization_id,h.project_id)=(c.herd_id,c.organization_id,c.project_id) join public.livestock_sites s on (s.id,s.organization_id,s.project_id)=(h.site_id,h.organization_id,h.project_id);
create view public.livestock_cohort_timeline_read with(security_invoker=on) as select id,organization_id,project_id,cohort_id,previous_state,new_state,reason,evidence_reference,changed_by,changed_at from public.livestock_cohort_state_history;

do $$ declare t text; begin foreach t in array array['livestock_project_profiles','livestock_sites','livestock_herds','livestock_cohorts','livestock_cohort_state_history'] loop
 execute format('alter table public.%I enable row level security',t); execute format('alter table public.%I force row level security',t);
 execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t); execute format('grant select on public.%I to authenticated',t);
end loop; end $$;
revoke all on public.livestock_sites_read,public.livestock_herds_read,public.livestock_cohorts_read,public.livestock_cohort_timeline_read from public,anon;
grant select on public.livestock_sites_read,public.livestock_herds_read,public.livestock_cohorts_read,public.livestock_cohort_timeline_read to authenticated;

revoke all on function public.gf020_hash(text),public.gf020_require_project(uuid,uuid),public.gf020_sector_guard(),public.gf020_immutable(),public.livestock_current_cohort_tip(uuid),public.livestock_current_cohort_state(uuid) from public,anon,authenticated;
grant execute on function public.livestock_current_cohort_tip(uuid),public.livestock_current_cohort_state(uuid) to authenticated;
revoke all on function public.create_livestock_profile(uuid,uuid,text,text),public.create_livestock_site(uuid,uuid,text,text,text,text,text,text),public.create_livestock_herd(uuid,uuid,uuid,text,text,text,text,text,text),public.create_livestock_cohort(uuid,uuid,uuid,text,text,date,integer,text,text,numeric,text,text,text,text,text),public.transition_livestock_cohort(uuid,uuid,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.create_livestock_profile(uuid,uuid,text,text),public.create_livestock_site(uuid,uuid,text,text,text,text,text,text),public.create_livestock_herd(uuid,uuid,uuid,text,text,text,text,text,text),public.create_livestock_cohort(uuid,uuid,uuid,text,text,date,integer,text,text,numeric,text,text,text,text,text),public.transition_livestock_cohort(uuid,uuid,uuid,text,text,text,text,text) to authenticated;

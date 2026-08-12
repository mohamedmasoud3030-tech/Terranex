-- GF-008 / S5 — replace the obsolete commitment-coupled rule command.

revoke all on function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text)
from public,anon,authenticated;
drop function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text);

create or replace function public.s5_configure_allocation_rules(
  p_organization_id uuid,p_project_id uuid,p_governing_version_id uuid,p_policy text,
  p_participant_party_ids uuid[],p_weight_numerators bigint[],p_common_denominator bigint,
  p_basis_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid; v_hash text; v_lines jsonb; v_existing record;
  v_expected integer; v_actual integer; v_sum numeric; v_effective_from date; v_effective_to date;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_policy not in ('PRO_RATA','FIXED_SHARES') then raise exception 'unsupported allocation policy'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_basis_evidence_reference is null or char_length(trim(p_basis_evidence_reference)) not between 3 and 200 then
    raise exception 'allocation basis evidence reference is required';
  end if;
  if p_common_denominator is null or p_common_denominator<=0 then raise exception 'allocation denominator must be positive'; end if;
  if p_participant_party_ids is null or p_weight_numerators is null
     or cardinality(p_participant_party_ids)=0
     or cardinality(p_participant_party_ids)<>cardinality(p_weight_numerators) then
    raise exception 'participant and weight arrays must be non-empty and aligned';
  end if;
  select count(distinct x) into v_actual from unnest(p_participant_party_ids) x;
  if v_actual<>cardinality(p_participant_party_ids) then raise exception 'duplicate participant in allocation rules'; end if;
  if exists(select 1 from unnest(p_weight_numerators) n where n is null or n<=0) then raise exception 'allocation weights must be positive integers'; end if;
  select coalesce(sum(n::numeric),0) into v_sum from unnest(p_weight_numerators) n;
  if v_sum<>p_common_denominator::numeric then raise exception 'allocation weights must resolve exactly to 100 percent'; end if;

  select av.effective_date,
         (select min(next_av.effective_date)-1
          from public.agreement_versions next_av
          where next_av.organization_id=av.organization_id
            and next_av.project_id=av.project_id
            and next_av.effective_date>av.effective_date)
    into v_effective_from,v_effective_to
  from public.agreement_versions av
  where av.id=p_governing_version_id and av.organization_id=p_organization_id
    and av.project_id=p_project_id and av.status in ('ACTIVE','SUPERSEDED');
  if v_effective_from is null then raise exception 'allocation rules require an activated governing agreement version'; end if;

  select count(*) into v_expected
  from public.commitment_terms ct
  join public.project_participants pp on pp.id=ct.participant_id
  where ct.organization_id=p_organization_id and ct.agreement_version_id=p_governing_version_id
    and pp.project_id=p_project_id and pp.role='INVESTOR';
  if v_expected<>cardinality(p_participant_party_ids) or exists(
    select 1
    from public.commitment_terms ct
    join public.project_participants pp on pp.id=ct.participant_id
    where ct.organization_id=p_organization_id and ct.agreement_version_id=p_governing_version_id
      and pp.project_id=p_project_id and pp.role='INVESTOR'
      and not (pp.party_id=any(p_participant_party_ids))
  ) then raise exception 'allocation rules must cover every investor in the governing version exactly once'; end if;

  select jsonb_agg(jsonb_build_object('party_id',x.party_id,'numerator',x.numerator) order by x.party_id::text)
    into v_lines
  from unnest(p_participant_party_ids,p_weight_numerators) as x(party_id,numerator);
  v_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'governing_version_id',p_governing_version_id,
    'policy',p_policy,'common_denominator',p_common_denominator,'lines',v_lines,
    'basis_evidence_reference',trim(p_basis_evidence_reference),
    'effective_from',v_effective_from,'effective_to',v_effective_to
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-rules:'||trim(p_idempotency_key),0));
  select * into v_existing from public.s5_allocation_rule_sets
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-rules-version:'||p_governing_version_id::text,0));
  if exists(select 1 from public.s5_allocation_rule_sets where organization_id=p_organization_id and project_id=p_project_id and governing_version_id=p_governing_version_id) then
    raise exception 'allocation rules are already frozen for this governing version';
  end if;

  insert into public.s5_allocation_rule_sets(
    organization_id,project_id,governing_version_id,policy,common_denominator,
    content_hash,idempotency_key,request_hash,created_by,basis_evidence_reference,effective_from,effective_to
  ) values(
    p_organization_id,p_project_id,p_governing_version_id,p_policy,p_common_denominator,
    v_hash,trim(p_idempotency_key),v_hash,v_actor,trim(p_basis_evidence_reference),v_effective_from,v_effective_to
  ) returning id into v_id;

  insert into public.s5_allocation_rules(
    organization_id,project_id,governing_version_id,rule_set_id,participant_party_id,
    weight_numerator,weight_denominator
  )
  select p_organization_id,p_project_id,p_governing_version_id,v_id,x.party_id,x.numerator,p_common_denominator
  from unnest(p_participant_party_ids,p_weight_numerators) as x(party_id,numerator);

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_ALLOCATION_RULES_FROZEN','s5_allocation_rule_set',v_id,
    jsonb_build_object('project_id',p_project_id,'governing_version_id',p_governing_version_id,
      'policy',p_policy,'participant_count',cardinality(p_participant_party_ids),'content_hash',v_hash,
      'basis_evidence_reference',trim(p_basis_evidence_reference),'effective_from',v_effective_from,'effective_to',v_effective_to));
  return v_id;
end $$;

grant execute on function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text,text)
to authenticated;

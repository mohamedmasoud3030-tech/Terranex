-- GF-008 / S5 — evidence-backed allocation-basis command.
-- Reuse the already-tested economic rule command instead of copying its full
-- validation/insertion implementation. The public 9-argument wrapper adds the
-- independent basis provenance required by ADR 0008.

revoke all on function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text)
from public,anon,authenticated;

create or replace function public.s5_configure_allocation_rules(
  p_organization_id uuid,p_project_id uuid,p_governing_version_id uuid,p_policy text,
  p_participant_party_ids uuid[],p_weight_numerators bigint[],p_common_denominator bigint,
  p_basis_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid();
  v_rule_set_id uuid;
  v_effective_from date;
  v_effective_to date;
  v_basis_hash text;
  v_existing_basis text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_basis_evidence_reference is null
     or char_length(trim(p_basis_evidence_reference)) not between 3 and 200 then
    raise exception 'allocation basis evidence reference is required';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select av.effective_date,
         (select min(next_av.effective_date)-1
          from public.agreement_versions next_av
          where next_av.organization_id=av.organization_id
            and next_av.project_id=av.project_id
            and next_av.effective_date>av.effective_date)
    into v_effective_from,v_effective_to
  from public.agreement_versions av
  where av.id=p_governing_version_id
    and av.organization_id=p_organization_id
    and av.project_id=p_project_id
    and av.status='ACTIVE';
  if v_effective_from is null then
    raise exception 'allocation rules require the active governing agreement version';
  end if;

  v_basis_hash:=encode(digest(jsonb_build_object(
    'organization_id',p_organization_id,
    'project_id',p_project_id,
    'governing_version_id',p_governing_version_id,
    'policy',p_policy,
    'participant_party_ids',p_participant_party_ids,
    'weight_numerators',p_weight_numerators,
    'common_denominator',p_common_denominator,
    'basis_evidence_reference',trim(p_basis_evidence_reference),
    'effective_from',v_effective_from,
    'effective_to',v_effective_to
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':s5-basis:'||trim(p_idempotency_key),0));

  select rs.id,b.basis_hash
    into v_rule_set_id,v_existing_basis
  from public.s5_allocation_rule_sets rs
  left join public.s5_allocation_rule_basis b
    on b.rule_set_id=rs.id and b.organization_id=rs.organization_id
  where rs.organization_id=p_organization_id
    and rs.idempotency_key=trim(p_idempotency_key);

  if v_rule_set_id is not null then
    if v_existing_basis is null or v_existing_basis<>v_basis_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_rule_set_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':s5-basis-version:'||p_governing_version_id::text,0));

  v_rule_set_id:=public.s5_configure_allocation_rules(
    p_organization_id,p_project_id,p_governing_version_id,p_policy,
    p_participant_party_ids,p_weight_numerators,p_common_denominator,
    trim(p_idempotency_key)
  );

  insert into public.s5_allocation_rule_basis(
    rule_set_id,organization_id,project_id,governing_version_id,
    basis_evidence_reference,effective_from,effective_to,basis_hash,created_by
  ) values(
    v_rule_set_id,p_organization_id,p_project_id,p_governing_version_id,
    trim(p_basis_evidence_reference),v_effective_from,v_effective_to,v_basis_hash,v_actor
  );

  insert into public.audit_events(
    organization_id,actor_id,event_type,entity_type,entity_id,payload
  ) values(
    p_organization_id,v_actor,'S5_ALLOCATION_BASIS_FROZEN','s5_allocation_rule_set',v_rule_set_id,
    jsonb_build_object(
      'project_id',p_project_id,
      'governing_version_id',p_governing_version_id,
      'basis_evidence_reference',trim(p_basis_evidence_reference),
      'effective_from',v_effective_from,
      'effective_to',v_effective_to,
      'basis_hash',v_basis_hash
    )
  );
  return v_rule_set_id;
end $$;

grant execute on function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text,text)
to authenticated;

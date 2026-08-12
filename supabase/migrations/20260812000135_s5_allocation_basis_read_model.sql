-- GF-008 / S5 — expose the independent allocation-basis provenance.

drop view if exists public.s5_rule_sets_read;
create view public.s5_rule_sets_read with (security_invoker=on) as
select rs.id as rule_set_id,rs.organization_id,rs.project_id,rs.governing_version_id,rs.policy,
  rs.common_denominator::text,rs.content_hash,rs.basis_evidence_reference,rs.effective_from,rs.effective_to,
  rs.created_by,rs.created_at,
  (select count(*) from public.s5_allocation_rules r where r.rule_set_id=rs.id) as participant_count
from public.s5_allocation_rule_sets rs;
grant select on public.s5_rule_sets_read to authenticated;

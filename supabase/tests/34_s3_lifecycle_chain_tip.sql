-- Regression for multiple lifecycle transitions inside one PostgreSQL
-- transaction. Current state/predecessor selection must follow the explicit
-- previous_history_id chain, never transaction-stable timestamps or random UUID
-- ordering.

select 1 / case when pg_get_functiondef('public.s3_current_property_state(uuid)'::regprocedure)
  like '%s3_property_history_tip_id%' then 1 else 0 end
  as property_current_state_uses_chain_tip;

select 1 / case when pg_get_functiondef('public.s3_current_phase_state(uuid)'::regprocedure)
  like '%s3_phase_history_tip_id%' then 1 else 0 end
  as phase_current_state_uses_chain_tip;

select 1 / case when pg_get_functiondef('public.s3_current_milestone_state(uuid)'::regprocedure)
  like '%s3_milestone_history_tip_id%' then 1 else 0 end
  as milestone_current_state_uses_chain_tip;

select 1 / case when pg_get_functiondef('public.transition_property_asset(uuid,uuid,text,text,text,text,text)'::regprocedure)
  not like '%order by h.changed_at desc,h.id desc limit 1%'
  and pg_get_functiondef('public.transition_property_asset(uuid,uuid,text,text,text,text,text)'::regprocedure)
    like '%s3_property_history_tip_id%' then 1 else 0 end
  as property_command_uses_causal_predecessor;

select 1 / case when pg_get_functiondef('public.transition_development_phase(uuid,uuid,text,text,text,text)'::regprocedure)
  not like '%order by h.changed_at desc,h.id desc limit 1%'
  and pg_get_functiondef('public.transition_development_phase(uuid,uuid,text,text,text,text)'::regprocedure)
    like '%s3_phase_history_tip_id%' then 1 else 0 end
  as phase_command_uses_causal_predecessor;

select 1 / case when pg_get_functiondef('public.transition_development_milestone(uuid,uuid,text,text,text,text)'::regprocedure)
  not like '%order by h.changed_at desc,h.id desc limit 1%'
  and pg_get_functiondef('public.transition_development_milestone(uuid,uuid,text,text,text,text)'::regprocedure)
    like '%s3_milestone_history_tip_id%' then 1 else 0 end
  as milestone_command_uses_causal_predecessor;

select 1 / case when pg_get_functiondef('public.s3_validate_property_transition()'::regprocedure)
  like '%s3_property_history_tip_id(new.property_asset_id)%' then 1 else 0 end
  as property_trigger_uses_causal_tip;

select 1 / case when pg_get_functiondef('public.s3_validate_phase_transition()'::regprocedure)
  like '%s3_phase_history_tip_id(new.phase_id)%' then 1 else 0 end
  as phase_trigger_uses_causal_tip;

select 1 / case when pg_get_functiondef('public.s3_validate_milestone_transition()'::regprocedure)
  like '%s3_milestone_history_tip_id(new.milestone_id)%' then 1 else 0 end
  as milestone_trigger_uses_causal_tip;

select 1 / case when pg_get_viewdef('public.property_asset_workspace_read'::regclass,true)
  like '%previous_history_id = h.id%' then 1 else 0 end
  as property_workspace_uses_causal_tip;

select 1 / case when pg_get_viewdef('public.development_phases_read'::regclass,true)
  like '%previous_history_id = h.id%' then 1 else 0 end
  as phase_read_model_uses_causal_tip;

select 1 / case when pg_get_viewdef('public.development_milestones_read'::regclass,true)
  like '%previous_history_id = h.id%' then 1 else 0 end
  as milestone_read_model_uses_causal_tip;

-- S4's later lifecycle extension must survive the forward rewrite.
select 1 / case when pg_get_functiondef('public.s3_validate_property_transition()'::regprocedure)
  like '%EXITING%' and pg_get_functiondef('public.s3_validate_property_transition()'::regprocedure)
  like '%DISPOSED%' then 1 else 0 end
  as s4_exit_states_preserved;

select 'S3 lifecycle causal chain-tip SQL PASS' as result;

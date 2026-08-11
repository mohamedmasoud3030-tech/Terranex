-- S1 keeps one governing agreement version. Participant membership and new
-- agreement drafts freeze once that version is active; amendment carry-forward
-- is deliberately deferred rather than guessed.

create or replace function public.s1_guard_participant_after_activation() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if exists (
    select 1 from public.agreement_versions av
    where av.project_id = new.project_id
      and av.organization_id = new.organization_id
      and av.status = 'ACTIVE'
  ) then
    raise exception 'project participants are frozen after agreement activation';
  end if;
  return new;
end $$;

drop trigger if exists participant_after_activation_guard on public.project_participants;
create trigger participant_after_activation_guard
before insert or update on public.project_participants
for each row execute function public.s1_guard_participant_after_activation();

create or replace function public.s1_guard_new_version_after_activation() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if exists (
    select 1 from public.agreement_versions av
    where av.project_id = new.project_id
      and av.organization_id = new.organization_id
      and av.status = 'ACTIVE'
  ) then
    raise exception 'agreement amendments are deferred while an active version governs the project';
  end if;
  return new;
end $$;

drop trigger if exists agreement_version_after_activation_guard on public.agreement_versions;
create trigger agreement_version_after_activation_guard
before insert on public.agreement_versions
for each row execute function public.s1_guard_new_version_after_activation();

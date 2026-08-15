-- GF-023 review regression — backdated optional identity must preserve the
-- authoritative GF-022 quantity timeline.

select id gf23t_project from investment_projects where internal_reference='GF020-LS-A' \gset
select id gf23t_site from livestock_sites where project_id=:'gf23t_project' and internal_reference='SITE-A' \gset
select id gf23t_herd from livestock_herds where project_id=:'gf23t_project' and internal_reference='HERD-A' \gset

-- ---------------------------------------------------------------------------
-- Case 1: one-head Cohort. A later T2 identity exists first; a subsequently
-- inserted T1 identity would make the immutable history contain 2 identities
-- against quantity 1 at T2, so it must be rejected.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,'دفعة رجعية GF023',
  'PURCHASED',current_date-10,1,'UNKNOWN',null,null,null,null,'دليل افتتاحي',null,'gf23-temporal-cohort-reject')
$q$,:'gf23t_project',:'gf23t_herd',:'gf23t_site')) gf23t_reject_cohort \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.transition_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE',
  'تفعيل اختبار الهوية الرجعية',null,'gf23-temporal-cohort-reject-active')
$q$,:'gf23t_project',:'gf23t_reject_cohort')) gf23t_reject_active \gset

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'EAR_TAG','GF023-T2-A','UNKNOWN',
  null,null,current_date::timestamptz-interval '1 day','دليل T2',null,'gf23-temporal-t2-a')
$q$,:'gf23t_project',:'gf23t_reject_cohort')) gf23t_t2_animal \gset

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'EAR_TAG','GF023-T1-B','UNKNOWN',
  null,null,current_date::timestamptz-interval '2 days','دليل T1',null,'gf23-temporal-t1-b')
$q$,:'gf23t_project',:'gf23t_reject_cohort')) like '%identified Animal count exceeds Cohort quantity%'
then 1 else 0 end as backdated_identity_rejected_when_later_checkpoint_would_overidentify;

select 1/case when
  (select count(*)=1 from livestock_animals where identification_cohort_id=:'gf23t_reject_cohort')
  and (select count(*)=1 from livestock_animal_memberships where cohort_id=:'gf23t_reject_cohort')
  and (select current_quantity=1 from livestock_cohort_quantity_rollforward where cohort_id=:'gf23t_reject_cohort')
then 1 else 0 end as rejected_backdate_preserves_identity_and_quantity_truth;

-- ---------------------------------------------------------------------------
-- Case 2: the same T2-then-T1 insertion is valid when an authoritative GF-022
-- quantity increase occurs between T1 and T2. At T1 there is 1 identity / 1
-- head; after the BIRTH checkpoint and at T2 there are 2 identities / 2 heads.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,'دفعة رجعية صالحة GF023',
  'BORN',current_date-10,1,'UNKNOWN',null,null,null,null,'دليل افتتاحي',null,'gf23-temporal-cohort-allow')
$q$,:'gf23t_project',:'gf23t_herd',:'gf23t_site')) gf23t_allow_cohort \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.transition_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE',
  'تفعيل اختبار الهوية الرجعية الصالحة',null,'gf23-temporal-cohort-allow-active')
$q$,:'gf23t_project',:'gf23t_allow_cohort')) gf23t_allow_active \gset

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_birth(
  '10000000-0000-4000-8000-000000000001',%L,%L,1,
  current_date::timestamptz-interval '36 hours','دليل ميلاد',null,'gf23-temporal-birth')
$q$,:'gf23t_project',:'gf23t_allow_cohort')) gf23t_birth_event \gset

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'EAR_TAG','GF023-ALLOW-T2-A','UNKNOWN',
  null,null,current_date::timestamptz-interval '1 day','دليل T2',null,'gf23-temporal-allow-t2-a')
$q$,:'gf23t_project',:'gf23t_allow_cohort')) gf23t_allow_t2_animal \gset

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'EAR_TAG','GF023-ALLOW-T1-B','UNKNOWN',
  null,null,current_date::timestamptz-interval '2 days','دليل T1',null,'gf23-temporal-allow-t1-b')
$q$,:'gf23t_project',:'gf23t_allow_cohort')) gf23t_allow_t1_animal \gset

select 1/case when
  (select count(*)=2 from livestock_animals where identification_cohort_id=:'gf23t_allow_cohort')
  and (select count(*)=2 from livestock_animal_memberships where cohort_id=:'gf23t_allow_cohort')
  and public.livestock_cohort_quantity_as_of(:'gf23t_allow_cohort', current_date::timestamptz-interval '2 days')=1
  and public.livestock_cohort_quantity_as_of(:'gf23t_allow_cohort', current_date::timestamptz-interval '1 day')=2
  and (select current_quantity=2 from livestock_cohort_quantity_rollforward where cohort_id=:'gf23t_allow_cohort')
then 1 else 0 end as backdated_identity_allowed_when_gf022_quantity_timeline_supports_it;

select 'GF-023 identity timeline hardening PASS' result;

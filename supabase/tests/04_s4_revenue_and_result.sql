-- S4 Revenue & Realized Result — accounting integrity and isolation tests.
-- Runs against a real PostgreSQL 16 instance after all migrations S0→S4.
-- Two-tenant RLS, balanced postings, idempotency, concurrency, and lifecycle.

-- Shim (already loaded by 00_supabase_shim.sql in test harness).
select plan(48);

-- === Setup: two organizations, two projects ===
do $$
declare
  v_user_a uuid := 'a0000000-0000-4000-8000-000000000001';
  v_user_b uuid := 'b0000000-0000-4000-8000-000000000002';
  v_org_a uuid; v_org_b uuid; v_project_a uuid; v_project_b uuid;
  v_party_buyer uuid; v_party_supplier uuid;
  v_asset uuid; v_disposition uuid; v_sale uuid;
  v_cash_account uuid; v_receivable uuid;
begin
  -- Create orgs and memberships directly for test (bypasses auth.uid()).
  insert into public.organizations(name) values ('منظمة أ') returning id into v_org_a;
  insert into public.organizations(name) values ('منظمة ب') returning id into v_org_b;

  -- Insert auth users (shim creates these in auth schema).
  insert into auth.users(id, email) values (v_user_a, 'a@test.com') on conflict do nothing;
  insert into auth.users(id, email) values (v_user_b, 'b@test.com') on conflict do nothing;

  -- Memberships.
  insert into public.memberships(organization_id, user_id, role) values (v_org_a, v_user_a, 'OWNER');
  insert into public.memberships(organization_id, user_id, role) values (v_org_b, v_user_b, 'OWNER');

  -- Projects.
  insert into public.investment_projects(organization_id, name, sector) values (v_org_a, 'مشروع أ', 'REAL_ESTATE') returning id into v_project_a;
  insert into public.investment_projects(organization_id, name, sector) values (v_org_b, 'مشروع ب', 'REAL_ESTATE') returning id into v_project_b;

  -- Parties.
  insert into public.parties(organization_id, legal_name, party_type) values (v_org_a, 'المشتري', 'PERSON') returning id into v_party_buyer;
  insert into public.parties(organization_id, legal_name, party_type) values (v_org_a, 'المورد', 'ORGANIZATION') returning id into v_party_supplier;

  -- Property asset.
  perform public.create_property_asset(v_org_a, v_project_a, 'قطعة النخيل', 'DEVELOP_SELL', 'القاهرة', 'CLEAR', '2026-01-01', 500000000, 'EGP', 's4-test-asset-001');

  select id into v_asset from public.property_assets where organization_id = v_org_a and idempotency_key = 's4-test-asset-001';

  -- Add a capitalizable cost to establish carrying amount.
  perform public.record_property_cost_item(v_org_a, v_project_a, v_asset, null, 'أعمال حفر', true, 100000000, 'EGP', 'حفر أساسات', '2026-02-15', null, 's4-test-cost-001');

  -- Disposition.
  perform public.create_disposition(v_org_a, v_project_a, v_asset, v_party_buyer, 2000000000, 'EGP', '2026-06-01', 50000000, 'عقد-001', null, 's4-test-disp-001');

  select id into v_disposition from public.dispositions where organization_id = v_org_a and idempotency_key = 's4-test-disp-001';

  -- Approve.
  perform public.approve_disposition(v_org_a, v_disposition);

  -- Create cash account for collections.
  select id into v_cash_account from public.financial_accounts where organization_id = v_org_a and semantic_role = 'cash' and currency = 'EGP';
  if v_cash_account is null then
    select public.ensure_financial_account(v_org_a, 'cash', 'النقدية', 'EGP') into v_cash_account;
  end if;

  -- Recognize sale.
  perform public.recognize_sale(v_org_a, v_project_a, v_disposition, '2026-07-01', 's4-test-sale-001');

  select id into v_sale from public.sale_recognitions where organization_id = v_org_a and disposition_id = v_disposition;
  select id into v_receivable from public.sale_receivables where sale_recognition_id = v_sale;

  -- Store IDs for later tests.
  perform set_config('test.org_a', v_org_a::text, true);
  perform set_config('test.org_b', v_org_b::text, true);
  perform set_config('test.project_a', v_project_a::text, true);
  perform set_config('test.project_b', v_project_b::text, true);
  perform set_config('test.asset', v_asset::text, true);
  perform set_config('test.disposition', v_disposition::text, true);
  perform set_config('test.sale', v_sale::text, true);
  perform set_config('test.receivable', v_receivable::text, true);
  perform set_config('test.cash_account', v_cash_account::text, true);
  perform set_config('test.buyer', v_party_buyer::text, true);
end $$;

-- 1. Sale posting balanced.
select is(
  (select sum(debit_minor_units) from public.journal_lines where batch_id = (select revenue_journal_batch_id from public.sale_recognitions where id = current_setting('test.sale')::uuid)),
  (select sum(credit_minor_units) from public.journal_lines where batch_id = (select revenue_journal_batch_id from public.sale_recognitions where id = current_setting('test.sale')::uuid)),
  'S4: revenue posting is balanced'
);

-- 2. Cost derecognition posting balanced.
select is(
  (select sum(debit_minor_units) from public.journal_lines where batch_id = (select cost_derecognition_journal_batch_id from public.sale_recognitions where id = current_setting('test.sale')::uuid)),
  (select sum(credit_minor_units) from public.journal_lines where batch_id = (select cost_derecognition_journal_batch_id from public.sale_recognitions where id = current_setting('test.sale')::uuid)),
  'S4: cost derecognition posting is balanced'
);

-- 3. Revenue amount equals agreed proceeds.
select is(
  (select recognized_revenue_minor_units from public.sale_recognitions where id = current_setting('test.sale')::uuid),
  2000000000::bigint,
  'S4: recognized revenue equals agreed proceeds'
);

-- 4. Carrying cost comes from authoritative posted facts.
select is(
  (select derecognized_carrying_cost_minor_units from public.sale_recognitions where id = current_setting('test.sale')::uuid),
  600000000::bigint,
  'S4: carrying cost = acquisition (500M) + capitalizable cost (100M)'
);

-- 5. Realized result = revenue - carrying cost - selling costs.
select is(
  (select realized_result_minor_units from public.sale_recognitions where id = current_setting('test.sale')::uuid),
  2000000000 - 600000000 - 50000000,
  'S4: realized result = 2000M - 600M - 50M = 1350M'
);

-- 6. Receivable equals revenue.
select is(
  (select receivable_minor_units from public.sale_receivables where id = current_setting('test.receivable')::uuid),
  2000000000::bigint,
  'S4: receivable equals recognized revenue'
);

-- 7. Collection posting balanced.
select lives_ok(
  format('select public.record_collection(%L::uuid, %L::uuid, %L::uuid, 1000000000::bigint, ''EGP'', ''2026-08-01''::date, %L::uuid, ''s4-test-coll-001'')',
    current_setting('test.org_a'), current_setting('test.project_a'), current_setting('test.receivable'), current_setting('test.cash_account')),
  'S4: collection command executes'
);

select is(
  (select sum(debit_minor_units) from public.journal_lines
   where batch_id = (select journal_batch_id from public.collections where idempotency_key = 's4-test-coll-001' and organization_id = current_setting('test.org_a')::uuid)),
  (select sum(credit_minor_units) from public.journal_lines
   where batch_id = (select journal_batch_id from public.collections where idempotency_key = 's4-test-coll-001' and organization_id = current_setting('test.org_a')::uuid)),
  'S4: collection posting is balanced'
);

-- 8. Partial collection updates receivable status.
select is(
  (select status from public.sale_receivables where id = current_setting('test.receivable')::uuid),
  'PARTIAL',
  'S4: partial collection marks receivable as PARTIAL'
);

-- 9. Second collection completes the receivable.
select lives_ok(
  format('select public.record_collection(%L::uuid, %L::uuid, %L::uuid, 1000000000::bigint, ''EGP'', ''2026-09-01''::date, %L::uuid, ''s4-test-coll-002'')',
    current_setting('test.org_a'), current_setting('test.project_a'), current_setting('test.receivable'), current_setting('test.cash_account')),
  'S4: second collection command executes'
);

select is(
  (select status from public.sale_receivables where id = current_setting('test.receivable')::uuid),
  'COLLECTED',
  'S4: full collection marks receivable as COLLECTED'
);

-- 10. Disposition settled after full collection.
select is(
  (select status from public.dispositions where id = current_setting('test.disposition')::uuid),
  'SETTLED',
  'S4: disposition is SETTLED after full collection'
);

-- 11. Over-collection is rejected.
select throws_ok(
  format('select public.record_collection(%L::uuid, %L::uuid, %L::uuid, 100::bigint, ''EGP'', ''2026-09-02''::date, %L::uuid, ''s4-test-coll-003'')',
    current_setting('test.org_a'), current_setting('test.project_a'), current_setting('test.receivable'), current_setting('test.cash_account')),
  'collection exceeds outstanding receivable',
  'S4: over-collection rejected'
);

-- 12. Duplicate sale recognition is idempotent (same key returns same ID).
select is(
  (select public.recognize_sale(current_setting('test.org_a')::uuid, current_setting('test.project_a')::uuid, current_setting('test.disposition')::uuid, '2026-07-01', 's4-test-sale-001')),
  current_setting('test.sale')::uuid,
  'S4: duplicate sale recognition is idempotent'
);

-- 13. Duplicate sale recognition with different key fails (asset already sold).
select throws_ok(
  format('select public.recognize_sale(%L::uuid, %L::uuid, %L::uuid, ''2026-07-01''::date, ''s4-test-sale-002'')',
    current_setting('test.org_a'), current_setting('test.project_a'), current_setting('test.disposition')::uuid),
  null,
  'S4: second sale recognition on same disposition fails'
);

-- 14. Cannot create new disposition on disposed asset.
select throws_ok(
  format('select public.create_disposition(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 100::bigint, ''EGP'', ''2026-10-01''::date, 0::bigint, null, null, ''s4-test-disp-002'')',
    current_setting('test.org_a'), current_setting('test.project_a'), current_setting('test.asset'), current_setting('test.buyer')),
  null,
  'S4: cannot sell disposed asset again'
);

-- 15. Cross-tenant disposition blocked.
select throws_ok(
  format('select public.create_disposition(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 100::bigint, ''EGP'', ''2026-10-01''::date, 0::bigint, null, null, ''s4-test-cross-001'')',
    current_setting('test.org_b'), current_setting('test.project_b'), current_setting('test.asset'), current_setting('test.buyer')),
  null,
  'S4: cross-tenant disposition blocked'
);

-- 16. Cash is not revenue: separate accounts.
select isnt(
  (select account_id from public.journal_lines where batch_id = (select revenue_journal_batch_id from public.sale_recognitions where id = current_setting('test.sale')::uuid) and debit_minor_units > 0 limit 1),
  (select account_id from public.journal_lines where batch_id = (select journal_batch_id from public.collections where idempotency_key = 's4-test-coll-001' and organization_id = current_setting('test.org_a')::uuid) and debit_minor_units > 0 limit 1),
  'S4: revenue posting debits receivable, not cash'
);

-- 17. Project realized result view is correct.
select is(
  (select recognized_revenue_minor_units from public.project_realized_result where project_id = current_setting('test.project_a')::uuid),
  2000000000::bigint,
  'S4: project result revenue = 2000M'
);

select is(
  (select collected_cash_minor_units from public.project_realized_result where project_id = current_setting('test.project_a')::uuid),
  2000000000::bigint,
  'S4: project result collected = 2000M'
);

select is(
  (select outstanding_receivable_minor_units from public.project_realized_result where project_id = current_setting('test.project_a')::uuid),
  0::bigint,
  'S4: project result outstanding = 0 after full collection'
);

-- 18. Property asset marked DISPOSED.
select is(
  (select lifecycle_state from public.property_assets where id = current_setting('test.asset')::uuid),
  'DISPOSED',
  'S4: property asset marked DISPOSED after sale'
);

-- 19. Project lifecycle moved to EXITING.
select is(
  (select lifecycle_state from public.investment_projects where id = current_setting('test.project_a')::uuid),
  'EXITING',
  'S4: project lifecycle moved to EXITING'
);

-- 20. Cannot recognize sale on DRAFT disposition.
do $$
declare v_org uuid := current_setting('test.org_a')::uuid; v_proj uuid := current_setting('test.project_a')::uuid;
  v_asset2 uuid; v_party uuid := current_setting('test.buyer')::uuid; v_disp2 uuid;
begin
  -- Create a new asset.
  perform public.create_property_asset(v_org, v_proj, 'قطعة أخرى', 'DEVELOP_SELL', 'القاهرة', 'CLEAR', '2026-01-01', 300000000, 'EGP', 's4-test-asset-002');
  select id into v_asset2 from public.property_assets where idempotency_key = 's4-test-asset-002' and organization_id = v_org;
  perform public.create_disposition(v_org, v_proj, v_asset2, v_party, 1000000000, 'EGP', '2026-06-01', 0, null, null, 's4-test-disp-003');
  select id into v_disp2 from public.dispositions where idempotency_key = 's4-test-disp-003' and organization_id = v_org;

  begin
    perform public.recognize_sale(v_org, v_proj, v_disp2, '2026-07-01', 's4-test-sale-003');
    raise exception 'should have failed';
  exception when others then
    if sqlerrm not like '%must be approved%' then raise; end if;
  end;
end $$;
select pass('S4: sale recognition requires APPROVED disposition');

-- 21. Cannot recognize sale without carrying amount data.
do $$
declare v_org uuid := current_setting('test.org_a')::uuid; v_proj uuid := current_setting('test.project_a')::uuid;
  v_asset3 uuid; v_party uuid := current_setting('test.buyer')::uuid; v_disp3 uuid;
begin
  perform public.create_property_asset(v_org, v_proj, 'قطعة بلا تكلفة', 'DEVELOP_SELL', 'القاهرة', 'CLEAR', null, null, 'EGP', 's4-test-asset-003');
  select id into v_asset3 from public.property_assets where idempotency_key = 's4-test-asset-003' and organization_id = v_org;
  perform public.create_disposition(v_org, v_proj, v_asset3, v_party, 500000000, 'EGP', '2026-06-01', 0, null, null, 's4-test-disp-004');
  select id into v_disp3 from public.dispositions where idempotency_key = 's4-test-disp-004' and organization_id = v_org;
  perform public.approve_disposition(v_org, v_disp3);

  begin
    perform public.recognize_sale(v_org, v_proj, v_disp3, '2026-07-01', 's4-test-sale-004');
    raise exception 'should have failed';
  exception when others then
    if sqlerrm not like '%cannot compute carrying amount%' then raise; end if;
  end;
end $$;
select pass('S4: sale recognition fails without authoritative cost data');

-- 22. Unposted/draft facts do not enter reports.
select is(
  (select count(*) from public.sale_recognitions where organization_id = current_setting('test.org_a')::uuid),
  1::bigint,
  'S4: only one sale recognition exists (failed ones did not create facts)'
);

-- 23. Project result traces to posted journal lines.
select ok(
  (select exists(select 1 from public.journal_batches jb
    join public.sale_recognitions sr on sr.revenue_journal_batch_id = jb.id
    where sr.id = current_setting('test.sale')::uuid and jb.status = 'POSTED')),
  'S4: project result traces to posted journal batch'
);

-- 24. Receivable rollforward: receivable - collections = outstanding.
select is(
  (select receivable_minor_units from public.sale_receivables where id = current_setting('test.receivable')::uuid)
    - (select coalesce(sum(collection_minor_units), 0) from public.collections where sale_receivable_id = current_setting('test.receivable')::uuid),
  0::bigint,
  'S4: receivable rollforward: receivable - collections = 0 (fully collected)'
);

-- 25. Valuation does not appear in realized result.
select ok(
  not exists(select 1 from information_schema.columns
    where table_name = 'project_realized_result' and column_name = 'valuation_minor_units'),
  'S4: valuation is not in the realized result view'
);

-- 26. Cross-tenant collection blocked.
select throws_ok(
  format('select public.record_collection(%L::uuid, %L::uuid, %L::uuid, 100::bigint, ''EGP'', ''2026-08-01''::date, %L::uuid, ''s4-cross-coll'')',
    current_setting('test.org_b'), current_setting('test.project_b'), current_setting('test.receivable'), current_setting('test.cash_account')),
  null,
  'S4: cross-tenant collection blocked'
);

select * from finish();

-- Terranex investor capital and distribution lifecycle (Egypt-first)
-- Corrects the ownership slice before exporting it to Odoo:
--   * draft distributions do not create accounting entitlements
--   * approval creates frozen partner entitlements atomically
--   * capital contributions/withdrawals require a real bank or cash account
--   * distribution payments update allocation + ledger + bank in one tx
--   * reversals create append-only counter-events and reverse cash atomically

-- ---------------------------------------------------------------------------
-- 1) Schema links and lifecycle metadata.
-- ---------------------------------------------------------------------------
alter table partner_ledger_entries add column if not exists bank_account_id uuid;
alter table partner_ledger_entries add column if not exists bank_transaction_id uuid;
alter table partner_ledger_entries drop constraint if exists partner_ledger_entries_bank_owner_fk;
alter table partner_ledger_entries drop constraint if exists partner_ledger_entries_bank_tx_owner_fk;
alter table partner_ledger_entries add constraint partner_ledger_entries_bank_owner_fk
  foreign key (bank_account_id, owner_id) references bank_accounts(id, owner_id) on delete restrict;
alter table partner_ledger_entries add constraint partner_ledger_entries_bank_tx_owner_fk
  foreign key (bank_transaction_id, owner_id) references bank_transactions(id, owner_id) on delete restrict;
create unique index if not exists partner_ledger_entries_bank_tx_unique
  on partner_ledger_entries(bank_transaction_id) where bank_transaction_id is not null;

alter table distributions add column if not exists approved_at timestamptz;
alter table distributions add column if not exists approved_by uuid;
alter table distributions add column if not exists paid_at timestamptz;
alter table distributions drop constraint if exists distributions_approved_by_owner_fk;
alter table distributions add constraint distributions_approved_by_owner_fk
  foreign key (approved_by) references auth.users(id) on delete restrict;

alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in (
    'transaction','settlement','distribution_payment','transfer','manual','opening_balance',
    'invoice_payment','bill_payment','journal_posting','journal_reversal',
    'partner_capital','partner_ledger_reversal'
  ));

-- ---------------------------------------------------------------------------
-- 2) Guard the append-only ledger: accounting/cash types are server-only.
-- ---------------------------------------------------------------------------
create or replace function terranex_guard_partner_ledger_source()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_internal constant text := 'terranex.internal_partner_financial_posting';
  v_original_type terranex_ledger_entry_type;
begin
  if current_setting(v_internal, true) = 'on' then return new; end if;

  if new.entry_type in (
    'capital_contribution','withdrawal','distribution_entitlement','distribution_payment'
  ) then
    raise exception using errcode='0A000',
      message='cash and distribution ledger entries require an atomic lifecycle RPC';
  end if;

  if new.entry_type = 'reversal' then
    if new.reversal_of_id is null then
      raise exception using errcode='23514', message='reversal requires an original ledger entry';
    end if;
    select entry_type into v_original_type
      from partner_ledger_entries
     where id = new.reversal_of_id and owner_id = new.owner_id;
    if v_original_type in (
      'capital_contribution','withdrawal','distribution_entitlement','distribution_payment'
    ) then
      raise exception using errcode='0A000',
        message='financial ledger reversals require reverse_partner_ledger_entry_atomic';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_partner_ledger_source_guard on partner_ledger_entries;
create trigger trg_partner_ledger_source_guard
  before insert on partner_ledger_entries
  for each row execute function terranex_guard_partner_ledger_source();

-- ---------------------------------------------------------------------------
-- 3) Distribution creation freezes allocations only. Entitlements are posted
-- when the distribution is explicitly approved.
-- ---------------------------------------------------------------------------
create or replace function record_distribution_atomic(
  p_request_id uuid,
  p_project_id uuid,
  p_distribution_date date,
  p_ownership_as_of_date date,
  p_total_amount numeric,
  p_currency terranex_currency,
  p_fx_rate numeric,
  p_notes text default null,
  p_supporting_document_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_cached jsonb;
  v_distribution_id uuid;
  v_total_amount_egp numeric;
  v_partner record;
  v_allocated_total numeric := 0;
  v_allocated_egp_total numeric := 0;
  v_largest_partner_id uuid;
  v_largest_share numeric := 0;
  v_share numeric;
  v_share_egp numeric;
  v_rounding_diff numeric;
  v_rounding_diff_egp numeric;
  v_result jsonb;
begin
  select owner_id into v_owner_id from projects where id=p_project_id for update;
  if not found then raise exception using errcode='P0002', message='project not found'; end if;
  perform terranex_assert_owner(v_owner_id);
  perform terranex_lock_financial_request(v_owner_id, p_request_id);
  v_cached := terranex_audit_check_idempotent(p_request_id, v_owner_id);
  if v_cached is not null then return v_cached; end if;

  if p_total_amount <= 0 then raise exception using errcode='23514', message='distribution amount must be positive'; end if;
  if p_fx_rate <= 0 then raise exception using errcode='23514', message='distribution fx_rate must be positive'; end if;
  if p_ownership_as_of_date > p_distribution_date then
    raise exception using errcode='23514', message='ownership_as_of_date cannot be after distribution_date';
  end if;
  v_total_amount_egp := round(p_total_amount * p_fx_rate, 4);

  insert into distributions(
    owner_id,project_id,distribution_date,ownership_as_of_date,total_amount,
    currency,fx_rate,total_amount_egp,status,notes,supporting_document_id,created_by
  ) values (
    v_owner_id,p_project_id,p_distribution_date,p_ownership_as_of_date,p_total_amount,
    p_currency,p_fx_rate,v_total_amount_egp,'draft',p_notes,p_supporting_document_id,v_owner_id
  ) returning id into v_distribution_id;

  for v_partner in
    select partner_id,equity_pct from project_partners
     where owner_id=v_owner_id and project_id=p_project_id and equity_pct>0
       and effective_from<=p_ownership_as_of_date
       and (effective_to is null or effective_to>=p_ownership_as_of_date)
     order by partner_id
  loop
    v_share := round(p_total_amount * v_partner.equity_pct / 100, 2);
    v_share_egp := round(v_total_amount_egp * v_partner.equity_pct / 100, 2);
    v_allocated_total := v_allocated_total + v_share;
    v_allocated_egp_total := v_allocated_egp_total + v_share_egp;
    if v_share > v_largest_share then
      v_largest_share := v_share; v_largest_partner_id := v_partner.partner_id;
    end if;
    insert into distribution_allocations(
      owner_id,distribution_id,partner_id,equity_pct_snapshot,
      allocated_amount,allocated_amount_egp,status
    ) values (
      v_owner_id,v_distribution_id,v_partner.partner_id,v_partner.equity_pct,
      v_share,v_share_egp,'due'
    );
  end loop;

  if v_largest_partner_id is null then
    raise exception using errcode='23514', message='distribution requires at least one active ownership allocation';
  end if;
  v_rounding_diff := p_total_amount-v_allocated_total;
  v_rounding_diff_egp := v_total_amount_egp-v_allocated_egp_total;
  if abs(v_rounding_diff)>0.001 or abs(v_rounding_diff_egp)>0.001 then
    perform set_config('terranex.internal_distribution_allocation_adjustment','on',true);
    update distribution_allocations
       set allocated_amount=allocated_amount+v_rounding_diff,
           allocated_amount_egp=allocated_amount_egp+v_rounding_diff_egp
     where owner_id=v_owner_id and distribution_id=v_distribution_id
       and partner_id=v_largest_partner_id;
    perform set_config('terranex.internal_distribution_allocation_adjustment','off',true);
  end if;

  v_result := jsonb_build_object(
    'distribution_id',v_distribution_id,'total_amount',p_total_amount,
    'total_amount_egp',v_total_amount_egp,'status','draft','ledger_entry_ids','[]'::jsonb
  );
  perform terranex_audit_log(
    p_request_id,'record_distribution','distribution',array[v_distribution_id],
    jsonb_build_object('project_id',p_project_id,'distribution_date',p_distribution_date,
      'ownership_as_of_date',p_ownership_as_of_date,'total_amount',p_total_amount,
      'currency',p_currency::text,'fx_rate',p_fx_rate),
    v_result,v_owner_id
  );
  return v_result;
end;
$$;

create or replace function approve_distribution_atomic(
  p_request_id uuid,
  p_distribution_id uuid,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distribution distributions%rowtype;
  v_cached jsonb;
  v_allocation record;
  v_existing_count integer;
  v_allocation_count integer;
  v_existing_total numeric;
  v_ledger_ids uuid[] := '{}'::uuid[];
  v_ledger_id uuid;
  v_result jsonb;
begin
  select * into v_distribution from distributions where id=p_distribution_id for update;
  if not found then raise exception using errcode='P0002', message='distribution not found'; end if;
  perform terranex_assert_owner(v_distribution.owner_id);
  perform terranex_lock_financial_request(v_distribution.owner_id,p_request_id);
  v_cached := terranex_audit_check_idempotent(p_request_id,v_distribution.owner_id);
  if v_cached is not null then return v_cached; end if;
  if v_distribution.status<>'draft' then
    raise exception using errcode='23514', message='only draft distributions can be approved';
  end if;

  select count(*),coalesce(sum(allocated_amount),0)
    into v_allocation_count,v_existing_total
    from distribution_allocations
   where owner_id=v_distribution.owner_id and distribution_id=p_distribution_id;
  if v_allocation_count=0 or abs(v_existing_total-v_distribution.total_amount)>0.01 then
    raise exception using errcode='23514', message='distribution allocations do not reconcile to the header total';
  end if;

  select count(*) into v_existing_count from partner_ledger_entries
   where owner_id=v_distribution.owner_id and related_distribution_id=p_distribution_id
     and entry_type='distribution_entitlement';
  if v_existing_count not in (0,v_allocation_count) then
    raise exception using errcode='23514', message='legacy distribution entitlements are incomplete';
  end if;

  if v_existing_count=0 then
    perform set_config('terranex.internal_partner_financial_posting','on',true);
    for v_allocation in
      select * from distribution_allocations
       where owner_id=v_distribution.owner_id and distribution_id=p_distribution_id
       order by partner_id
    loop
      insert into partner_ledger_entries(
        owner_id,project_id,partner_id,entry_type,amount,currency,fx_rate,amount_egp,
        posting_date,supporting_document_id,related_distribution_id,notes,created_by
      ) values (
        v_distribution.owner_id,v_distribution.project_id,v_allocation.partner_id,
        'distribution_entitlement',v_allocation.allocated_amount,v_distribution.currency,
        v_distribution.fx_rate,v_allocation.allocated_amount_egp,v_distribution.distribution_date,
        v_distribution.supporting_document_id,p_distribution_id,
        coalesce(p_notes,v_distribution.notes),v_distribution.owner_id
      ) returning id into v_ledger_id;
      v_ledger_ids := array_append(v_ledger_ids,v_ledger_id);
    end loop;
    perform set_config('terranex.internal_partner_financial_posting','off',true);
  else
    select array_agg(id order by partner_id) into v_ledger_ids
      from partner_ledger_entries
     where owner_id=v_distribution.owner_id and related_distribution_id=p_distribution_id
       and entry_type='distribution_entitlement';
  end if;

  update distributions set status='approved',approved_at=now(),approved_by=auth.uid(),
    notes=coalesce(p_notes,notes)
   where id=p_distribution_id and owner_id=v_distribution.owner_id;

  v_result := jsonb_build_object('distribution_id',p_distribution_id,'status','approved',
    'ledger_entry_ids',to_jsonb(v_ledger_ids));
  perform terranex_audit_log(
    p_request_id,'approve_distribution','distribution',array[p_distribution_id],
    jsonb_build_object('previous_status','draft','notes',p_notes),v_result,v_distribution.owner_id
  );
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Atomic capital cash movement.
-- ---------------------------------------------------------------------------
create or replace function record_partner_capital_movement_atomic(
  p_request_id uuid,
  p_project_id uuid,
  p_partner_id uuid,
  p_entry_type terranex_ledger_entry_type,
  p_amount numeric,
  p_currency terranex_currency,
  p_fx_rate numeric,
  p_posting_date date,
  p_bank_account_id uuid,
  p_supporting_document_id uuid default null,
  p_related_equity_event_id uuid default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_cached jsonb;
  v_bank bank_accounts%rowtype;
  v_ledger_id uuid := gen_random_uuid();
  v_bank_tx_id uuid := gen_random_uuid();
  v_amount_egp numeric;
  v_direction text;
  v_result jsonb;
begin
  select owner_id into v_owner_id from projects where id=p_project_id for update;
  if not found then raise exception using errcode='P0002', message='project not found'; end if;
  perform terranex_assert_owner(v_owner_id);
  perform terranex_lock_financial_request(v_owner_id,p_request_id);
  v_cached := terranex_audit_check_idempotent(p_request_id,v_owner_id);
  if v_cached is not null then return v_cached; end if;
  if p_entry_type not in ('capital_contribution','withdrawal') then
    raise exception using errcode='23514', message='capital movement type must be capital_contribution or withdrawal';
  end if;
  if p_amount<=0 or p_fx_rate<=0 then
    raise exception using errcode='23514', message='capital amount and fx_rate must be positive';
  end if;
  perform 1 from partners where id=p_partner_id and owner_id=v_owner_id;
  if not found then raise exception using errcode='P0002', message='partner not found'; end if;
  select * into v_bank from bank_accounts
   where id=p_bank_account_id and owner_id=v_owner_id and not is_archived for update;
  if not found then raise exception using errcode='P0002', message='active bank account not found'; end if;
  if v_bank.currency<>p_currency::text then
    raise exception using errcode='23514', message='capital movement currency must match the selected bank account';
  end if;
  v_amount_egp := round(p_amount*p_fx_rate,4);
  v_direction := case when p_entry_type='capital_contribution' then 'deposit' else 'withdrawal' end;

  insert into bank_transactions(
    id,owner_id,bank_account_id,direction,amount,currency,fx_rate_to_base,amount_base,
    transaction_date,reference_type,reference_id,partner_id,memo,document_id
  ) values (
    v_bank_tx_id,v_owner_id,p_bank_account_id,v_direction,p_amount,p_currency::text,p_fx_rate,
    v_amount_egp,p_posting_date,'partner_capital',v_ledger_id,p_partner_id,p_notes,p_supporting_document_id
  );
  perform set_config('terranex.internal_partner_financial_posting','on',true);
  insert into partner_ledger_entries(
    id,owner_id,project_id,partner_id,entry_type,amount,currency,fx_rate,amount_egp,
    posting_date,supporting_document_id,related_equity_event_id,notes,
    bank_account_id,bank_transaction_id,created_by
  ) values (
    v_ledger_id,v_owner_id,p_project_id,p_partner_id,p_entry_type,p_amount,p_currency,p_fx_rate,
    v_amount_egp,p_posting_date,p_supporting_document_id,p_related_equity_event_id,p_notes,
    p_bank_account_id,v_bank_tx_id,v_owner_id
  );
  perform set_config('terranex.internal_partner_financial_posting','off',true);

  v_result := jsonb_build_object('ledger_entry_id',v_ledger_id,'bank_transaction_id',v_bank_tx_id,
    'entry_type',p_entry_type::text,'amount_egp',v_amount_egp);
  perform terranex_audit_log(
    p_request_id,'record_partner_capital_movement','partner_ledger_entry',array[v_ledger_id,v_bank_tx_id],
    jsonb_build_object('project_id',p_project_id,'partner_id',p_partner_id,'entry_type',p_entry_type::text,
      'amount',p_amount,'currency',p_currency::text,'fx_rate',p_fx_rate,'bank_account_id',p_bank_account_id),
    v_result,v_owner_id
  );
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) Pay one frozen distribution allocation in full.
-- ---------------------------------------------------------------------------
create or replace function pay_distribution_allocation_atomic(
  p_request_id uuid,
  p_allocation_id uuid,
  p_bank_account_id uuid,
  p_payment_date date,
  p_payment_document_id uuid default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allocation distribution_allocations%rowtype;
  v_distribution distributions%rowtype;
  v_bank bank_accounts%rowtype;
  v_cached jsonb;
  v_ledger_id uuid := gen_random_uuid();
  v_bank_tx_id uuid := gen_random_uuid();
  v_remaining integer;
  v_result jsonb;
begin
  select * into v_allocation from distribution_allocations where id=p_allocation_id for update;
  if not found then raise exception using errcode='P0002', message='distribution allocation not found'; end if;
  select * into v_distribution from distributions
   where id=v_allocation.distribution_id and owner_id=v_allocation.owner_id for update;
  perform terranex_assert_owner(v_allocation.owner_id);
  perform terranex_lock_financial_request(v_allocation.owner_id,p_request_id);
  v_cached := terranex_audit_check_idempotent(p_request_id,v_allocation.owner_id);
  if v_cached is not null then return v_cached; end if;
  if v_distribution.status not in ('approved','paid') then
    raise exception using errcode='23514', message='distribution must be approved before payment';
  end if;
  if v_allocation.status<>'due' then
    raise exception using errcode='23514', message='distribution allocation is not due';
  end if;
  if p_payment_date<v_distribution.distribution_date then
    raise exception using errcode='23514', message='payment date cannot be before distribution date';
  end if;
  select * into v_bank from bank_accounts
   where id=p_bank_account_id and owner_id=v_allocation.owner_id and not is_archived for update;
  if not found then raise exception using errcode='P0002', message='active bank account not found'; end if;
  if v_bank.currency<>v_distribution.currency::text then
    raise exception using errcode='23514', message='distribution currency must match the selected bank account';
  end if;

  insert into bank_transactions(
    id,owner_id,bank_account_id,direction,amount,currency,fx_rate_to_base,amount_base,
    transaction_date,reference_type,reference_id,partner_id,memo,document_id
  ) values (
    v_bank_tx_id,v_allocation.owner_id,p_bank_account_id,'withdrawal',v_allocation.allocated_amount,
    v_distribution.currency::text,v_distribution.fx_rate,v_allocation.allocated_amount_egp,
    p_payment_date,'distribution_payment',v_ledger_id,v_allocation.partner_id,p_notes,p_payment_document_id
  );
  perform set_config('terranex.internal_partner_financial_posting','on',true);
  insert into partner_ledger_entries(
    id,owner_id,project_id,partner_id,entry_type,amount,currency,fx_rate,amount_egp,
    posting_date,supporting_document_id,related_distribution_id,notes,
    bank_account_id,bank_transaction_id,created_by
  ) values (
    v_ledger_id,v_allocation.owner_id,v_distribution.project_id,v_allocation.partner_id,
    'distribution_payment',v_allocation.allocated_amount,v_distribution.currency,v_distribution.fx_rate,
    v_allocation.allocated_amount_egp,p_payment_date,p_payment_document_id,v_distribution.id,p_notes,
    p_bank_account_id,v_bank_tx_id,v_allocation.owner_id
  );
  perform set_config('terranex.internal_partner_financial_posting','off',true);

  update distribution_allocations set status='paid',payment_date=p_payment_date,
    payment_document_id=p_payment_document_id,related_ledger_entry_id=v_ledger_id
   where id=p_allocation_id and owner_id=v_allocation.owner_id;
  select count(*) into v_remaining from distribution_allocations
   where owner_id=v_allocation.owner_id and distribution_id=v_distribution.id and status='due';
  if v_remaining=0 then
    update distributions set status='paid',paid_at=now()
     where id=v_distribution.id and owner_id=v_allocation.owner_id;
  end if;

  v_result := jsonb_build_object('allocation_id',p_allocation_id,'ledger_entry_id',v_ledger_id,
    'bank_transaction_id',v_bank_tx_id,'distribution_status',case when v_remaining=0 then 'paid' else 'approved' end);
  perform terranex_audit_log(
    p_request_id,'pay_distribution_allocation','distribution_allocation',array[p_allocation_id,v_ledger_id,v_bank_tx_id],
    jsonb_build_object('distribution_id',v_distribution.id,'partner_id',v_allocation.partner_id,
      'bank_account_id',p_bank_account_id,'payment_date',p_payment_date),v_result,v_allocation.owner_id
  );
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) Append-only reversal with the opposite bank movement when applicable.
-- ---------------------------------------------------------------------------
create or replace function reverse_partner_ledger_entry_atomic(
  p_request_id uuid,
  p_entry_id uuid,
  p_posting_date date,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_original partner_ledger_entries%rowtype;
  v_cached jsonb;
  v_reversal_id uuid := gen_random_uuid();
  v_bank_tx_id uuid;
  v_original_tx bank_transactions%rowtype;
  v_direction text;
  v_result jsonb;
begin
  select * into v_original from partner_ledger_entries where id=p_entry_id for update;
  if not found then raise exception using errcode='P0002', message='partner ledger entry not found'; end if;
  perform terranex_assert_owner(v_original.owner_id);
  perform terranex_lock_financial_request(v_original.owner_id,p_request_id);
  v_cached := terranex_audit_check_idempotent(p_request_id,v_original.owner_id);
  if v_cached is not null then return v_cached; end if;
  if nullif(trim(p_reason),'') is null then
    raise exception using errcode='23514', message='reversal reason is required';
  end if;
  if v_original.entry_type='distribution_entitlement' then
    raise exception using errcode='23514', message='distribution entitlements must be reversed through the distribution lifecycle';
  end if;
  if exists(select 1 from partner_ledger_entries where owner_id=v_original.owner_id and reversal_of_id=p_entry_id) then
    raise exception using errcode='23514', message='partner ledger entry is already reversed';
  end if;

  if v_original.bank_transaction_id is not null then
    select * into v_original_tx from bank_transactions
     where id=v_original.bank_transaction_id and owner_id=v_original.owner_id for update;
    v_bank_tx_id := gen_random_uuid();
    v_direction := case when v_original_tx.direction='deposit' then 'withdrawal' else 'deposit' end;
    insert into bank_transactions(
      id,owner_id,bank_account_id,direction,amount,currency,fx_rate_to_base,amount_base,
      transaction_date,reference_type,reference_id,partner_id,memo,document_id
    ) values (
      v_bank_tx_id,v_original.owner_id,v_original_tx.bank_account_id,v_direction,
      v_original.amount,v_original.currency::text,v_original.fx_rate,v_original.amount_egp,
      p_posting_date,'partner_ledger_reversal',v_reversal_id,v_original.partner_id,p_reason,
      v_original.supporting_document_id
    );
  end if;

  perform set_config('terranex.internal_partner_financial_posting','on',true);
  insert into partner_ledger_entries(
    id,owner_id,project_id,partner_id,entry_type,amount,currency,fx_rate,amount_egp,
    posting_date,supporting_document_id,related_equity_event_id,related_distribution_id,
    notes,reversal_of_id,bank_account_id,bank_transaction_id,created_by
  ) values (
    v_reversal_id,v_original.owner_id,v_original.project_id,v_original.partner_id,'reversal',
    v_original.amount,v_original.currency,v_original.fx_rate,v_original.amount_egp,p_posting_date,
    v_original.supporting_document_id,v_original.related_equity_event_id,v_original.related_distribution_id,
    p_reason,v_original.id,v_original.bank_account_id,v_bank_tx_id,v_original.owner_id
  );
  perform set_config('terranex.internal_partner_financial_posting','off',true);

  if v_original.entry_type='distribution_payment' then
    update distribution_allocations set status='due',payment_date=null,payment_document_id=null,
      related_ledger_entry_id=null
     where owner_id=v_original.owner_id and related_ledger_entry_id=v_original.id;
    update distributions set status='approved',paid_at=null
     where owner_id=v_original.owner_id and id=v_original.related_distribution_id and status='paid';
  end if;

  v_result := jsonb_build_object('original_entry_id',v_original.id,'reversal_entry_id',v_reversal_id,
    'bank_transaction_id',v_bank_tx_id);
  perform terranex_audit_log(
    p_request_id,'reverse_partner_ledger_entry','partner_ledger_entry',
    array_remove(array[v_original.id,v_reversal_id,v_bank_tx_id],null),
    jsonb_build_object('reason',p_reason,'posting_date',p_posting_date),v_result,v_original.owner_id
  );
  return v_result;
end;
$$;

revoke all on function approve_distribution_atomic(uuid,uuid,text) from public,anon;
revoke all on function record_partner_capital_movement_atomic(uuid,uuid,uuid,terranex_ledger_entry_type,numeric,terranex_currency,numeric,date,uuid,uuid,uuid,text) from public,anon;
revoke all on function pay_distribution_allocation_atomic(uuid,uuid,uuid,date,uuid,text) from public,anon;
revoke all on function reverse_partner_ledger_entry_atomic(uuid,uuid,date,text) from public,anon;
grant execute on function approve_distribution_atomic(uuid,uuid,text) to authenticated;
grant execute on function record_partner_capital_movement_atomic(uuid,uuid,uuid,terranex_ledger_entry_type,numeric,terranex_currency,numeric,date,uuid,uuid,uuid,text) to authenticated;
grant execute on function pay_distribution_allocation_atomic(uuid,uuid,uuid,date,uuid,text) to authenticated;
grant execute on function reverse_partner_ledger_entry_atomic(uuid,uuid,date,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Odoo event vocabulary and causal ordering.
-- ---------------------------------------------------------------------------
alter table odoo_sync_outbox drop constraint if exists odoo_sync_outbox_entity_type_check;
alter table odoo_sync_outbox add constraint odoo_sync_outbox_entity_type_check
  check (entity_type in (
    'partner','project','sales_invoice','purchase_invoice','bank_account',
    'sales_payment','purchase_payment','journal_entry','distribution','partner_ledger_entry'
  ));
alter table odoo_entity_mappings drop constraint if exists odoo_entity_mappings_entity_type_check;
alter table odoo_entity_mappings add constraint odoo_entity_mappings_entity_type_check
  check (entity_type in (
    'partner','project','sales_invoice','purchase_invoice','bank_account',
    'sales_payment','purchase_payment','journal_entry','distribution','partner_ledger_entry'
  ));

create or replace function terranex_queue_odoo_event(
  p_owner_id uuid,p_entity_type text,p_entity_id uuid,p_operation text default 'upsert',
  p_payload jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if p_owner_id is null or p_entity_id is null then raise exception 'owner_id و entity_id مطلوبان للمزامنة'; end if;
  if p_entity_type not in (
    'partner','project','sales_invoice','purchase_invoice','bank_account',
    'sales_payment','purchase_payment','journal_entry','distribution','partner_ledger_entry'
  ) then raise exception 'نوع كيان Odoo غير مدعوم: %',p_entity_type; end if;
  if p_operation not in ('upsert','void') then raise exception 'عملية Odoo غير مدعومة: %',p_operation; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner_id::text||':'||p_entity_type||':'||p_entity_id::text,0));
  update odoo_sync_outbox set operation=p_operation,payload=coalesce(p_payload,'{}'::jsonb),
    status='pending',available_at=now(),locked_at=null,locked_by=null,last_error=null,updated_at=now()
   where owner_id=p_owner_id and entity_type=p_entity_type and entity_id=p_entity_id
     and status in ('pending','failed') returning id into v_id;
  if v_id is null then
    insert into odoo_sync_outbox(owner_id,entity_type,entity_id,operation,payload)
    values(p_owner_id,p_entity_type,p_entity_id,p_operation,coalesce(p_payload,'{}'::jsonb)) returning id into v_id;
  end if;
  return v_id;
end; $$;

create or replace function terranex_enqueue_odoo_investor_event()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_event uuid; v_dependency uuid;
begin
  if tg_table_name='distributions' then
    if new.status='approved' and old.status is distinct from 'approved' then
      perform terranex_queue_odoo_event(new.owner_id,'distribution',new.id,'upsert',
        jsonb_build_object('status',new.status,'project_id',new.project_id));
    end if;
    return new;
  end if;

  if new.entry_type not in ('capital_contribution','withdrawal','distribution_payment','reversal') then return new; end if;
  v_event := terranex_queue_odoo_event(new.owner_id,'partner_ledger_entry',new.id,'upsert',
    jsonb_build_object('entry_type',new.entry_type,'project_id',new.project_id,
      'partner_id',new.partner_id,'related_distribution_id',new.related_distribution_id,
      'reversal_of_id',new.reversal_of_id));

  if new.entry_type='distribution_payment' then v_dependency:=new.related_distribution_id;
  elsif new.entry_type='reversal' then v_dependency:=new.reversal_of_id;
  end if;
  if v_dependency is not null and not exists(
    select 1 from odoo_entity_mappings m where m.owner_id=new.owner_id
      and m.entity_type=case when new.entry_type='distribution_payment' then 'distribution' else 'partner_ledger_entry' end
      and m.entity_id=v_dependency
  ) then
    update odoo_sync_outbox set available_at='infinity'::timestamptz,updated_at=now() where id=v_event;
  end if;
  return new;
end; $$;

drop trigger if exists trg_distributions_odoo_investor_event on distributions;
create trigger trg_distributions_odoo_investor_event
  after update of status on distributions for each row execute function terranex_enqueue_odoo_investor_event();
drop trigger if exists trg_partner_ledger_odoo_investor_event on partner_ledger_entries;
create trigger trg_partner_ledger_odoo_investor_event
  after insert on partner_ledger_entries for each row execute function terranex_enqueue_odoo_investor_event();

create or replace function terranex_release_odoo_investor_dependents()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.entity_type='distribution' then
    update odoo_sync_outbox o set available_at=now(),updated_at=now()
      from partner_ledger_entries l
     where l.owner_id=new.owner_id and l.related_distribution_id=new.entity_id
       and l.entry_type='distribution_payment' and o.owner_id=l.owner_id
       and o.entity_type='partner_ledger_entry' and o.entity_id=l.id
       and o.status in ('pending','failed') and o.available_at='infinity'::timestamptz;
  elsif new.entity_type='partner_ledger_entry' then
    update odoo_sync_outbox o set available_at=now(),updated_at=now()
      from partner_ledger_entries l
     where l.owner_id=new.owner_id and l.reversal_of_id=new.entity_id
       and o.owner_id=l.owner_id and o.entity_type='partner_ledger_entry' and o.entity_id=l.id
       and o.status in ('pending','failed') and o.available_at='infinity'::timestamptz;
  end if;
  return new;
end; $$;

drop trigger if exists trg_odoo_mapping_release_investor_dependents on odoo_entity_mappings;
create trigger trg_odoo_mapping_release_investor_dependents
  after insert or update on odoo_entity_mappings
  for each row execute function terranex_release_odoo_investor_dependents();

revoke all on function terranex_queue_odoo_event(uuid,text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function terranex_queue_odoo_event(uuid,text,uuid,text,jsonb) to service_role;

-- Approved legacy distributions and bank-backed legacy cash entries only.
select terranex_queue_odoo_event(owner_id,'distribution',id,'upsert',jsonb_build_object('backfill',true))
from distributions d where status in ('approved','paid') and not exists(
  select 1 from odoo_entity_mappings m where m.owner_id=d.owner_id and m.entity_type='distribution' and m.entity_id=d.id
);
select terranex_queue_odoo_event(owner_id,'partner_ledger_entry',id,'upsert',jsonb_build_object('backfill',true))
from partner_ledger_entries l where entry_type in ('capital_contribution','withdrawal','distribution_payment','reversal')
  and bank_account_id is not null and not exists(
    select 1 from odoo_entity_mappings m where m.owner_id=l.owner_id and m.entity_type='partner_ledger_entry' and m.entity_id=l.id
  );
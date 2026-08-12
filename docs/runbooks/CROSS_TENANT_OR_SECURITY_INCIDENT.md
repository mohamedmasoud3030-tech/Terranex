# Runbook — Cross-tenant or security incident

**Scope:** suspected exposure of one organization's data to another, suspected unauthorised access, or any suspected weakening of the tenancy controls.

**This is the highest-severity runbook in the set. When in doubt, treat the situation as real and escalate.**

## 1. Symptom

- A user reports seeing a project, party, balance, document reference or name that does not belong to their organization.
- A query or export returns rows from more than one organization.
- A command succeeded against another tenant's identifier.
- Logs show authenticated requests with an organization id the actor is not a member of.
- A secret, key, or database credential is suspected to be exposed.
- Any report that "the data looks like someone else's".

## 2. Immediate safety action

1. **Preserve first.** Do not restart services, rotate keys, or "clean up" before evidence is captured. Rotation destroys the ability to establish scope.
2. **Contain the actor, not the evidence.** If a specific account is implicated, revoke that membership immediately with `s7_set_membership_status(..., 'INACTIVE', reason, key)` — see [`MEMBERSHIP_AND_ACCESS_INCIDENT.md`](MEMBERSHIP_AND_ACCESS_INCIDENT.md).
3. **Notify `<SECURITY_OWNER>` immediately**, and `<PILOT_OPS_OWNER>` in parallel. Do not wait for confirmation that the report is genuine.
4. **Do not tell the reporting customer that it is "just a display issue"** until it has been proven so.
5. If a credential or key is confirmed exposed, rotate it *after* evidence capture, and record the rotation time.

## 3. Evidence to preserve

- The exact report: who saw what, when, on which screen or query, and under which user.
- Screenshots or exports supplied by the reporter, stored in the operator's incident system and **never** committed to this repository.
- Application and database logs covering the window.
- The authenticated user id, the organization ids involved, and the request timestamps.
- The deployed commit SHA and the applied migration state.
- The output of every verification query in section 4, captured before any change.

## 4. Diagnosis

Tenancy in Terranex rests on three layers. Verify all three; a genuine cross-tenant leak requires a failure in one of them.

### Layer 1 — Row Level Security is enabled *and forced*

```sql
select c.relname, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
  from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relkind = 'r'
   and c.relname in ('organizations','memberships','investment_projects','audit_events',
     'parties','project_participants','agreement_versions','commitment_terms',
     'journal_batches','journal_lines','project_cash_accounts','cost_obligations',
     'accounting_periods','close_runs','close_run_snapshots',
     's5_allocation_runs','s5_allocation_lines','s5_distributions',
     's7_opening_imports','s7_opening_import_rows','s7_reconciliation_checkpoints',
     's7_reconciliation_exceptions','s7_uat_tasks','s7_pilot_rehearsals')
 order by 1;
-- Every row must show true / true.
```

### Layer 2 — Policies are membership-scoped, and views are security_invoker

```sql
select schemaname, tablename, policyname, cmd, qual
  from pg_policies where schemaname = 'public' order by tablename, policyname;

-- Read models must not bypass RLS.
select c.relname, c.reloptions
  from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relkind = 'v' and c.relname like '%_read'
 order by 1;
-- Each must carry security_invoker=on.
```

### Layer 3 — SECURITY DEFINER functions pin their search_path and check membership

```sql
select p.proname, p.prosecdef, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.prosecdef
   and (p.proconfig is null
        or not exists (select 1 from unnest(p.proconfig) c
                        where replace(c,' ','') = 'search_path=pg_catalog,public'))
 order by 1;
-- This must return zero rows.
```

### Data-level checks

```sql
-- No journal line may cross its batch's tenant or project.
select count(*) from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
 where jl.organization_id <> jb.organization_id or jl.project_id <> jb.project_id;

-- No participant may reference a party from another organization.
select count(*) from public.project_participants pp
  join public.parties p on p.id = pp.party_id
 where p.organization_id <> pp.organization_id;

-- What did the implicated actor actually touch?
select occurred_at, organization_id, event_type, entity_type, entity_id
  from public.audit_events where actor_id = :user_id order by occurred_at desc limit 500;

-- Is the actor a member of every organization they touched?
select distinct a.organization_id,
       exists(select 1 from public.memberships m
               where m.organization_id = a.organization_id and m.user_id = :user_id
                 and m.status = 'ACTIVE') as is_active_member
  from public.audit_events a where a.actor_id = :user_id;
```

### Secret exposure checks

```bash
# No service-role key may ever appear in application code or in the client bundle.
grep -rn -i "service_role\|SERVICE_ROLE" src/ || echo "clean"

# The browser client must use only the publishable key.
cat src/shared/supabase/browser.ts src/shared/supabase/env.ts
```

The browser client is built from the publishable key only. If any build artifact contains a service-role key or a database URL with credentials, that is a confirmed secret exposure regardless of whether data was accessed.

### Most common benign explanations — verify, do not assume

| Observation | Often actually is | How to confirm |
| --- | --- | --- |
| "I can see another company's project" | The user is genuinely a member of both organizations | Check `memberships` for that user |
| "The name looks like another client" | Two customers chose similar Arabic names | Compare organization ids, not names |
| "Numbers changed after login" | The user switched organizations in the UI | Check the session's organization context |
| "An export had extra rows" | The export was run by a user with wider membership | Check who ran it |

A benign explanation must be *proved* with the queries above, not assumed from plausibility.

## 5. Approved response path

1. **Classify** with `<SECURITY_OWNER>`: confirmed leak, confirmed unauthorised access, secret exposure, or unfounded report.
2. **Scope** it: which organizations, which records, which time window, which actors. Use the audit trail — it exists for exactly this.
3. **Contain**: revoke implicated memberships; rotate exposed secrets after evidence capture; if a defect in RLS or a policy is confirmed, take the affected path out of service rather than leaving it exposed.
4. **Remediate the defect** through the ordinary engineering path: a migration or code fix, reviewed, with a regression test that reproduces the leak and then proves it closed. The existing suites already assert cross-tenant containment for every read model; a genuine leak means a missing case, and the fix must add it.
5. **Correct any wrong data** through the ordinary correction paths. Cross-tenant records are never deleted quietly; if a fact was recorded under the wrong tenant it is reversed and re-recorded correctly, with the incident referenced.
6. **Notify** the affected customers. Content and timing are decided by `<SECURITY_OWNER>` with the customer's own obligations in mind. Terranex does not decide the customer's regulatory notifications for them.
7. **Verify** with section 7 before declaring the incident closed.

## 6. Prohibited shortcuts

- Disabling RLS, dropping a policy, or setting a view to `security_definer` to "make the query work".
- Granting `authenticated` write access to any table so a support action can proceed. Browser-reachable roles are read-only for command-mutated facts.
- Using a service-role key from a browser, a support tool, or a shell to bypass a policy.
- Deleting audit events, log lines, or the reporter's screenshots.
- Rotating keys before evidence capture.
- Closing the incident because the report "could not be reproduced" without running the layer checks above.
- Copying customer data into this repository, into a ticket body, or into a chat message as "evidence".

## 7. Post-recovery verification

- Every table in the layer-1 query shows `true / true`.
- Every `%_read` view shows `security_invoker=on`.
- The SECURITY DEFINER search_path query returns zero rows.
- Both data-level cross-tenant counts are `0`.
- The full database gate passes on the fixed code, including the cross-tenant containment assertions in the S0, S3, S4, S5 and S7 suites:

  ```bash
  npm run db:test
  ```

- A regression test exists that fails on the pre-fix code.
- No service-role reference exists in `src/` or in a build artifact.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Any report of cross-tenant visibility | `<SECURITY_OWNER>` immediately, no triage delay |
| Confirmed leak | `<SECURITY_OWNER>` leads; `<PILOT_OPS_OWNER>` owns customer contact |
| Secret or credential exposure | `<SECURITY_OWNER>` + `<ENGINEERING_ONCALL>` |
| Financial facts recorded under the wrong tenant | `<FINANCE_CONTROL_OWNER>` for corrections |
| Regulatory notification question | `<CUSTOMER_APPROVER>` — it is the customer's obligation, informed by our findings |

## 9. Communication

State only what has been established. Distinguish clearly between "a user reported X", "we confirmed X", and "we have not been able to reproduce X". Never assert that no data was accessed unless the audit trail supports that specific claim. Never minimise a report to a customer before the layer checks have been run.

## 10. Record

Record: the initial report verbatim, the classification and who made it, the scope by organization and record, the containment actions with timestamps, the defect and its fix commit, the regression test, the verification output, the customers notified and when, and any residual risk accepted and by whom.

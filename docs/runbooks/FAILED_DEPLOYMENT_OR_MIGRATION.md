# Runbook — Failed deployment or migration

**Scope:** an application release or a database migration failed, partially applied, or left the system behaving incorrectly.

## 1. Symptom

- A migration errored part-way through the replay.
- The application build or start fails after a release.
- CI is red on the database job, the app job, or both.
- The application is up but a screen errors, or a command that used to work now fails.
- The schema does not match what the code expects.

## 2. Immediate safety action

1. **Stop the rollout.** Do not deploy further changes on top of a failed one.
2. **Do not hand-patch the database to "match" the code.** A schema reached by manual `ALTER` statements is not reproducible, will diverge from the next clean replay, and will fail the canonical gate later in a much worse situation.
3. **Establish whether any financial fact was written after the failure.** If yes, a rollback is no longer a simple matter and `<FINANCE_CONTROL_OWNER>` must be involved.

   ```sql
   select id, source_type, project_id, transaction_date, posted_at
     from public.journal_batches where posted_at > :deployment_started_at order by posted_at;
   ```

4. Notify `<ENGINEERING_ONCALL>`.

## 3. Evidence to preserve

- The commit SHA being deployed and the previously deployed SHA.
- The full failure output — CI job logs, migration error text, application stack trace.
- The migration file that failed and the error's line context.
- The list of migrations applied before the failure.
- The database state at failure time (a `pg_dump` if a live environment is involved — see [`BACKUP_AND_RESTORE.md`](BACKUP_AND_RESTORE.md)).
- Any financial facts written after the failure, from the query above.

## 4. Diagnosis

### Reproduce on a clean database first

Terranex migrations are replayed from empty on every gate. That property is the fastest diagnostic available.

```bash
npm run db:test
```

This drops and recreates the verification database, applies the shim, replays every migration in lexical filename order, then runs every SQL suite and every shell suite. If it fails here, the migration is genuinely broken and no environment-specific theory is needed.

### Check what actually landed

```sql
-- Do the expected objects exist?
select to_regclass('public.s7_opening_imports'),
       to_regclass('public.s7_reconciliation_checkpoints'),
       to_regprocedure('public.s7_approve_opening_import(uuid,uuid,date,text)');

-- Are all controls in place?
select c.relname, c.relrowsecurity, c.relforcerowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relkind = 'r' and c.relname like 's7\_%' order by 1;

select tgname, tgrelid::regclass from pg_trigger
 where not tgisinternal and tgrelid::regclass::text like '%journal%' order by 1;

-- SECURITY DEFINER functions must pin search_path.
select p.proname, p.proconfig from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
 where p.prosecdef and (p.proconfig is null
   or not exists (select 1 from unnest(p.proconfig) c
                   where replace(c,' ','') = 'search_path=pg_catalog,public'));
```

### Check the application side

```bash
npm ci --no-audit --no-fund
npm run lint
npm run typecheck
npm test
npm run build
```

### Forward-upgrade check

If the failure is "it works on a clean replay but not on the existing database", the migration is not forward-safe. The forward-upgrade suites exist to catch exactly this: they build the prior boundary, apply only the new family, and assert that prior primitives survive.

```bash
TERRANEX_TEST_DB=terranex_test bash supabase/tests/25_s7_forward_upgrade.sh
```

### Cause table

| Signature | Cause | Fix |
| --- | --- | --- |
| Fails on clean replay | Broken SQL in the migration | Fix the migration file; never patch the database |
| Passes clean, fails on existing DB | Not forward-safe (assumes an object absent/present) | Make the migration additive and idempotent-safe |
| Objects exist but RLS/triggers missing | Migration partially applied | Restore to the last known-good state and re-apply cleanly |
| App errors, schema fine | Code/schema version skew | Deploy the matching application commit |
| CI green, environment red | Environment-specific config or extension missing | Fix the environment; do not weaken the migration |

## 5. Approved recovery path

### 5a. Failure caught before any customer data was written

1. Roll the application back to the previously deployed SHA.
2. Restore the database to its pre-deployment state from the backup taken as part of the release procedure (see [`BACKUP_AND_RESTORE.md`](BACKUP_AND_RESTORE.md)).
3. Fix the migration in the repository.
4. Prove it with the full gate on the fixed commit: `npm ci`, lint, typecheck, test, build, `npm run db:test`, including the forward-upgrade suite.
5. Redeploy.

### 5b. Failure discovered after facts were written

Requires `<FINANCE_CONTROL_OWNER>`, because a restore would discard those facts.

1. Do **not** restore blindly. List the post-failure facts (section 2).
2. Prefer **rolling forward**: write a new, additive corrective migration that brings the schema to the intended state without discarding data. Terranex migrations are forward-only by convention; there is no down-migration path.
3. Prove the corrective migration with a full clean replay *and* the forward-upgrade suite from the broken boundary.
4. If the data written after the failure is itself wrong, correct it through the ordinary product paths — [`INCORRECT_POSTED_TRANSACTION.md`](INCORRECT_POSTED_TRANSACTION.md) or [`CLOSED_PERIOD_CORRECTION.md`](CLOSED_PERIOD_CORRECTION.md) — not by restoring over it.

### 5c. Application-only failure

Roll back the application. No database action is required. Fix, re-run the app gates, redeploy.

## 6. Prohibited shortcuts

- Editing a migration file that has already been applied anywhere. Add a new migration instead.
- Manual `ALTER TABLE`/`CREATE FUNCTION` in a live database to make the code work.
- Marking a migration as applied without running it.
- Deleting rows to let a constraint or unique index be created.
- Dropping a constraint, trigger, or RLS policy to unblock a deployment.
- Skipping a test suite because it is "unrelated" to the change.
- Deploying with a red gate and a plan to fix it afterwards.
- Restoring over live financial facts without `<FINANCE_CONTROL_OWNER>` authorisation.

## 7. Post-recovery verification

```bash
npm ci --no-audit --no-fund
npm run lint
npm run typecheck
npm test
npm run build
npm run db:test
```

All must pass on the deployed commit. Then:

```sql
-- Integrity after recovery.
select count(*) from (
  select batch_id from public.journal_lines group by batch_id
  having sum(debit_minor_units) <> sum(credit_minor_units) or count(*) < 2) u;

select count(*) from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
 where jl.organization_id <> jb.organization_id or jl.project_id <> jb.project_id;
```

Both must be `0`. Confirm at least one project workspace loads and shows the expected balances, and that a read-only user still cannot write.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Any failed migration | `<ENGINEERING_ONCALL>` |
| Facts written after a failed migration | `<ENGINEERING_ONCALL>` + `<FINANCE_CONTROL_OWNER>` |
| A restore is being considered | `<PILOT_OPS_OWNER>` + `<FINANCE_CONTROL_OWNER>` + `<CUSTOMER_APPROVER>` |
| A control (RLS, trigger, constraint) is missing after deployment | `<SECURITY_OWNER>` as well — treat as a potential exposure |

## 9. Communication

Tell the customer whether their data was affected, and be specific: "no financial facts were written during the window" is a claim that must be backed by the query in section 2. Give an honest status rather than an optimistic ETA. Never say a gate passed when it was not run.

## 10. Record

Record: the deployed and previous SHAs, the failing migration and its error, whether any facts were written after the failure, the recovery route taken and who authorised it, the corrective commit, and the full gate results on the final deployed commit.

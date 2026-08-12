# Runbook — Backup and restore

**Scope:** verifying that Terranex data is restorable, and executing a real restore if one is ever authorised.

> **This document distinguishes two very different things.**
>
> - The **automated rehearsal** (`supabase/tests/26_s7_backup_restore.sh`) runs on every canonical database gate. It dumps the *verification* database with `pg_dump`, restores it into a clean database with `pg_restore`, and re-runs every integrity query on the copy. It uses no production system and no production credentials.
> - A **production restore** is a live operational event on customer data. It has never been performed by the automated suite. A passing rehearsal is evidence that the schema, data, constraints, RLS and immutability triggers survive a dump/restore cycle. It is **not** evidence that a production restore has occurred, that a production backup schedule exists, or that a recovery objective has been met.
>
> Do not report a production restore as done unless a named operator actually performed one and recorded it.

---

## 1. Symptom

One of:

- Routine verification: it is time to prove that backups are restorable.
- Data loss or corruption is suspected, and restoring from backup is being considered.
- A migration or deployment failure has left the database in an unusable state.
- The customer or an auditor asks for evidence that the system is recoverable.

## 2. Immediate safety action

If this is a live incident rather than routine verification:

1. **Stop writes before you consider a restore.** Take the application out of service for the affected tenant rather than letting new facts post on top of a database you may replace.
2. **Do not drop, truncate, or overwrite anything.** A restore is performed *into a new database*, never on top of the damaged one. The damaged database is evidence.
3. **Take a fresh backup of the damaged database first.** You cannot investigate what you have overwritten.

```bash
pg_dump -Fc -d "$DAMAGED_DB" -f "incident-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

4. Notify `<ENGINEERING_ONCALL>` and `<PILOT_OPS_OWNER>` immediately. A restore decision is never taken by one person alone.

## 3. Evidence to preserve

- The pre-restore dump of the damaged database (above).
- The exact timestamp at which the problem was first observed and the last known-good timestamp.
- Application and database logs covering that window.
- The output of the integrity queries in section 4, captured *before* any restore.
- The migration state: which migration files had been applied.
- The incident ticket reference. This reference is what goes into any evidence field in the product; the logs themselves stay in the operator's systems.

## 4. Diagnosis — integrity queries

These are read-only. Run them against the database in question. They are the same checks the automated rehearsal reproduces, so a difference between a source and a restored copy is immediately visible.

```sql
-- Tenant isolation: project counts per organization.
select organization_id, count(*) from public.investment_projects group by organization_id order by 1;

-- No journal line may belong to a different tenant or project than its batch.
select count(*) from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
 where jl.organization_id <> jb.organization_id or jl.project_id <> jb.project_id;

-- Every batch must balance and have at least two lines.
select count(*) from (
  select batch_id from public.journal_lines group by batch_id
  having sum(debit_minor_units) <> sum(credit_minor_units) or count(*) < 2) u;

-- Financial totals.
select sum(debit_minor_units), sum(credit_minor_units) from public.journal_lines;
select cash_account_id, balance_minor_units from public.project_cash_position_read order by 1;
select obligation_id, outstanding_minor_units from public.cost_obligation_position_read order by 1;

-- S6 close provenance.
select id, content_hash from public.close_run_snapshots order by 1;
select id, status, version from public.accounting_periods order by 1;

-- S5 allocation and distribution.
select id, status, content_hash, source_amount_minor_units from public.s5_allocation_runs order by 1;
select distribution_id, settlement_status, outstanding_minor_units from public.s5_distributions_read order by 1;
select participant_party_id, closing_capital_minor_units from public.s5_partner_capital_statement_read order by 1;

-- S7 pilot records.
select id, status, content_hash, computed_debit_total_minor_units from public.s7_opening_imports order by 1;
select id, status, variance_minor_units, content_hash from public.s7_reconciliation_checkpoints order by 1;
select task_code, status from public.s7_uat_tasks order by 1;

-- Audit trail volume.
select count(*) from public.audit_events;
```

Structural controls must also be present. A copy that has the rows but not the controls is not a valid restore:

```sql
-- Forced default-deny RLS on every tenant table.
select c.relname, c.relrowsecurity, c.relforcerowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relname in ('organizations','memberships','investment_projects','audit_events',
   'journal_batches','journal_lines','s5_allocation_runs','s5_distributions',
   's7_opening_imports','s7_opening_import_rows','s7_reconciliation_checkpoints',
   's7_reconciliation_exceptions','s7_uat_tasks','s7_pilot_rehearsals')
 order by 1;

-- Immutability and recovery triggers.
select tgname from pg_trigger where not tgisinternal and tgname in (
  'journal_batches_immutable','journal_lines_immutable',
  's7_opening_imports_transition_guard','s7_opening_imports_no_delete',
  's7_reconciliation_checkpoints_immutable','memberships_last_active_owner_guard')
 order by 1;
```

## 5. Approved procedure

### 5a. Routine verification (no production involvement)

Run the canonical database gate. It executes the rehearsal as part of the suite:

```bash
npm run db:test
```

The rehearsal prints `S7 backup and restore rehearsal PASS (N integrity checks reproduced exactly)` and records a `BACKUP_RESTORE` rehearsal fact against the rehearsal project. If it cannot find a `pg_dump`/`pg_restore` of a high enough major version it **fails loudly and exits non-zero**; it never skips itself. A skipped gate is a failed gate.

To run only the rehearsal against an existing verification database:

```bash
TERRANEX_TEST_DB=terranex_test bash supabase/tests/26_s7_backup_restore.sh
```

### 5b. Taking a production backup

Standard PostgreSQL tooling only. No custom tooling, no application-level export.

```bash
# Credentials come from the operator's secret store, never from this repository,
# never from a shell history, never pasted into a ticket.
pg_dump -Fc -d "$PROD_URL" -f "terranex-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

The artifact is written to the customer's approved encrypted storage with restricted permissions. It contains real customer data and is therefore treated as confidential material: it is never committed to a repository, attached to a ticket, or copied to a developer workstation.

### 5c. Performing an authorised restore

A restore requires explicit written authorisation from `<CUSTOMER_APPROVER>` and `<FINANCE_CONTROL_OWNER>`, because it can discard financial facts recorded after the backup point.

1. Confirm the target: a **new, empty** database. Never restore over a live database.

   ```bash
   createdb "$RESTORE_DB"
   ```

2. Restore.

   ```bash
   pg_restore -d "$RESTORE_DB" --no-owner --no-privileges "$BACKUP_FILE"
   ```

3. Verify before cutting over. Run every query in section 4 against `$RESTORE_DB` and compare to the values recorded from the backup source. **Any difference stops the cutover.** In particular:
   - unbalanced batches must be `0`;
   - cross-tenant journal lines must be `0`;
   - forced RLS must be `true` on every listed table;
   - all six immutability/recovery triggers must be present.

4. Prove that immutability survived. This must fail:

   ```sql
   update public.journal_lines set debit_minor_units = debit_minor_units + 1;
   -- expected: ERROR ... immutable once posted
   ```

   If that statement succeeds, the restore is not usable. Stop and escalate to `<ENGINEERING_ONCALL>`.

5. Quantify the gap. List every financial fact recorded after the backup point that the restore would discard:

   ```sql
   select id, source_type, transaction_date, posted_at
     from public.journal_batches where posted_at > :backup_taken_at order by posted_at;
   ```

   `<FINANCE_CONTROL_OWNER>` and `<CUSTOMER_APPROVER>` must acknowledge this list in writing before cutover. Facts that must survive are re-entered afterwards through the ordinary product commands, with their own evidence references — never by hand-editing the restored database.

6. Cut over only after steps 3–5 pass and are recorded.

## 6. Prohibited shortcuts

- Restoring on top of a live database.
- Restoring without first backing up the damaged database.
- Cutting over without running the integrity queries on the restored copy.
- Disabling triggers, RLS, or constraints "temporarily" to make a restore load cleanly. If the data does not load with the controls in place, the data is the problem.
- Re-entering post-backup transactions with `INSERT` statements instead of product commands.
- Using production credentials on a developer machine, or copying a production dump outside approved storage.
- Reporting the automated rehearsal as a production restore.

## 7. Post-recovery verification

- Every integrity query in section 4 matches expectations, with output attached to the incident record.
- The tamper check in step 4 of section 5c still fails as designed.
- The application loads for at least one project per affected tenant and shows the expected balances.
- A reconciliation checkpoint is recorded for project cash against the customer's own bank statement, and it either matches exactly or opens an exception with an owner.
- Any facts re-entered after the restore are visible with their own audit events.

## 8. Escalation

| Situation | Owner |
| --- | --- |
| Rehearsal fails in CI | `<ENGINEERING_ONCALL>` |
| Backup artifact missing, empty, or unreadable | `<ENGINEERING_ONCALL>`, then `<PILOT_OPS_OWNER>` |
| Restore considered on customer data | `<PILOT_OPS_OWNER>` + `<FINANCE_CONTROL_OWNER>` + `<CUSTOMER_APPROVER>` |
| Restored copy fails an integrity or immutability check | `<ENGINEERING_ONCALL>` — do not cut over |
| Suspected exposure of a backup artifact | `<SECURITY_OWNER>` immediately |

## 9. Communication

Tell the customer what is factually known: what was observed, what has been preserved, what is being verified, and what data — if any — is at risk of being discarded. Do not promise a recovery time before the restore has been verified on a copy. Do not describe the automated rehearsal as if it were a restore of their data.

## 10. Record

Write into the incident record: the trigger for the procedure, the backup artifact identifier and its timestamp, who authorised any restore, the integrity query output before and after, the list of facts discarded or re-entered, and the verification result. If a production restore was performed, record it as an operator action with a named operator; the automated `BACKUP_RESTORE` rehearsal fact in the product is separate and must not be presented as that event.

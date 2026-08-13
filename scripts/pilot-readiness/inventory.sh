#!/usr/bin/env bash
# Pilot/GA readiness inventory — zero-dependency repository inspection.
#
# Reports the presence of the artifacts the controlled paid pilot depends on:
# canonical Greenfield documents, operator runbooks, S7 rehearsal suites, CI
# workflow, environment contract, and this readiness pack itself.
#
# It reads the repository only. It never reads secret values, never touches
# the network, and never modifies anything. Exit code: 0 = inventory complete
# (missing items listed, if any), 1 = required item missing.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

MISSING=0
TOTAL=0

have() { # have <path> <label>
  TOTAL=$((TOTAL + 1))
  if [ -e "$1" ]; then
    printf '  OK    %s\n' "$2"
  else
    printf '  MISS  %s  (%s)\n' "$2" "$1"
    MISSING=$((MISSING + 1))
  fi
}

count() { # count <glob-label> <count>
  printf '  COUNT %-44s %s\n' "$1" "$2"
}

echo "== Terranex pilot readiness inventory =="
echo "repo: $REPO_ROOT"
echo "commit: $(git rev-parse HEAD 2>/dev/null || echo 'not a git checkout')"
echo

echo "-- Canonical Greenfield documents --"
for f in 01_PRODUCT_CHARTER_AND_MARKET 02_OPERATING_MODEL_AND_JOURNEYS \
         03_DOMAIN_MODEL 04_SECTOR_MODELS 05_FINANCE_AND_ACCOUNTING \
         06_SYSTEM_ARCHITECTURE_AND_SECURITY 07_UX_INFORMATION_ARCHITECTURE \
         08_MVP_AND_DELIVERY_ROADMAP; do
  have "docs/greenfield/${f}.md" "greenfield/${f}"
done

echo "-- Operator runbooks (S7 set + pilot operating gaps G-01/G-02) --"
for f in README FAILED_OPENING_IMPORT INCORRECT_POSTED_TRANSACTION UNRECONCILED_CASH \
         FAILED_ALLOCATION_OR_DISTRIBUTION CLOSED_PERIOD_CORRECTION \
         MEMBERSHIP_AND_ACCESS_INCIDENT CROSS_TENANT_OR_SECURITY_INCIDENT \
         BACKUP_AND_RESTORE FAILED_DEPLOYMENT_OR_MIGRATION SUPPORT_ESCALATION \
         CLOSE_RUN_GATE_FAILURE NON_CASH_CHECKPOINT_VARIANCE; do
  have "docs/runbooks/${f}.md" "runbook ${f}"
done

echo "-- S7 verification suites --"
have "supabase/tests/27_s7_end_to_end_rehearsal.sql" "S7 end-to-end rehearsal"
have "supabase/tests/26_s7_backup_restore.sh" "S7 backup/restore rehearsal"
have "scripts/db-test.sh" "canonical database gate runner"

echo "-- Engineering gates --"
have ".github/workflows/greenfield-ci.yml" "Greenfield CI workflow"
have ".env.example" "environment contract (.env.example)"
have "package.json" "application package manifest"

MIGRATIONS=$(ls supabase/migrations/*.sql 2>/dev/null | wc -l | tr -d ' ')
count "ordered migrations" "$MIGRATIONS"
DBTESTS=$(ls supabase/tests/* 2>/dev/null | wc -l | tr -d ' ')
count "database verification suites" "$DBTESTS"

echo "-- Pilot readiness pack --"
for f in README 01_PILOT_READINESS_MAP 02_DATA_INTAKE_CONTRACT \
         03_OPENING_BALANCE_CONTROL_PACK 04_PILOT_RUNBOOK_WEEKS_0_TO_4 \
         05_UAT_ACCEPTANCE_MATRIX 06_RECONCILIATION_PROCEDURES \
         07_INCIDENT_SUPPORT_MATRIX 08_DEPLOYMENT_ENVIRONMENT_CHECKLIST \
         09_PILOT_ROLES_AND_RESPONSIBILITIES 10_COMMERCIAL_HANDOFF_REQUIREMENTS \
         11_GA_READINESS_BACKLOG; do
  have "docs/pilot-readiness/${f}.md" "pilot-readiness/${f}"
done
for f in opening-import-worksheet.csv source-data-coverage-tracker.csv pilot-evidence-register.csv; do
  have "docs/pilot-readiness/templates/${f}" "template ${f}"
done
have "scripts/pilot-readiness/check-readiness-pack.sh" "readiness pack validator"

echo
echo "checked: $TOTAL, missing: $MISSING"
if [ "$MISSING" -gt 0 ]; then
  echo "RESULT: FAIL — required readiness artifacts missing"
  exit 1
fi
echo "RESULT: PASS — all required readiness artifacts present"

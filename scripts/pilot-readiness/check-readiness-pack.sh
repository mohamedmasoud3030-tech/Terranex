#!/usr/bin/env bash
# Pilot/GA readiness pack validator — zero-dependency drift detection.
#
# The readiness documents in docs/pilot-readiness/ cite concrete product
# constants (S7 opening mapping codes, S7 reconciliation checkpoint codes,
# S6 close gate codes, environment variable names, runbook file names, UAT
# task code pattern). Those constants are owned by migrations and shipped
# code; if a future change moves them, this script detects the drift.
#
# It validates NAMES and structure only. It never reads secret values, never
# connects to anything, and never modifies the repository.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

PACK=docs/pilot-readiness
FAILURES=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

echo "== Pilot readiness pack validation =="

# ---------------------------------------------------------------------------
# 1. Pack completeness.
# ---------------------------------------------------------------------------
echo "-- Pack files --"
for f in README.md 01_PILOT_READINESS_MAP.md 02_DATA_INTAKE_CONTRACT.md \
         03_OPENING_BALANCE_CONTROL_PACK.md 04_PILOT_RUNBOOK_WEEKS_0_TO_4.md \
         05_UAT_ACCEPTANCE_MATRIX.md 06_RECONCILIATION_PROCEDURES.md \
         07_INCIDENT_SUPPORT_MATRIX.md 08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md \
         09_PILOT_ROLES_AND_RESPONSIBILITIES.md 10_COMMERCIAL_HANDOFF_REQUIREMENTS.md \
         11_GA_READINESS_BACKLOG.md; do
  if [ -f "$PACK/$f" ]; then pass "$f"; else fail "$f missing"; fi
done
for f in opening-import-worksheet.csv source-data-coverage-tracker.csv pilot-evidence-register.csv; do
  if [ -f "$PACK/templates/$f" ]; then
    LINES=$(wc -l < "$PACK/templates/$f" | tr -d ' ')
    if [ "$LINES" -eq 1 ]; then
      pass "template $f is header-only (no customer data)"
    else
      fail "template $f must be header-only, found $LINES lines"
    fi
  else
    fail "template $f missing"
  fi
done

# ---------------------------------------------------------------------------
# 2. S7 opening mapping codes: migration registry vs intake contract.
# ---------------------------------------------------------------------------
echo "-- S7 opening mapping codes --"
MIG_OPENING=supabase/migrations/20260812000200_s7_opening_import.sql
REGISTRY=$(sed -n '/insert into public.s7_opening_mapping_codes/,/;/p' "$MIG_OPENING" \
  | grep -oE "'OPENING_[A-Z_]+'" | tr -d "'" | sort -u)
if [ -z "$REGISTRY" ]; then
  fail "could not extract mapping registry from migration"
else
  pass "migration registry holds $(echo "$REGISTRY" | wc -l | tr -d ' ') mapping codes"
fi
for code in $REGISTRY; do
  if grep -q "$code" "$PACK/02_DATA_INTAKE_CONTRACT.md"; then
    pass "intake contract cites $code"
  else
    fail "intake contract is missing mapping code $code"
  fi
done
# Drift the other way: intake contract must not cite invented OPENING_* codes.
# Pack filenames (NN_NAME.md) are stripped first so markdown cross-references
# like 03_OPENING_BALANCE_CONTROL_PACK.md cannot masquerade as mapping codes.
CITED=$(sed -E 's/[0-9]{2}_[A-Z_]+\.md//g' "$PACK/02_DATA_INTAKE_CONTRACT.md" \
  | grep -oE 'OPENING_[A-Z_]+' | sort -u)
for code in $CITED; do
  case "$code" in OPENING_IMPORT) continue ;; esac # journal source type, not a mapping code
  if ! printf '%s\n' "$REGISTRY" | grep -qx "$code"; then
    fail "intake contract cites unknown mapping code $code"
  fi
done

# ---------------------------------------------------------------------------
# 3. S7 reconciliation checkpoint codes: migration vs procedures.
# ---------------------------------------------------------------------------
echo "-- S7 reconciliation checkpoint codes --"
MIG_RECON=supabase/migrations/20260812000210_s7_pilot_reconciliation.sql
CHECKPOINTS=$(sed -n '/checkpoint_code text not null check (checkpoint_code in (/,/)),/p' "$MIG_RECON" \
  | grep -oE "'[A-Z_]+'" | tr -d "'" | sort -u)
if [ -z "$CHECKPOINTS" ]; then
  fail "could not extract checkpoint codes from migration"
else
  pass "migration defines $(echo "$CHECKPOINTS" | wc -l | tr -d ' ') checkpoint codes"
fi
for code in $CHECKPOINTS; do
  if grep -q "$code" "$PACK/06_RECONCILIATION_PROCEDURES.md"; then
    pass "reconciliation procedures cite $code"
  else
    fail "reconciliation procedures miss checkpoint code $code"
  fi
done

# ---------------------------------------------------------------------------
# 4. S6 close gate codes: migration vs runbook/checklist documents.
# ---------------------------------------------------------------------------
echo "-- S6 close gate codes --"
MIG_CLOSE=supabase/migrations/20260811000600_s6_period_close_and_correction.sql
GATES=$(sed -n '/gate_code text not null check (gate_code in (/,/)),/p' "$MIG_CLOSE" \
  | grep -oE "'[A-Z_]+'" | tr -d "'" | sort -u)
if [ -z "$GATES" ]; then
  fail "could not extract close gate codes from migration"
else
  pass "migration defines $(echo "$GATES" | wc -l | tr -d ' ') close gates"
fi
for code in $GATES; do
  if grep -q "$code" "$PACK/04_PILOT_RUNBOOK_WEEKS_0_TO_4.md" \
     && grep -q "$code" "$PACK/06_RECONCILIATION_PROCEDURES.md"; then
    pass "close gate $code cited in runbook and procedures"
  else
    fail "close gate $code not cited in both 04 and 06"
  fi
done

# ---------------------------------------------------------------------------
# 5. Environment contract: .env.example names vs deployment checklist.
#    Names only — no secret value is ever read or printed.
# ---------------------------------------------------------------------------
echo "-- Environment variable names --"
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  NAME=${line%%=*}
  if grep -q "$NAME" "$PACK/08_DEPLOYMENT_ENVIRONMENT_CHECKLIST.md"; then
    pass "checklist covers env variable name $NAME"
  else
    fail "checklist does not mention env variable $NAME from .env.example"
  fi
done < .env.example

# ---------------------------------------------------------------------------
# 6. Runbook references in the incident matrix resolve to real runbooks.
# ---------------------------------------------------------------------------
echo "-- Runbook references --"
# Proposed-but-not-yet-written runbooks are documented as gaps in 07 and are
# the only acceptable unresolved names.
PROPOSED="CLOSE_RUN_GATE_FAILURE.md"
# Pack filenames (NN_NAME.md) are stripped first so cross-references to this
# pack's own documents are not mistaken for runbook references.
REFS=$(sed -E 's/[0-9]{2}_[A-Z_]+\.md//g' "$PACK/07_INCIDENT_SUPPORT_MATRIX.md" \
  | grep -oE '[A-Z][A-Z_]+\.md' | sort -u)
for ref in $REFS; do
  case " $PROPOSED " in *" $ref "*)
    pass "$ref referenced as proposed gap (not required yet)"; continue ;;
  esac
  if [ -f "docs/runbooks/$ref" ]; then
    pass "runbook $ref exists"
  else
    fail "07 references runbook $ref which does not exist"
  fi
done

# ---------------------------------------------------------------------------
# 7. UAT task codes match the product pattern ^S7-UAT-[A-Z0-9-]{2,40}$.
# ---------------------------------------------------------------------------
echo "-- UAT task codes --"
UAT_CODES=$(grep -oE 'S7-UAT-[A-Z0-9-]+' "$PACK/05_UAT_ACCEPTANCE_MATRIX.md" | sort -u)
BAD=0
for code in $UAT_CODES; do
  suffix=${code#S7-UAT-}
  if ! printf '%s' "$suffix" | grep -qE '^[A-Z0-9-]{2,40}$'; then
    fail "UAT code $code violates product pattern S7-UAT-[A-Z0-9-]{2,40}"
    BAD=1
  fi
done
if [ "$BAD" -eq 0 ]; then
  pass "all $(echo "$UAT_CODES" | wc -l | tr -d ' ') cited UAT codes match the product pattern"
fi
# Every scenario heading ## UAT-NN implies a registerable task code S7-UAT-NN.
SCENARIOS=$(grep -oE '^## UAT-[A-Z0-9-]+' "$PACK/05_UAT_ACCEPTANCE_MATRIX.md" \
  | sed 's/^## //' | sort -u)
SCENARIO_BAD=0
for sc in $SCENARIOS; do
  suffix=${sc#UAT-}
  if ! printf '%s' "$suffix" | grep -qE '^[A-Z0-9-]{2,40}$'; then
    fail "scenario $sc would not register as S7-UAT-$suffix under the product pattern"
    SCENARIO_BAD=1
  fi
done
if [ "$SCENARIO_BAD" -eq 0 ]; then
  pass "all $(echo "$SCENARIOS" | wc -l | tr -d ' ') UAT scenarios map to registerable S7-UAT task codes"
fi

# ---------------------------------------------------------------------------
# 8. No customer data / secrets in the pack.
# ---------------------------------------------------------------------------
echo "-- Hygiene --"
if grep -rniE '(api[_-]?key|service[_-]?role|password|secret)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9]' "$PACK" | grep -vqi 'names only'; then
  fail "pack may contain a literal secret-like assignment"
else
  pass "no literal secret-like assignments found (names-only policy)"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: FAIL — $FAILURES check(s) failed"
  exit 1
fi
echo "RESULT: PASS — readiness pack consistent with shipped product constants"

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
# The G-01/G-02 runbooks are now mandatory parts of the runbook set; no
# proposed-but-unwritten runbook names are allowed in the matrix anymore.
PROPOSED=""
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
# 7. Canonical delivery gates: technical verification vs delivery exits.
#    The pack must state the Phase 2/3 exit wording explicitly and must not
#    let "verified main" imply any canonical delivery exit has passed.
# ---------------------------------------------------------------------------
echo "-- Canonical delivery gate wording --"
if grep -q "## Delivery status (read first)" "$PACK/README.md" \
   && grep -q "Phase 2 exit" "$PACK/README.md" \
   && grep -q "Phase 3 exit" "$PACK/README.md" \
   && grep -q "Not passed" "$PACK/README.md" \
   && grep -q "Not started" "$PACK/README.md"; then
  pass "README carries an explicit delivery-status section with Phase 2/3 exits not passed"
else
  fail "README delivery-status section missing or no longer marks Phase 2/3 exits as not passed"
fi
if grep -q "a real opening project can be imported and every financial balance reproduced" "$PACK/01_PILOT_READINESS_MAP.md"; then
  pass "map cites the canonical Phase 2 exit wording"
else
  fail "map no longer cites the canonical Phase 2 exit wording"
fi
if grep -q "in staging" "$PACK/01_PILOT_READINESS_MAP.md" \
   && grep -q "## PRM-09B" "$PACK/01_PILOT_READINESS_MAP.md"; then
  pass "map defines the PRM-09B real-project staging gate (canonical Phase 3 exit)"
else
  fail "map is missing the PRM-09B real-project staging gate or Phase 3 staging wording"
fi
if grep -q "synthetic fixture rehearsal is not" "$PACK/01_PILOT_READINESS_MAP.md" \
   && grep -q "synthetic fixture rehearsal is not" "$PACK/04_PILOT_RUNBOOK_WEEKS_0_TO_4.md"; then
  pass "map and runbook state that fixture rehearsals are not real-project staging"
else
  fail "fixture-vs-real-staging distinction missing from map or Week 0 runbook"
fi
if grep -q "PRM-09B" "$PACK/04_PILOT_RUNBOOK_WEEKS_0_TO_4.md"; then
  pass "Week 0 runbook requires the real-project staging proof before go-live"
else
  fail "Week 0 runbook does not reference the PRM-09B staging proof"
fi

# ---------------------------------------------------------------------------
# 8. Phase 5 must stay behind Phase 4 exit.
# ---------------------------------------------------------------------------
echo "-- Phase 5 sequencing lock --"
if grep -q "Phase 4 exit (PRM-16)" "$PACK/11_GA_READINESS_BACKLOG.md" \
   && grep -q "must not start" "$PACK/11_GA_READINESS_BACKLOG.md" \
   && grep -q "Do not start WP1" "$PACK/11_GA_READINESS_BACKLOG.md"; then
  pass "GA backlog keeps every Phase 5 package behind Phase 4 exit"
else
  fail "GA backlog no longer pins Phase 5/WP1 behind Phase 4 exit"
fi
if grep -q "Safe pre-pilot preparation" "$PACK/11_GA_READINESS_BACKLOG.md" \
   && grep -q "Phase 4 operational execution" "$PACK/11_GA_READINESS_BACKLOG.md" \
   && grep -q "Phase 5 productization" "$PACK/11_GA_READINESS_BACKLOG.md"; then
  pass "GA backlog distinguishes preparation vs pilot execution vs productization"
else
  fail "GA backlog lost the preparation/execution/productization distinction"
fi

# ---------------------------------------------------------------------------
# 9. No accidentally completed customer/human gates.
# ---------------------------------------------------------------------------
echo "-- Human gates still pending --"
if grep -q 'Status of every scenario below: `PENDING`' "$PACK/05_UAT_ACCEPTANCE_MATRIX.md" \
   && grep -q -- "— pending —" "$PACK/05_UAT_ACCEPTANCE_MATRIX.md"; then
  pass "UAT matrix still marks every scenario pending with an empty acceptance summary"
else
  fail "UAT matrix appears to mark scenarios passed or lost its pending markers"
fi
if grep -rq "production_restore_performed: true" "$PACK"; then
  fail "pack claims a production restore was performed"
else
  pass "no production restore is claimed anywhere in the pack"
fi
CLAIM_HITS=$(grep -rniE "deployment occurred|customer onboarding occurred|UAT passed|weekly reconciliation occurred|buyer acceptance obtained|GA readiness (is|has been) achieved" "$PACK" \
  | grep -viE "not|never|without|no |unless" | wc -l | tr -d ' ')
if [ "$CLAIM_HITS" -eq 0 ]; then
  pass "no accidentally completed pilot/customer gate claims found"
else
  fail "$CLAIM_HITS line(s) may claim a completed customer gate — review them"
fi

# ---------------------------------------------------------------------------
# 10. UAT task codes match the product pattern ^S7-UAT-[A-Z0-9-]{2,40}$.
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

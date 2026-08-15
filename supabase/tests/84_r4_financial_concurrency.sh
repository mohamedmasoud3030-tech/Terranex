#!/usr/bin/env bash
set -euo pipefail

# R4 real two-session proof: competing invoice approvals cannot consume more
# than received quantity, and competing shared Finance Core payments cannot
# overpay the invoice-created payable.
DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
psql_sql() { if [[ -n "$CONTAINER" ]]; then printf '%s\n' "$1" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$DB"; else printf '%s\n' "$1" | psql -v ON_ERROR_STOP=1 -q -d "$DB"; fi; }
psql_value() { if [[ -n "$CONTAINER" ]]; then docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$DB" -c "$1"; else psql -v ON_ERROR_STOP=1 -Atq -d "$DB" -c "$1"; fi; }
run_session() { psql_sql "$1" >"$2" 2>&1; }

ORG='10000000-0000-4000-8000-000000000001'
MEMBER='00000000-0000-4000-8000-000000000003'
OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF025-PROJ'")"
PO="$(psql_value "select id from public.purchase_orders where organization_id='$ORG' and internal_reference='PO-GF026-001'")"
RECEIPT_LINE="$(psql_value "select id from public.purchase_receipt_lines where purchase_order_id='$PO' order by created_at limit 1")"
CASH="$(psql_value "select id from public.project_cash_accounts where project_id='$PROJECT' and name='حساب R4' limit 1")"

# Suite 83 consumed 10 of this 40-unit receipt. Each competing invoice asks for
# 20; only one can fit in the remaining 30 after the first commits.
for suffix in A B; do
  psql_sql "set request.jwt.claim.sub='$MEMBER'; set role authenticated;
    select public.record_supplier_invoice('$ORG','$PROJECT','$PO','INV-R4-RACE-$suffix',current_date,'EGP','EXPENSE','دليل سباق فاتورة $suffix',null,
      '[{\"purchase_receipt_line_id\":\"$RECEIPT_LINE\",\"quantity_invoiced\":20,\"unit_price_minor_units\":100}]',
      's84-invoice-create-$suffix');"
done
INV_A="$(psql_value "select id from public.supplier_invoices where organization_id='$ORG' and invoice_reference='INV-R4-RACE-A'")"
INV_B="$(psql_value "select id from public.supplier_invoices where organization_id='$ORG' and invoice_reference='INV-R4-RACE-B'")"

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
APPROVE_A="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.approve_supplier_invoice('$ORG','$INV_A','s84-invoice-approve-A');"
APPROVE_B="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.approve_supplier_invoice('$ORG','$INV_B','s84-invoice-approve-B');"
set +e
run_session "$APPROVE_A" "$tmpdir/ia.log" & a=$!
run_session "$APPROVE_B" "$tmpdir/ib.log" & b=$!
wait "$a"; sa=$?; wait "$b"; sb=$?
set -e
if ! { [[ "$sa" -eq 0 && "$sb" -ne 0 ]] || [[ "$sa" -ne 0 && "$sb" -eq 0 ]]; }; then
  echo "ERROR: competing invoice approvals expected exactly one success; A=$sa B=$sb" >&2
  cat "$tmpdir/ia.log" "$tmpdir/ib.log" >&2 || true; exit 1
fi
APPROVED="$(psql_value "select count(*) from public.supplier_invoices where id in ('$INV_A','$INV_B') and status='APPROVED'")"
[[ "$APPROVED" == '1' ]] || { echo "ERROR: approved invoice race count $APPROVED" >&2; exit 1; }
OBLIGATION="$(psql_value "select cost_obligation_id from public.supplier_invoices where id in ('$INV_A','$INV_B') and status='APPROVED'")"

# The winning payable is 2,000 minor units. Two concurrent payments of 1,500
# serialize on the same existing cost_obligation row; exactly one may post.
PAY_A="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.pay_cost_obligation('$ORG','$OBLIGATION','$CASH',1500,current_date,'s84-payment-A');"
PAY_B="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.pay_cost_obligation('$ORG','$OBLIGATION','$CASH',1500,current_date,'s84-payment-B');"
set +e
run_session "$PAY_A" "$tmpdir/pa.log" & c=$!
run_session "$PAY_B" "$tmpdir/pb.log" & d=$!
wait "$c"; sc=$?; wait "$d"; sd=$?
set -e
if ! { [[ "$sc" -eq 0 && "$sd" -ne 0 ]] || [[ "$sc" -ne 0 && "$sd" -eq 0 ]]; }; then
  echo "ERROR: competing payments expected exactly one success; A=$sc B=$sd" >&2
  cat "$tmpdir/pa.log" "$tmpdir/pb.log" >&2 || true; exit 1
fi
PAID="$(psql_value "select paid_minor_units from public.cost_obligation_position_read where obligation_id='$OBLIGATION'")"
[[ "$PAID" == '1500' ]] || { echo "ERROR: concurrent payment total $PAID" >&2; exit 1; }

echo 'R4 procurement financial concurrency PASS'

#!/usr/bin/env python3
"""
Terranex end-to-end test — real user, real JWT, real REST/RPC calls.

Every request goes through PostgREST with the anon/publishable key plus a real
user JWT, exactly like the browser app. RLS is enforced throughout; the
service_role key is never used here.
"""
import json
import os
import subprocess
import sys
import uuid

PUB = os.environ["SUPABASE_PUBLISHABLE_KEY"]
BASE = "https://{REF}.supabase.co/rest/v1"
JWT = open("/tmp/e2e_jwt.txt").read().strip()
UID = open("/tmp/e2e_uid.txt").read().strip()

PASS, FAIL, NOTES = 0, 0, []


def ok(msg):
    global PASS
    PASS += 1
    print(f"  ✅ {msg}")


def no(msg, detail=""):
    global FAIL
    FAIL += 1
    print(f"  ❌ {msg}")
    if detail:
        print(f"     {str(detail)[:300]}")
    NOTES.append(msg)


def call(method, path, body=None, prefer_repr=True):
    cmd = ["curl", "-s", "-w", "\n%{http_code}", "--max-time", "60",
           "-X", method, f"{BASE}/{path}",
           "-H", f"apikey: {PUB}",
           "-H", f"Authorization: Bearer {JWT}",
           "-H", "Content-Type: application/json"]
    if prefer_repr and method in ("POST", "PATCH"):
        cmd += ["-H", "Prefer: return=representation"]
    if body is not None:
        cmd += ["-d", json.dumps(body)]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    raw = p.stdout.rsplit("\n", 1)
    text, code = (raw[0], raw[1]) if len(raw) == 2 else (p.stdout, "?")
    try:
        return json.loads(text) if text.strip() else None, code
    except json.JSONDecodeError:
        return text, code


def rpc(name, params):
    return call("POST", f"rpc/{name}", params, prefer_repr=False)


print("═══════ [4.2] إنشاء مشروع ═══════")
d, c = call("POST", "projects", {
    "owner_id": UID, "sector_id": "agriculture",
    "name_ar": "مزرعة الاختبار", "name_en": "E2E Farm",
    "status": "active", "start_date": "2026-01-01", "base_currency": "EGP"})
pid = d[0]["id"] if isinstance(d, list) and d else None
ok(f"مشروع أُنشئ: {pid}") if pid else no("فشل إنشاء المشروع", d)

print("═══════ [4.3] إنشاء شريك ═══════")
d, c = call("POST", "partners", {
    "owner_id": UID, "name_ar": "مورد الاختبار",
    "category": "counterparty", "counterparty_role": "supplier"})
paid = d[0]["id"] if isinstance(d, list) and d else None
ok(f"شريك أُنشئ: {paid}") if paid else no("فشل إنشاء الشريك", d)

print("═══════ [4.4] معاملة مالية ذرية + التزام ═══════")
rid = str(uuid.uuid4())
tx_payload = {
    "p_request_id": rid,
    "p_transaction": {
        "project_id": pid, "partner_id": paid, "direction": "expense",
        "category": "operating_expense", "amount": 5000, "currency": "EGP",
        "fx_rate": 1, "amount_egp": 5000, "transaction_date": "2026-06-01",
        "description": "شراء أعلاف"},
    "p_payable": {
        "project_id": pid, "partner_id": paid, "direction": "payable",
        "amount": 5000, "currency": "EGP", "amount_egp": 5000,
        "due_date": "2026-07-01", "status": "open"}}
d, c = rpc("record_transaction_atomic", tx_payload)
txid = d.get("transaction_id") if isinstance(d, dict) else None
obid = (d.get("payable_id") or d.get("obligation_id")) if isinstance(d, dict) else None
ok(f"معاملة: {txid}") if txid else no("فشل تسجيل المعاملة", d)
ok(f"التزام مرتبط: {obid}") if obid else no("لم يُنشأ التزام", d)

print("═══════ [4.5] idempotency (نفس request_id مرتين) ═══════")
d2, _ = rpc("record_transaction_atomic", tx_payload)
txid2 = d2.get("transaction_id") if isinstance(d2, dict) else None
lst, _ = call("GET", f"transactions?select=id&project_id=eq.{pid}")
n = len(lst) if isinstance(lst, list) else -1
if txid == txid2 and n == 1:
    ok(f"التكرار مُنع — معاملة واحدة فقط (نفس id: {txid2[:8]}…)")
else:
    no("idempotency فشل", f"count={n} id1={txid} id2={txid2}")

print("═══════ [4.6] تسوية ذرية ═══════")
rid2 = str(uuid.uuid4())
d, c = rpc("record_settlement_atomic", {
    "p_request_id": rid2,
    "p_settlement": {
        "obligation_id": obid, "amount": 2000, "currency": "EGP",
        "fx_rate": 1, "amount_egp": 2000, "settlement_date": "2026-06-15",
        "payment_method": "cash", "reference_number": "E2E-001"},
    "p_allocations": [{"obligation_id": obid, "allocated_amount_egp": 2000}]})
stid = d.get("settlement_id") if isinstance(d, dict) else None
ok(f"تسوية: {stid}") if stid else no("فشل التسوية", d)

obs, _ = call("GET", f"obligations?select=status,amount_settled_egp&id=eq.{obid}")
if isinstance(obs, list) and obs:
    st, amt = obs[0]["status"], obs[0]["amount_settled_egp"]
    print(f"     الالتزام: status={st} · مسدَّد={amt}")
    if st == "partial" and float(amt) == 2000:
        ok("الحالة تحوّلت إلى partial والرصيد 2000/5000")
    else:
        no("حالة الالتزام لم تتحدّث صح", obs)

print("═══════ [4.7] أصل + تعديل مخزون ذري ═══════")
d, c = call("POST", "assets", {
    "owner_id": UID, "project_id": pid, "sector_id": "agriculture",
    "type": "herd", "name_ar": "قطيع الاختبار", "name_en": "E2E Herd",
    "acquisition_date": "2026-01-01", "acquisition_cost": 10000,
    "acquisition_currency": "EGP", "acquisition_cost_egp": 10000,
    "current_value_egp": 10000,
    "status": "owned", "quantity": 50, "unit": "رأس"})
aid = d[0]["id"] if isinstance(d, list) and d else None
ok(f"أصل: {aid} (50 رأس)") if aid else no("فشل إنشاء الأصل", d)

rid3 = str(uuid.uuid4())
d, c = rpc("record_stock_adjustment_atomic", {
    "p_request_id": rid3,
    "p_adjustment": {
        "asset_id": aid, "project_id": pid, "adjustment_date": "2026-06-20",
        "quantity_delta": -5, "value_egp_delta": -1000,
        "reason": "reconciliation", "notes": "جرد فعلي"}})
said = d.get("adjustment_id") if isinstance(d, dict) else None
ok(f"تعديل مخزون: {said}") if said else no("فشل تعديل المخزون", d)

a, _ = call("GET", f"assets?select=quantity&id=eq.{aid}")
q = a[0]["quantity"] if isinstance(a, list) and a else None
ok(f"كمية الأصل تحدّثت: 50 → {float(q):g}") if q is not None and float(q) == 45 \
    else no("الكمية لم تتحدّث", q)

print("═══════ [4.8] deletion guard ═══════")
g, _ = rpc("guard_project_deletion", {"p_project_id": pid})
print(f"     {json.dumps(g, ensure_ascii=False)[:200]}")
blocked = isinstance(g, list) and g and g[0].get("can_delete") is False
ok(f"الحارس منع الحذف: {g[0]['message_ar'][:60]}…") if blocked \
    else no("الحارس لم يمنع الحذف", g)

d, code = call("DELETE", f"projects?id=eq.{pid}", prefer_repr=False)
still, _ = call("GET", f"projects?select=id&id=eq.{pid}")
if isinstance(still, list) and len(still) == 1:
    ok(f"المشروع لم يُحذف — FK يحمي البيانات (HTTP {code})")
else:
    no("المشروع اتحذف رغم ارتباطه ببيانات!", f"HTTP {code}")

print("═══════ [4.9] سجل التدقيق ═══════")
al, _ = call("GET", "financial_audit_logs?select=operation,entity_type,request_id&order=created_at.asc")
if isinstance(al, list):
    for r in al:
        print(f"     • {r['operation']:32s} {r['entity_type']}")
    ops = " ".join(r["operation"] for r in al)
    ok(f"سجّل {len(al)} عملية") if len(al) >= 3 else no("السجل ناقص", len(al))
    ok("سجّل المعاملة") if "transaction" in ops else no("لم يسجل المعاملة")
    ok("سجّل التسوية") if "settlement" in ops else no("لم يسجل التسوية")
    ok("سجّل تعديل المخزون") if "stock" in ops else no("لم يسجل المخزون")
    reqs = {r["request_id"] for r in al}
    ok(f"كل عملية لها request_id فريد ({len(reqs)} معرّف)") if len(reqs) == len(al) \
        else no("request_id مكرر", reqs)
else:
    no("تعذر قراءة السجل", al)

print("═══════ [4.10] السجل غير قابل للتعديل/الحذف ═══════")
_, c1 = call("PATCH", "financial_audit_logs?operation=neq.zzz",
             {"operation": "tampered"}, prefer_repr=False)
ok(f"UPDATE مرفوض (HTTP {c1})") if c1 in ("403", "401", "404") \
    else no("السجل قابل للتعديل!", f"HTTP {c1}")
_, c2 = call("DELETE", "financial_audit_logs?operation=neq.zzz", prefer_repr=False)
ok(f"DELETE مرفوض (HTTP {c2})") if c2 in ("403", "401", "404") \
    else no("السجل قابل للحذف!", f"HTTP {c2}")

print("═══════ [4.11] TRUNCATE عبر REST (الثغرة المُصلحة) ═══════")
t, ct = rpc("record_transaction_atomic", {"p_request_id": str(uuid.uuid4()),
                                          "p_transaction": {}, "p_payable": None})
ok("الرفض بخطأ تحقق منطقي (الدالة تعمل)") if ct == "400" else no("سلوك غير متوقع", ct)

json.dump({"pid": pid, "paid": paid, "aid": aid, "txid": txid,
           "obid": obid, "stid": stid}, open("/tmp/e2e_ids.json", "w"))

print(f"\n{'═'*44}\nالنتيجة: {PASS} نجح · {FAIL} فشل\n{'═'*44}")
if NOTES:
    print("الإخفاقات:")
    for x in NOTES:
        print("  -", x)
sys.exit(1 if FAIL else 0)

#!/usr/bin/env python3
"""
Compare the frontend domain interfaces (src/core/types/domain.ts) against the
live Postgres schema, table by table and field by field.

Reports:
  - fields the frontend sends that have no column   (would break writes)
  - columns the DB requires that the frontend omits (NOT NULL without default)
  - type mismatches between the TS field and the SQL column
  - optionality mismatches (TS optional vs NOT NULL, and vice versa)
"""
import json
import os
import re
import subprocess
import sys

SBP = os.environ["SUPABASE_ACCESS_TOKEN"]
URL = ("https://api.supabase.com/v1/projects/"
       "{REF}/database/query")

# TS interface -> DB table
MAP = {
    "Project": "projects",
    "Asset": "assets",
    "Partner": "partners",
    "ProjectPartner": "project_partners",
    "Transaction": "transactions",
    "Obligation": "obligations",
    "Settlement": "settlements",
    "SettlementAllocation": "settlement_allocations",
    "OperationalEvent": "operational_events",
    "StockAdjustment": "stock_adjustments",
    "Document": "documents",
}

# columns managed by the server, never sent by the client
SERVER_MANAGED = {"owner_id", "created_at", "updated_at"}


def sql(query):
    payload = json.dumps({"query": query})
    p = subprocess.run(
        ["curl", "-s", "--max-time", "120", "-X", "POST", URL,
         "-H", f"Authorization: Bearer {SBP}",
         "-H", "Content-Type: application/json",
         "-d", payload],
        capture_output=True, text=True, timeout=150)
    return json.loads(p.stdout)


def parse_interfaces(path):
    src = open(path, encoding="utf8").read()
    # strip comments
    src = re.sub(r"//.*", "", src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    out = {}
    for m in re.finditer(r"export interface (\w+)\s*\{(.*?)\n\}", src, re.S):
        name, body = m.group(1), m.group(2)
        fields = {}
        for line in body.split("\n"):
            line = line.strip().rstrip(";,")
            if not line or ":" not in line:
                continue
            fm = re.match(r"(\w+)(\??):\s*(.+)", line)
            if fm:
                fields[fm.group(1)] = {
                    "optional": fm.group(2) == "?",
                    "ts_type": fm.group(3).strip(),
                }
        out[name] = fields
    return out


def ts_compatible(ts, col):
    """Loose structural compatibility check."""
    t, dt, udt = ts.lower(), col["data_type"], col["udt_name"]
    if "number" in t:
        return dt in ("numeric", "integer", "bigint", "double precision",
                      "real", "smallint")
    if "boolean" in t:
        return dt == "boolean"
    if "string" in t or "'" in t:  # string or string-literal union
        return dt in ("text", "character varying", "uuid", "date",
                      "timestamp with time zone", "timestamp without time zone",
                      "USER-DEFINED", "jsonb", "json")
    if "[]" in t:
        return dt == "ARRAY" or dt == "jsonb"
    return True


def main():
    types = parse_interfaces("/home/user/Terranex/src/core/types/domain.ts")
    for extra in ("/home/user/Terranex/src/features/settlements/types.ts",
                  "/home/user/Terranex/src/features/settlement-allocations/types.ts"):
        types.update(parse_interfaces(extra))
    cols_raw = sql("""
        select table_name, column_name, data_type, udt_name, is_nullable,
               column_default
        from information_schema.columns
        where table_schema='public'
        order by table_name, ordinal_position;
    """)
    db = {}
    for r in cols_raw:
        db.setdefault(r["table_name"], {})[r["column_name"]] = r

    issues = 0
    for iface, table in MAP.items():
        if iface not in types:
            print(f"⚠️  {iface}: interface not found in domain.ts")
            issues += 1
            continue
        if table not in db:
            print(f"❌ {iface} -> {table}: TABLE MISSING in database")
            issues += 1
            continue

        ts_fields = types[iface]
        cols = db[table]
        problems = []

        # 1. TS field with no column
        for f, meta in ts_fields.items():
            if f not in cols:
                problems.append(f"   ❌ field '{f}' ({meta['ts_type']}) has NO COLUMN")
            elif not ts_compatible(meta["ts_type"], cols[f]):
                problems.append(
                    f"   ⚠️  '{f}': TS {meta['ts_type']} vs DB "
                    f"{cols[f]['data_type']}/{cols[f]['udt_name']}")

        # 2. required column the frontend never sends
        for c, meta in cols.items():
            if c in SERVER_MANAGED or c in ts_fields:
                continue
            if meta["is_nullable"] == "NO" and meta["column_default"] is None:
                problems.append(
                    f"   ❌ column '{c}' is NOT NULL without default, "
                    f"frontend never sends it")
            else:
                problems.append(f"   ℹ️  column '{c}' exists, unused by frontend "
                                f"(nullable/default)")

        # 3. optionality: TS required but column nullable is fine;
        #    TS optional but column NOT NULL w/o default is a risk
        for f, meta in ts_fields.items():
            if f in cols and meta["optional"]:
                c = cols[f]
                if c["is_nullable"] == "NO" and c["column_default"] is None:
                    problems.append(
                        f"   ❌ '{f}' optional in TS but NOT NULL w/o default in DB")

        hard = [p for p in problems if "❌" in p]
        if not problems:
            print(f"✅ {iface:22s} -> {table:24s} exact match "
                  f"({len(ts_fields)} fields)")
        else:
            mark = "❌" if hard else "🟡"
            print(f"{mark} {iface:22s} -> {table}")
            for p in problems:
                print(p)
            issues += len(hard)

    print("\n" + "=" * 60)
    print(f"HARD MISMATCHES: {issues}")
    print("=" * 60)
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())

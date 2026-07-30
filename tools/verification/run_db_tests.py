#!/usr/bin/env python3
"""
Terranex DB test runner over the Supabase Management API.

The suite files are written for `psql`: each test is a `begin; ... rollback;`
block, and `\echo`/`\set` are psql meta-commands. The HTTP API wraps a whole
request in one transaction, so sending a file as-is makes the first `rollback`
discard helper objects created earlier in the same file.

This runner reproduces psql semantics: preamble first, then each
begin/rollback block as its own request, then the tail.
"""
import json
import re
import os
import subprocess
import sys
import tempfile

SBP = os.environ["SUPABASE_ACCESS_TOKEN"]
REF = os.environ.get("SUPABASE_PROJECT_REF", "your-project-ref")
URL = f"https://api.supabase.com/v1/projects/{REF}/database/query"

BLOCK = re.compile(r'^begin;\s*$(.*?)^rollback;\s*$', re.M | re.S)


def run_sql(sql: str):
    """Returns (ok, payload_or_error). Uses curl: Cloudflare rejects urllib's UA."""
    if not sql.strip():
        return True, "(empty)"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                     encoding="utf8") as f:
        json.dump({"query": sql}, f)
        payload = f.name
    try:
        proc = subprocess.run(
            ["curl", "-s", "-w", "\n%{http_code}", "--max-time", "300",
             "-X", "POST", URL,
             "-H", f"Authorization: Bearer {SBP}",
             "-H", "Content-Type: application/json",
             "--data-binary", f"@{payload}"],
            capture_output=True, text=True, timeout=320)
        out = proc.stdout.rsplit("\n", 1)
        body = out[0] if len(out) == 2 else proc.stdout
        code = out[1].strip() if len(out) == 2 else "?"
        if code in ("200", "201"):
            return True, body[:400]
        return False, f"HTTP {code}: {body[:800]}"
    finally:
        os.unlink(payload)


def split_file(path: str):
    raw = open(path, encoding="utf8").read()
    # strip psql meta-commands (\echo, \set, \timing ...)
    txt = "\n".join(l for l in raw.split("\n")
                    if not l.strip().startswith("\\"))
    parts, last, pre = [], 0, []
    for m in BLOCK.finditer(txt):
        pre.append(txt[last:m.start()])
        parts.append("begin;" + m.group(1) + "rollback;")
        last = m.end()
    return "\n".join(pre), parts, txt[last:]


def main(files):
    grand_pass = grand_fail = 0
    failures = []

    for path in files:
        name = path.split("/")[-1]
        print(f"\n{'='*66}\n### {name}\n{'='*66}")
        pre, blocks, tail = split_file(path)

        segments = []
        if pre.strip():
            segments.append(("preamble", pre))
        for i, b in enumerate(blocks, 1):
            segments.append((f"block {i}", b))
        if tail.strip():
            segments.append(("tail", tail))

        for label, sql in segments:
            ok, out = run_sql(sql)
            if ok:
                print(f"  ✅ {label}")
                grand_pass += 1
            else:
                print(f"  ❌ {label}")
                print(f"     {out}")
                grand_fail += 1
                failures.append((name, label, out))

    print(f"\n{'='*66}")
    print(f"TOTAL: {grand_pass} passed, {grand_fail} failed")
    print('='*66)
    if failures:
        print("\nFAILURES:")
        for n, l, o in failures:
            print(f"  - {n} :: {l}\n    {o[:300]}")
    return 1 if grand_fail else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""استخراج الأصول الجديدة فعليًا من فروع GitHub الأربعة + manifest موحّد.

- يقرأ البايتات عبر `git cat-file blob` (لا يكتفي بالبيانات الوصفية).
- يستبعد التكرار التام على مستوى blob SHA.
- يفصل المواد المرفوعة حديثًا (WhatsApp *) عن وسائط المستودع القديمة الموجودة في كل فرع.
- يكتب نسخ العمل في مجلد مستثنى من Git — لا يدخل RAW إلى تاريخ Git.
- لا يدمج الفروع ولا يعدّلها ولا يمس main.
"""
import collections
import hashlib
import json
import os
import subprocess

REPO = "/home/user/Terranex"
OPS = os.path.join(REPO, "التسويق-والإدارة/تسويق/مواد-وهوية/terranex-ops")
OUT = os.path.join(OPS, "archive-intake", "github-branches")
WORK = os.path.join(REPO, "media-intake-work")          # مستثنى من Git
REFS = collections.OrderedDict([
    ("patch-1", ("refs/intake/p1", "0b9002d867a4cfdb900005f14d2814d6b70b6834", 196, "main")),
    ("patch-2", ("refs/intake/p2", "626135f8904f44e774626ac05619222fb6df20c7", 197, "main")),
    ("patch-3", ("refs/intake/p3", "d08c9ca77fee51c14231ede04da55e103b1742f7", 198, "patch-1 / patch-2 (PR199)")),
    ("patch-4", ("refs/intake/p4", "d532719b343a236fc66fdde1d08553a90c7457f6", 200, "patch-2")),
])
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".bmp", ".tif", ".tiff", ".gif"}


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, check=True).stdout


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    by_blob = collections.OrderedDict()
    per_branch = {}
    for br, (ref, sha, pr, base) in REFS.items():
        head = git("rev-parse", ref).decode().strip()
        assert head == sha, (br, head, sha)
        rows = [r for r in git("ls-tree", "-r", "-l", "-z", ref).decode().split("\0") if r]
        media = 0
        for r in rows:
            meta, path = r.split("\t", 1)
            _mode, typ, blob, size = meta.split()
            ext = os.path.splitext(path)[1].lower()
            if typ != "blob" or ext not in VIDEO_EXT | IMAGE_EXT:
                continue
            media += 1
            e = by_blob.setdefault(blob, {
                "git_blob_sha": blob, "git_size": int(size), "ext": ext,
                "kind": "video" if ext in VIDEO_EXT else "image",
                "is_new_upload": os.path.basename(path).startswith("WhatsApp "),
                "occurrences": []})
            e["occurrences"].append({"branch": br, "head_sha": head, "pr": pr, "path": path})
        per_branch[br] = {"head_sha": head, "pr": pr, "base": base, "media_blobs_in_tree": media}

    new = [e for e in by_blob.values() if e["is_new_upload"]]
    old = [e for e in by_blob.values() if not e["is_new_upload"]]
    extracted = []
    for i, e in enumerate(new, start=1):
        primary = e["occurrences"][0]
        name = os.path.basename(primary["path"])
        safe = f'{i:02d}_' + name.replace("/", "_")
        dest = os.path.join(WORK, safe)
        data = git("cat-file", "blob", e["git_blob_sha"])
        assert len(data) == e["git_size"], (name, len(data), e["git_size"])
        with open(dest, "wb") as f:
            f.write(data)
        back = hashlib.sha256(open(dest, "rb").read()).hexdigest()
        e.update({"original_path": primary["path"], "file_name": name,
                  "sha256": hashlib.sha256(data).hexdigest(),
                  "sha256_of_written_copy": back,
                  "bytes": len(data), "working_copy": os.path.relpath(dest, REPO),
                  "branches": sorted({o["branch"] for o in e["occurrences"]}),
                  "all_paths": sorted({o["path"] for o in e["occurrences"]})})
        assert e["sha256"] == back
        extracted.append(e)
        print(f'{i:02d}/{len(new)} {e["kind"]:5} {len(data):>9,}B  {name}')

    total = sum(e["bytes"] for e in extracted)
    manifest = {
        "schema_version": 1,
        "intake": "GitHub branches (actual blob bytes, not metadata-only)",
        "branches": per_branch,
        "branch_policy": "لم تُدمج الفروع ولا main؛ القراءة عبر refs/intake/* فقط",
        "counts": {
            "unique_media_blobs_all": len(by_blob),
            "new_uploads_unique": len(extracted),
            "new_videos": sum(1 for e in extracted if e["kind"] == "video"),
            "new_images": sum(1 for e in extracted if e["kind"] == "image"),
            "pre_existing_repo_media_blobs": len(old),
            "exact_duplicate_occurrences_collapsed": sum(len(e["occurrences"]) - 1 for e in new),
        },
        "bytes": {"new_uploads_total": total, "new_uploads_mib": round(total / 1048576, 2)},
        "raw_storage_policy": "نسخ العمل في media-intake-work/ المستثنى من Git — لا RAW في تاريخ Git",
        "assets": extracted,
        "pre_existing_repo_media_blobs": [e["git_blob_sha"] for e in old],
    }
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("\ncounts:", json.dumps(manifest["counts"], ensure_ascii=False))
    print("bytes:", manifest["bytes"])
    print("manifest:", os.path.join(OUT, "manifest.json"))


if __name__ == "__main__":
    main()

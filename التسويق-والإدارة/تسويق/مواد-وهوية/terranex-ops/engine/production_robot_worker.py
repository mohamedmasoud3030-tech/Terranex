#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Always-on private server worker: watch raw footage folders, never publish by itself.

No HTTP socket or public upload endpoint. Place real files under:
output/production-robot/inbox/<stage>/*.mp4
"""
from __future__ import annotations
import json
import time
from pathlib import Path
import production_robot as BOT


def run_once(inbox: Path, work: Path = BOT.WORK, brief: Path | None = None) -> dict:
    inbox = BOT.confined(inbox, work)
    inbox.mkdir(parents=True, exist_ok=True)
    manifest = work / "uploads.json"
    existing = json.loads(manifest.read_text(encoding="utf-8"))["assets"] if manifest.exists() else []
    known_hashes = {a["sha256"] for a in existing}
    received, skipped, errors = [], [], []
    for role in BOT.ROLES:
        folder = inbox / role
        if folder.is_symlink():
            errors.append({"stage": role, "reason": "symlinked input directory blocked"})
            continue
        folder.mkdir(parents=True, exist_ok=True)
        folder = BOT.confined(folder, inbox)
        for item in sorted(folder.iterdir()):
            if item.is_symlink() or not item.is_file() or item.suffix.lower() not in BOT.EXTS:
                skipped.append(str(item.name))
                continue
            try:
                BOT.confined(item, inbox)
                if not 0 < item.stat().st_size <= BOT.MAX_BYTES:
                    raise BOT.Blocked("missing/oversized raw footage")
                hashed = BOT.digest(item)
                if hashed in known_hashes:
                    skipped.append(str(item.name))
                    continue
                asset = BOT.ingest(item, role, work)
                received.append({"id": asset["id"], "role": role, "file": item.name})
                known_hashes.add(hashed)
            except (OSError, BOT.Blocked) as exc:
                errors.append({"file": item.name, "reason": str(exc)})
    template = brief or (BOT.OPS / "production-robot" / "briefs" / "farm-to-delivery.json")
    request = json.loads(Path(template).read_text(encoding="utf-8"))
    storyboard = BOT.make_plan(request, BOT.assets(work=work))
    BOT.write_json(work / "plan.json", storyboard)
    summary = {"received": received, "skipped": skipped, "errors": errors,
               "ready_for_render": storyboard["ready_for_render"],
               "missing": storyboard["missing"], "review_needed": storyboard["review_needed"],
               "published": False}
    BOT.write_json(work / "worker-status.json", summary)
    return summary


def serve(inbox: Path, every_seconds: int = 30):
    if every_seconds < 5 or every_seconds > 3600:
        raise BOT.Blocked("poll interval must be 5-3600 seconds")
    while True:
        status = run_once(inbox)
        print(json.dumps(status, ensure_ascii=False), flush=True)
        time.sleep(every_seconds)

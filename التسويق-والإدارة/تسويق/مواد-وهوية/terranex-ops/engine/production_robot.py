#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Private TerraNex production bot: evidence-backed raw footage -> storyboard -> existing engine."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path

OPS = Path(__file__).resolve().parents[1]
MARKETING = OPS.parents[1]
REPO = OPS.parents[3]
ARCHIVE = MARKETING / "مواد-خام" / "أرشيف" / "2026-11" / "manifest.json"
WORK = OPS / "output" / "production-robot"
ROLES = ("farm", "weighing", "feeding", "inspection", "slaughter", "cutting", "packing", "delivery")
TAGS = {"farm": ("animals-clean", "animals-group", "farm-pen"),
        "weighing": ("weighing-activity", "weighing-context"),
        "feeding": ("feeding",), "inspection": ("animal-inspection",),
        "slaughter": ("slaughter-graphic", "slaughter-carcass"),
        "cutting": ("cutting-process",),
        "packing": ("packing-process", "packaged-meat"),
        "delivery": ("delivery-process", "delivery-vehicle", "handover")}
AR = {"farm": "في المزرعة", "weighing": "الوزن على الميزان",
      "feeding": "التغذية", "inspection": "الفحص",
      "slaughter": "الذبح", "cutting": "التقطيع",
      "packing": "التعبئة والتغليف", "delivery": "التوصيل"}
EXTS = {".mp4", ".mov", ".m4v", ".jpg", ".jpeg", ".png", ".webp"}
MAX_BYTES = 250 * 1024 * 1024


class Blocked(ValueError):
    pass


def confined(path, root):
    p, r = Path(path).resolve(), Path(root).resolve()
    if not p.is_relative_to(r):
        raise Blocked("path escapes protected media root")
    return p


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, obj):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(tmp, p)
    finally:
        tmp.unlink(missing_ok=True)


def assets(archive=ARCHIVE, work=WORK, repo=REPO):
    base = json.loads(Path(archive).read_text(encoding="utf-8"))["assets"]
    out = []
    for item in base:
        path = confined(Path(repo) / item["archive_path"], repo)
        if not path.is_file():
            raise Blocked("archived source unavailable: " + item["id"])
        out.append({"id": item["id"], "path": str(path), "sha256": item["sha256"],
                    "tags": item["category"], "kind": item["kind"], "source": "archive",
                    "duration": item["duration_sec"], "status": item["status"],
                    "faces": item.get("consent_required", False),
                    "quality": float(item.get("quality", 0)), "reviewed": False})
    index = Path(work) / "uploads.json"
    if index.exists():
        for item in json.loads(index.read_text(encoding="utf-8"))["assets"]:
            if not confined(item["path"], Path(work) / "uploads").is_file():
                raise Blocked("uploaded source unavailable: " + item["id"])
            out.append(item)
    return out


def make_plan(brief, found):
    if not isinstance(brief, dict):
        raise Blocked("brief must be JSON object")
    stages = brief.get("stages", list(ROLES))
    length = brief.get("duration_seconds", 40)
    if not isinstance(stages, list) or not stages or len(stages) > 12 or any(s not in ROLES for s in stages):
        raise Blocked("invalid production stages")
    if len(set(stages)) != len(stages):
        raise Blocked("stage repeated")
    if isinstance(length, bool) or not isinstance(length, (int, float)) or not 15 <= length <= 90:
        raise Blocked("duration must be 15-90 seconds")
    endcard = float(brief.get("endcard_seconds", 3))
    if endcard < 2 or endcard > 5 or length-endcard < len(stages):
        raise Blocked("invalid endcard duration")
    choices = brief.get("choices", {})
    if not isinstance(choices, dict) or not isinstance(brief.get("script", {}), dict):
        raise Blocked("invalid choices/script")
    allow_sensitive = brief.get("allow_sensitive_preview") is True
    allow_stills = brief.get("allow_stills") is True
    output, missing, review, elapsed = [], [], [], 0.0
    for i, stage in enumerate(stages):
        size = round((length-endcard) / len(stages), 2) if i < len(stages)-1 else round(length-endcard-elapsed, 2)
        pick = choices.get(stage, {})
        if not isinstance(pick, dict):
            raise Blocked("choice must be an object")
        wanted = pick.get("asset_id")
        matches = [a for a in found if a["id"] == wanted] if wanted else [
            a for a in found if set(a["tags"]).intersection(TAGS[stage])]
        matches.sort(key=lambda a: (a["kind"] == "video", a["quality"]), reverse=True)
        reason, chosen = "no verified filmed stage", None
        for a in matches:
            if a.get("faces") or a["status"] == "privacy-consent-review":
                reason = "face/privacy consent missing"
                continue
            if (stage == "slaughter" or a["status"] == "quarantined-not-for-ads") and not allow_sensitive:
                reason = "sensitive quarantined footage needs explicit preview review"
                continue
            if a["kind"] == "image" and not allow_stills:
                reason = "only a still photo exists, not footage of this process"
                continue
            if a["source"] == "upload" and not a["reviewed"]:
                reason = "uploaded footage awaiting human visual review"
                continue
            if wanted and not set(a["tags"]).intersection(TAGS[stage]):
                reason = "chosen media does not document this stage"
                continue
            start = float(pick.get("start", 0))
            if start < 0 or (a["kind"] == "video" and (a.get("duration") is None or
                    start+size > float(a["duration"])+0.01)):
                reason = "clip too short or window not verified"
                continue
            chosen = (a, start)
            break
        shot = {"stage": stage, "label": AR[stage], "timeline_start": round(elapsed, 2),
                "timeline_end": round(elapsed+size, 2), "seconds": size,
                "voiceover_draft": brief.get("script", {}).get(stage, "")}
        if chosen:
            a, start = chosen
            shot.update({"asset_id": a["id"], "path": a["path"],
                         "sha256": a["sha256"], "kind": a["kind"],
                         "clip_start": start, "clip_end": round(start+size, 2),
                         "window_reviewed": pick.get("window_reviewed") is True or
                                            (a["source"] == "upload" and a["reviewed"]),
                         "sensitive_preview": stage == "slaughter"})
            if not shot["window_reviewed"]:
                review.append(stage)
        else:
            shot["blocker"] = reason
            missing.append({"stage": stage, "reason": reason})
        output.append(shot)
        elapsed += size
    return {"schema_version": 1, "duration_seconds": length,
            "endcard_seconds": endcard, "shots": output, "missing": missing,
            "review_needed": review, "ready_for_render": not missing and not review,
            "voice_id": "voice-00", "publish_approved": False,
            "notices": ["real company footage only; missing stage blocks rendering",
                        "explicit sensitive preview is not permission to publish",
                        "no narration is generated; full-length verified voice-00 required"]}


def make_spec(plan, voice_meta):
    if not plan.get("ready_for_render") or plan.get("missing") or plan.get("review_needed"):
        raise Blocked("storyboard incomplete; no placeholder scenes allowed")
    clips = []
    for shot in plan["shots"]:
        f = Path(shot["path"])
        if not f.is_file() or digest(f) != shot["sha256"]:
            raise Blocked("real source file changed or disappeared")
        clips.append({"path": str(f), "start": shot["clip_start"], "end": shot["clip_end"],
                      "crop": {}, "sharpen": False, "scale_flags": "lanczos"})
    return {"title": "terranex-production-robot", "template": "corporate-no-face",
            "clips": clips, "captions": [{"from": s["timeline_start"],
                                         "to": s["timeline_end"], "text": s["label"]}
                                        for s in plan["shots"]],
            "caption_cy": 0.68, "on_screen_persons": [], "consent_persons": [],
            "endcard_sec": plan["endcard_seconds"],
            "endcard": {"headline": "TerraNex", "subtitle": "من أرض الواقع",
                        "cta": "واتساب 01010154221"},
            "voice": voice_meta, "visual_draft": True, "publish_approved": False}


def verify_narration(voice, meta, length):
    from voice_identity import require_narration
    import imageio_ffmpeg
    audio = confined(voice, MARKETING)
    if not audio.is_file():
        raise Blocked("narration missing")
    require_narration(meta, str(audio))
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    result = subprocess.run([ff, "-hide_banner", "-i", str(audio),
                             "-af", "silencedetect=noise=-38dB:d=2.0",
                             "-f", "null", "-"], capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise Blocked("voice decode failed")
    match = re.search(r"Duration:\s*(\d+):(\d+):([\d.]+)", result.stderr)
    if not match:
        raise Blocked("voice duration not measurable")
    seconds = int(match[1])*3600 + int(match[2])*60 + float(match[3])
    if seconds < length * 0.8 or seconds > length+0.4:
        raise Blocked("narration is too short/long: no long empty audio gaps")
    for match in re.finditer(r"silence_duration:\s*([\d.]+)", result.stderr):
        if float(match[1]) > 2.6:
            raise Blocked("voice has a long silent pause")
    return seconds


def render(plan, voice, meta, out):
    spec = make_spec(plan, meta)
    seconds = verify_narration(voice, meta, plan["duration_seconds"])
    out = confined(out, WORK)
    out.parent.mkdir(parents=True, exist_ok=True)
    specpath = out.with_suffix(".spec.json")
    write_json(specpath, spec)
    import reel_build
    result = reel_build.build(str(specpath), str(voice), str(out))
    qa = subprocess.run([sys.executable, str(OPS/"engine"/"qa_video.py"),
                         "--video", str(out), "--profile", "reels"],
                        capture_output=True, text=True, timeout=180)
    if qa.returncode:
        raise Blocked("rendered video failed QA: " + (qa.stdout + qa.stderr)[-500:])
    return {"status": "ready-for-review", "file": str(out), "voice_seconds": seconds,
            "published": False, **result}


def ingest(source, role, work=WORK):
    import shutil
    if role not in ROLES:
        raise Blocked("unsupported production stage")
    src = Path(source).resolve()
    if not src.is_file() or src.suffix.lower() not in EXTS or not 0 < src.stat().st_size <= MAX_BYTES:
        raise Blocked("missing/invalid/oversized source file")
    ident = "up-" + uuid.uuid4().hex[:16]
    dest = Path(work)/"uploads"/(ident+src.suffix.lower())
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    item = {"id": ident, "path": str(dest.resolve()), "sha256": digest(dest),
            "tags": [role], "kind": "image" if src.suffix.lower() in {".jpg",".jpeg",".png",".webp"} else "video",
            "source": "upload", "duration": None, "status": "pending-human-review",
            "faces": False, "quality": 0, "reviewed": False}
    reg = Path(work)/"uploads.json"
    data = json.loads(reg.read_text(encoding="utf-8")) if reg.exists() else {"assets": []}
    data["assets"].append(item)
    write_json(reg, data)
    return item


def review_upload(ident, description, duration=None, work=WORK):
    if not re.fullmatch(r"up-[0-9a-f]{16}", ident):
        raise Blocked("invalid upload id")
    if not isinstance(description, str) or not description.strip():
        raise Blocked("human visual description required")
    reg = Path(work)/"uploads.json"
    data = json.loads(reg.read_text(encoding="utf-8"))
    item = next((x for x in data["assets"] if x["id"] == ident), None)
    if item is None:
        raise Blocked("uploaded asset not found")
    if item["kind"] == "video" and (duration is None or not 0 < duration <= 3600):
        raise Blocked("verified video duration required")
    if digest(item["path"]) != item["sha256"]:
        raise Blocked("asset checksum mismatch")
    item.update({"reviewed": True, "status": "source-reviewed",
                 "description": description[:500], "duration": duration, "quality": 1.0})
    write_json(reg, data)
    return item


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan"); p.add_argument("--brief", required=True); p.add_argument("--out", required=True)
    p = sub.add_parser("ingest"); p.add_argument("--file", required=True); p.add_argument("--role", choices=ROLES, required=True)
    p = sub.add_parser("review"); p.add_argument("--id", required=True); p.add_argument("--description", required=True); p.add_argument("--duration", type=float)
    p = sub.add_parser("render"); p.add_argument("--plan", required=True); p.add_argument("--voice", required=True); p.add_argument("--metadata", required=True); p.add_argument("--out", required=True)
    p = sub.add_parser("serve"); p.add_argument("--host", default="127.0.0.1"); p.add_argument("--port", default=8765, type=int)
    args = ap.parse_args()
    try:
        if args.cmd == "plan":
            result = make_plan(json.loads(Path(args.brief).read_text(encoding="utf-8")), assets())
            write_json(args.out, result)
            print(json.dumps({"missing": result["missing"], "review_needed": result["review_needed"],
                              "ready_for_render": result["ready_for_render"]}, ensure_ascii=False))
            return 0 if result["ready_for_render"] else 2
        if args.cmd == "ingest":
            print(json.dumps(ingest(args.file, args.role), ensure_ascii=False))
        if args.cmd == "review":
            print(json.dumps(review_upload(args.id, args.description, args.duration), ensure_ascii=False))
        if args.cmd == "render":
            print(json.dumps(render(json.loads(Path(args.plan).read_text(encoding="utf-8")),
                                    Path(args.voice), json.loads(Path(args.metadata).read_text(encoding="utf-8")),
                                    Path(args.out)), ensure_ascii=False))
        if args.cmd == "serve":
            from production_robot_server import serve
            serve(args.host, args.port)
        return 0
    except (Blocked, ValueError, OSError) as exc:
        print("BLOCKED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

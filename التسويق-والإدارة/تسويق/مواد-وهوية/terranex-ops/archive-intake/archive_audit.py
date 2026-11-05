#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة جرد أرشيف الوسائط الحقيقية — تعمل على ZIP أو على مجلد.

المبادئ:
  • لا تكتب أبدًا على المصدر (ZIP أو ملفات أصلية) — نسخ عمل للقراءة فقط.
  • الملفات التالفة والمكررة تُستبعد من الفهرس المرحلي وتُسجَّل في تقرير.
  • كل ما تُخرجه يذهب إلى مجلد staging منفصل — لا يلمس scene-library الإنتاجية.
  • المقاييس آلية ومعلنة الصيغة؛ التصنيف البشري/البصري يُضاف لاحقًا في حقل منفصل.

الاستخدام:
  python archive_audit.py --zip /path/Archive.zip --out <staging>
  python archive_audit.py --dir /path/media --out <staging> [--glob '*.mp4']
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine"))
import imageio_ffmpeg  # noqa: E402

FF = imageio_ffmpeg.get_ffmpeg_exe()
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".heic"}
SCENE_THRESHOLD = 0.30
MIN_SCENE_SEC = 0.80
PREVIEW_W = 360
DHASH_BITS = 64
NEAR_DUP_HAMMING = 6


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd, timeout=600):
    return subprocess.run(cmd, capture_output=True, timeout=timeout)


# ---------------- الاستقبال ----------------
def safe_extract(zip_path, dest):
    """فك آمن: لا traversal، لا روابط رمزية، لا مسار مطلق، حدّ حجم معقول."""
    log = {"entries": [], "rejected": [], "crc_bad": None}
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        bad = z.testzip()                      # فحص CRC لكل الأعضاء
        log["crc_bad"] = bad
        infos = z.infolist()
        log["entry_count"] = len(infos)
        log["uncompressed_bytes"] = sum(i.file_size for i in infos)
        for i in infos:
            name = i.filename
            parts = name.replace("\\", "/").split("/")
            reason = None
            if name.startswith("/") or ".." in parts:
                reason = "path-traversal-or-absolute"
            elif (i.external_attr >> 16) & 0o170000 == 0o120000:
                reason = "symlink"
            elif i.file_size > 2 << 30:
                reason = "over-2GiB"
            elif name.endswith("/"):
                continue
            if reason:
                log["rejected"].append({"name": name, "reason": reason})
                continue
            target = os.path.join(dest, *parts)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(i) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)
            log["entries"].append({"name": name, "bytes": i.file_size})
    return log


def enumerate_media(root):
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for n in sorted(names):
            ext = os.path.splitext(n)[1].lower()
            if ext in VIDEO_EXT or ext in IMAGE_EXT:
                files.append(os.path.join(dirpath, n))
    return sorted(files)


# ---------------- السلامة ----------------
def probe(path):
    p = run([FF, "-hide_banner", "-i", path], timeout=120)
    err = p.stderr.decode(errors="ignore")
    d = re.search(r"Duration: (\d+):(\d+):([\d.]+)", err)
    v = re.search(r"Video: .*?, (\d{2,5})x(\d{2,5})", err)
    fps = re.search(r"([\d.]+) fps", err)
    return {
        "duration": (int(d[1]) * 3600 + int(d[2]) * 60 + float(d[3])) if d else None,
        "width": int(v[1]) if v else None,
        "height": int(v[2]) if v else None,
        "fps": float(fps[1]) if fps else None,
        "has_audio": " Audio: " in err,
        "codec": (re.search(r"Video: (\w+)", err)[1] if re.search(r"Video: (\w+)", err) else None),
    }


def decode_check(path):
    """فك ترميز كامل — أي خطأ يعني ملفًا تالفًا يُستبعد."""
    p = run([FF, "-v", "error", "-i", path, "-f", "null", "-"], timeout=900)
    err = p.stderr.decode(errors="ignore").strip()
    return {"ok": p.returncode == 0 and not err, "errors": err[:600]}


def image_check(path):
    try:
        with Image.open(path) as im:
            im.verify()
        with Image.open(path) as im:
            im.load()
            return {"ok": True, "width": im.width, "height": im.height, "mode": im.mode}
    except Exception as e:                                   # noqa: BLE001
        return {"ok": False, "errors": str(e)[:300]}


# ---------------- المشاهد ----------------
def detect_cuts(path):
    p = run([FF, "-hide_banner", "-i", path, "-vf",
             f"select='gt(scene,{SCENE_THRESHOLD})',showinfo", "-an", "-f", "null", "-"], timeout=900)
    err = p.stderr.decode(errors="ignore")
    return sorted({round(float(t), 3) for t in re.findall(r"pts_time:([\d.]+)", err)})


def scenes_from_cuts(duration, cuts):
    bounds = [0.0] + [c for c in cuts if 0.05 < c < duration - 0.05] + [duration]
    out = []
    for a, b in zip(bounds, bounds[1:]):
        if b - a >= MIN_SCENE_SEC:
            out.append((round(a, 3), round(b, 3)))
        elif out:
            out[-1] = (out[-1][0], round(b, 3))              # ادمج الشظية في السابقة
    return out


def grab_frame(path, t, width=None):
    cmd = [FF, "-v", "error", "-ss", f"{max(0.0, t):.3f}", "-i", path, "-frames:v", "1"]
    if width:
        cmd += ["-vf", f"scale={width}:-2"]
    cmd += ["-f", "image2", "-c:v", "png", "-"]
    p = run(cmd, timeout=180)
    if p.returncode != 0 or not p.stdout:
        return None
    import io
    try:
        return Image.open(io.BytesIO(p.stdout)).convert("RGB")
    except Exception:                                      # noqa: BLE001
        return None


# ---------------- المقاييس ----------------
def dhash(img):
    g = np.asarray(img.convert("L").resize((9, 8), Image.LANCZOS), dtype=np.int16)
    bits = (g[:, 1:] > g[:, :-1]).flatten()
    v = 0
    for b in bits:
        v = (v << 1) | int(b)
    return v


def hamming(a, b):
    return bin(a ^ b).count("1")


def frame_metrics(img):
    a = np.asarray(img.convert("L").resize((480, int(480 * img.height / img.width))), dtype=np.float32)
    lap = (-4 * a[1:-1, 1:-1] + a[:-2, 1:-1] + a[2:, 1:-1] + a[1:-1, :-2] + a[1:-1, 2:])
    sharp = float(lap.var())
    rgb = np.asarray(img.resize((160, int(160 * img.height / img.width))), dtype=np.float32)
    colorfulness = float(np.mean(rgb.max(axis=2) - rgb.min(axis=2)))
    return {
        "sharpness_var": round(sharp, 2),
        "luma_mean": round(float(a.mean()), 2),
        "luma_std": round(float(a.std()), 2),
        "black_clip_share": round(float((a < 8).mean()), 4),
        "white_clip_share": round(float((a > 247).mean()), 4),
        "colorfulness": round(colorfulness, 2),
    }


def crop_retention(w, h, target_ar):
    ar = w / h
    return round(min(ar, target_ar) / max(ar, target_ar), 4)


def quality_score(m, w, h, motion):
    """0..1 — صيغة معلنة: حدة 40٪، تعريض 25٪، تباين 15٪، دقة 10٪، ثبات 10٪."""
    sharp = min(1.0, m["sharpness_var"] / 220.0)
    expo = 1.0 - min(1.0, abs(m["luma_mean"] - 128) / 110.0)
    expo -= min(0.5, m["black_clip_share"] + m["white_clip_share"])
    expo = max(0.0, expo)
    contrast = min(1.0, m["luma_std"] / 60.0)
    res = min(1.0, min(w, h) / 1080.0)
    steady = 1.0 - min(1.0, motion / 45.0)
    score = 0.40 * sharp + 0.25 * expo + 0.15 * contrast + 0.10 * res + 0.10 * steady
    return round(max(0.0, min(1.0, score)), 3)


def motion_estimate(path, a, b):
    f1 = grab_frame(path, a + min(0.2, (b - a) / 4), 160)
    f2 = grab_frame(path, b - min(0.2, (b - a) / 4), 160)
    if f1 is None or f2 is None or f1.size != f2.size:
        return 0.0
    d = np.abs(np.asarray(f1, dtype=np.float32) - np.asarray(f2, dtype=np.float32))
    return round(float(d.mean()), 2)


# ---------------- Contact Sheets ----------------
def contact_sheet(items, out_path, cols=5, title=""):
    if not items:
        return None
    thumb_w, thumb_h = 216, 384
    pad, label_h, head = 10, 46, 54
    rows = (len(items) + cols - 1) // cols
    W = cols * (thumb_w + pad) + pad
    H = head + rows * (thumb_h + label_h + pad) + pad
    sheet = Image.new("RGB", (W, H), (18, 26, 20))
    d = ImageDraw.Draw(sheet)
    d.text((pad + 4, 16), title[:110], fill=(230, 215, 160))
    for i, it in enumerate(items):
        r, c = divmod(i, cols)
        x = pad + c * (thumb_w + pad)
        y = head + r * (thumb_h + label_h + pad)
        try:
            im = Image.open(it["preview"]).convert("RGB")
            im.thumbnail((thumb_w, thumb_h), Image.LANCZOS)
            sheet.paste(im, (x + (thumb_w - im.width) // 2, y + (thumb_h - im.height) // 2))
        except Exception:                                  # noqa: BLE001
            d.rectangle([x, y, x + thumb_w, y + thumb_h], outline=(180, 60, 60))
        d.text((x + 2, y + thumb_h + 4), it["label"][:34], fill=(235, 235, 235))
        d.text((x + 2, y + thumb_h + 22), it["sub"][:34], fill=(150, 200, 160))
    sheet.save(out_path, quality=86)
    return out_path


# ---------------- البرنامج ----------------
def main():
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--zip")
    src.add_argument("--dir")
    src.add_argument("--files", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", default="intake")
    ap.add_argument("--skip-decode", action="store_true")
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    previews = os.path.join(out, "previews")
    sheets = os.path.join(out, "contact-sheets")
    reports = os.path.join(out, "reports")
    for p in (previews, sheets, reports):
        os.makedirs(p, exist_ok=True)

    started = datetime.now(timezone.utc).isoformat()
    intake = {"label": args.label, "started_at": started, "source_modified": False}
    if args.zip:
        zp = os.path.abspath(args.zip)
        intake["source"] = {"kind": "zip", "path": zp, "bytes": os.path.getsize(zp),
                            "sha256": sha256_file(zp)}
        work = os.path.join(out, "working")
        intake["zip"] = safe_extract(zp, work)
        media_root = work
    elif args.dir:
        media_root = os.path.abspath(args.dir)
        intake["source"] = {"kind": "dir", "path": media_root}
        intake["working_copies"] = "none — read-only analysis of files already in the workspace"
    else:
        media_root = os.path.commonpath([os.path.abspath(x) for x in args.files])
        intake["source"] = {"kind": "files", "paths": [os.path.abspath(x) for x in args.files]}
        intake["working_copies"] = "none — read-only analysis of files already in the workspace"

    files = ([os.path.abspath(x) for x in args.files] if args.files else enumerate_media(media_root))
    intake["media_files_found"] = len(files)

    seen_hash, assets, rejected, duplicates = {}, [], [], []
    for path in files:
        ext = os.path.splitext(path)[1].lower()
        rel = os.path.relpath(path, media_root)
        digest = sha256_file(path)
        rec = {"file": rel, "abs_path": path, "ext": ext, "bytes": os.path.getsize(path),
               "sha256": digest, "kind": "video" if ext in VIDEO_EXT else "image"}
        if digest in seen_hash:
            duplicates.append({"file": rel, "duplicate_of": seen_hash[digest], "reason": "identical-sha256"})
            continue
        seen_hash[digest] = rel
        chk = decode_check(path) if (rec["kind"] == "video" and not args.skip_decode) else (
            image_check(path) if rec["kind"] == "image" else {"ok": True})
        rec["integrity"] = chk
        if not chk.get("ok"):
            rejected.append({"file": rel, "reason": "corrupt-or-undecodable", "detail": chk.get("errors", "")})
            continue
        rec["probe"] = probe(path) if rec["kind"] == "video" else {
            "width": chk.get("width"), "height": chk.get("height"), "duration": None}
        assets.append(rec)

    scenes, frames_for_dedup = [], []
    for ai, a in enumerate(assets, start=1):
        sid = f"{args.label}-a{ai:02d}"
        a["asset_id"] = sid
        w, h = a["probe"].get("width") or 0, a["probe"].get("height") or 0
        if a["kind"] == "video":
            dur = a["probe"].get("duration") or 0.0
            cuts = detect_cuts(a["abs_path"])
            spans = scenes_from_cuts(dur, cuts)
            a["cuts_detected"] = len(cuts)
            a["scenes"] = len(spans)
        else:
            spans = [(0.0, 0.0)]
            a["scenes"] = 1
        for k, (s, e) in enumerate(spans, start=1):
            mid = s + (e - s) / 2 if e > s else 0.0
            img = grab_frame(a["abs_path"], mid, PREVIEW_W)
            if img is None:
                rejected.append({"file": a["file"], "scene": k, "reason": "frame-extraction-failed"})
                continue
            scene_id = f"{sid}-s{k:02d}"
            pv = os.path.join(previews, scene_id + ".jpg")
            img.save(pv, quality=88)
            m = frame_metrics(img)
            motion = motion_estimate(a["abs_path"], s, e) if e > s else 0.0
            ph = dhash(img)
            sc = {
                "scene_id": scene_id, "asset_id": sid, "source_file": a["file"],
                "source_sha256": a["sha256"], "kind": a["kind"],
                "start": s, "end": e, "duration": round(e - s, 3),
                "width": w, "height": h, "fps": a["probe"].get("fps"),
                "preview": os.path.relpath(pv, out), "dhash": f"{ph:016x}",
                "metrics": m, "motion": motion,
                "quality_score": quality_score(m, w, h, motion),
                "fit_vertical_9_16": crop_retention(w, h, 9 / 16) if w and h else None,
                "fit_horizontal_16_9": crop_retention(w, h, 16 / 9) if w and h else None,
                "visual_review": {"done": False, "category": None, "animals": None,
                                  "persons_visible": None, "burned_text_or_watermark": None,
                                  "private_data": None, "consent_needed": None, "notes": None},
                "staging": True, "usable": False,
                "merge_into_scene_library": False,
            }
            scenes.append(sc)
            frames_for_dedup.append((scene_id, ph))

    near = []
    for i in range(len(frames_for_dedup)):
        for j in range(i + 1, len(frames_for_dedup)):
            a_id, a_h = frames_for_dedup[i]
            b_id, b_h = frames_for_dedup[j]
            dist = hamming(a_h, b_h)
            if dist <= NEAR_DUP_HAMMING:
                near.append({"a": a_id, "b": b_id, "hamming": dist})
    dup_ids = {n["b"] for n in near}
    for sc in scenes:
        if sc["scene_id"] in dup_ids:
            sc["near_duplicate_flag"] = True
            sc["usable"] = False

    by_asset = {}
    for sc in scenes:
        by_asset.setdefault(sc["asset_id"], []).append(sc)
    sheet_paths = []
    for a in assets:
        items = [{"preview": os.path.join(out, s["preview"]),
                  "label": f'{s["scene_id"]}  {s["start"]:.1f}-{s["end"]:.1f}s',
                  "sub": f'Q={s["quality_score"]:.2f} sharp={s["metrics"]["sharpness_var"]:.0f}'}
                 for s in by_asset.get(a["asset_id"], [])]
        p = contact_sheet(items, os.path.join(sheets, a["asset_id"] + ".jpg"),
                          title=f'{a["asset_id"]} :: {os.path.basename(a["file"])[:70]}')
        if p:
            sheet_paths.append(os.path.relpath(p, out))
            a["contact_sheet"] = os.path.relpath(p, out)

    top = sorted(scenes, key=lambda s: s["quality_score"], reverse=True)[:20]
    summary = {
        "label": args.label, "started_at": started,
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "intake": intake,
        "counts": {"media_files_found": len(files), "unique_assets": len(assets),
                   "exact_duplicates": len(duplicates), "rejected": len(rejected),
                   "scenes_extracted": len(scenes), "near_duplicate_pairs": len(near),
                   "scenes_flagged_near_duplicate": len(dup_ids)},
        "assets": [{k: v for k, v in a.items() if k != "abs_path"} for a in assets],
        "duplicates": duplicates, "rejected": rejected, "near_duplicates": near,
        "contact_sheets": sheet_paths,
        "top20_by_technical_quality": [
            {k: s[k] for k in ("scene_id", "source_file", "start", "end", "quality_score",
                               "fit_vertical_9_16", "fit_horizontal_16_9", "preview")} for s in top],
        "scenes": scenes,
        "merge_policy": "staging only — لا دمج في scene-library قبل مراجعة المالك",
    }
    with open(os.path.join(reports, "audit.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(json.dumps(summary["counts"], ensure_ascii=False, indent=1))
    print("sheets:", sheet_paths)
    print("report:", os.path.join(reports, "audit.json"))


if __name__ == "__main__":
    main()

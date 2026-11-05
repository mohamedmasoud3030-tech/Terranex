#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""مكتبة المشاهد الذكية — Smart Scene Library (TerraNex terranex-ops).

خط الأنابيب: استيعاب (ingest) ← تحليل/كشف حدود (analyze) ← وسم بصري (tag)
← فهرسة (index.json) ← بحث عربي/إنجليزي (search) ← storyboard من معرفات المشاهد.

مبادئ ملزمة:
- الأصل لا يُعدّل: فيديوهات 01/04 متتبعة في git تُشار إليها في مكانها؛ الملفات الجديدة
  تُنسخ إلى scene-library/assets/ (خارج git) مع توثيق الاستعادة.
- إزالة التكرار بـ SHA-256. لا تُرفع فيديوهات خام كبيرة إلى git تلقائيًا.
- الأوصاف/الوسوم يكتبها وكيل Arena بعد معاينة فعلية (لا واجهة visión آلية غير مثبتة).
- حدود المشاهد من FFmpeg (select=gt(scene,X))؛ واللقطات المتصلة تُقسّم يدويًا من المعاينة.
- الـ storyboard يقرأ التوقيتات من الفهرس عبر scene_id — لا توقيتات مكتوبة يدويًا في كود الإنتاج.

لا شبكة ولا GPU ولا واجهات مدفوعة. ffmpeg عبر imageio_ffmpeg فقط.
"""
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import unicodedata

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

ENGINE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ENGINE)                       # terranex-ops
LIB = os.path.join(ROOT, "scene-library")
INDEX = os.path.join(LIB, "index.json")
PREVIEWS = os.path.join(LIB, "previews")
ASSETS = os.path.join(LIB, "assets")
FF = imageio_ffmpeg.get_ffmpeg_exe()


def repo_root() -> str:
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
                           capture_output=True, text=True, check=True)
        return r.stdout.strip()
    except Exception:
        return os.path.abspath(os.path.join(ROOT, "..", "..", "..", ".."))


REPO = repo_root()

# ── قاموس الوسوم: عربي/إنجليزي → وسم قانوني واحد ─────────────────────────────
# الفئات المطلوبة: animal / scale / feeding / farm / person / burned-text / unusable
ALIASES = {
    "animal": "animal", "حيوان": "animal", "حيوانات": "animal", "بهائم": "animal",
    "sheep": "sheep", "خروف": "sheep", "خراف": "sheep", "غنم": "sheep", "ضأن": "sheep",
    "ضاني": "sheep", "lamb": "sheep", "ram": "sheep",
    "cows": "cows", "cow": "cows", "cattle": "cows", "بقر": "cows", "بقرة": "cows", "أبقار": "cows",
    "scale": "scale", "ميزان": "scale", "الميزان": "scale", "وزن": "scale", "الوزن": "scale",
    "weigh": "scale", "weighing": "scale", "weight": "scale", "وزنه": "scale",
    "feeding": "feeding", "تغذية": "feeding", "أكل": "feeding", "علف": "feeding", "feed": "feeding",
    "farm": "farm", "مزرعة": "farm", "مزرعه": "farm", "حقل": "farm", "زراعة": "farm", "زرع": "farm",
    "field": "farm", "أرض": "farm",
    "irrigation": "irrigation", "ري": "irrigation", "رش": "irrigation", "رشاشات": "irrigation",
    "sprinkler": "irrigation", "sprinklers": "irrigation",
    "person": "person", "شخص": "person", "وجه": "person", "وجوه": "person", "face": "person",
    "hand": "person-hand", "يد": "person-hand", "أيدي": "person-hand",
    "burned-text": "burned-text", "نص": "burned-text", "نص-محروق": "burned-text",
    "كابشن": "burned-text", "burned": "burned-text", "watermark": "burned-text",
    "unusable": "unusable", "غير-صالحة": "unusable", "مرفوض": "unusable",
    "endcard": "endcard", "ختام": "endcard", "شعار": "endcard",
}
STOP = {"على", "في", "من", "إلى", "عن", "مع", "هذا", "هذه", "ذلك", "تلك", "ال", "و", "أو",
        "أفضل", "افضل", "لقطة", "لقطه", "مشهد", "the", "a", "an", "of", "on", "in", "for",
        "best", "shot", "scene", "clip"}
# «الخروف/للخروف» ليست وقفًا — تُجذَر إلى sheep عبر إزالة أل التعريف/الجر أدناه.


def _norm(tok: str) -> str:
    tok = unicodedata.normalize("NFKC", tok)
    tok = re.sub(r"[\u064B-\u0652\u0670]", "", tok)          # تشكيل
    tok = tok.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    tok = tok.replace("ى", "ي").replace("ة", "ه")
    return tok.strip().lower()


def tokenize(query: str):
    """تحويل استعلام عربي/إنجليزي إلى مجموعة وسوم قانونية.

    الخطوات: مطابقة مباشرة (مع إزالة أل التعريف) ← تجريد سوابق الجر/العطف (و ف ل ب ك)
    ثم إعادة المحاولة ← احتياط تطابق جزئي بحارس طول. «وزن» يُطابق مباشرة قبل أي تجريد.
    """
    raw = re.split(r"[\s,،.؟?!:/\\\-]+", query)
    tags = set()
    for w in raw:
        if not w:
            continue
        n = _norm(w)
        if n in STOP:
            continue
        direct = [n]
        if n.startswith("ال") and len(n) > 3:
            direct.append(n[2:])
        hit = next((ALIASES[c] for c in direct if c in ALIASES), None)
        if hit:
            tags.add(hit)
            continue
        t, stripped = n, []
        while t and t[0] in "وفلبك" and len(t) > 3:
            t = t[1:]
            stripped.append(t)
            if t.startswith("ال") and len(t) > 3:
                stripped.append(t[2:])
        hit = next((ALIASES[c] for c in stripped if c in ALIASES), None)
        if hit:
            tags.add(hit)
            continue
        for c in [n] + stripped:
            if len(c) < 3:
                continue
            done = False
            for key, val in ALIASES.items():
                k = _norm(key)
                if len(k) >= 3 and (c in k or k in c):
                    tags.add(val)
                    done = True
                    break
            if done:
                break
    return tags


# ── فهرس ────────────────────────────────────────────────────────────────────
def load_index() -> dict:
    if os.path.isfile(INDEX):
        with open(INDEX, encoding="utf-8") as f:
            return json.load(f)
    return {"version": 1, "sources": {}, "scenes": []}


def save_index(idx: dict) -> None:
    os.makedirs(LIB, exist_ok=True)
    with open(INDEX, "w", encoding="utf-8") as f:
        json.dump(idx, f, ensure_ascii=False, indent=2)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def probe(path: str) -> dict:
    r = subprocess.run([FF, "-i", path], capture_output=True, text=True)
    e = r.stderr
    dur = re.search(r"Duration:\s*(\d+):(\d+):([\d.]+)", e)
    d = int(dur[1]) * 3600 + int(dur[2]) * 60 + float(dur[3]) if dur else None
    vid = re.search(r"Video:.*?(\d{2,5})x(\d{2,5})", e)
    fps = re.search(r"([\d.]+)\s*fps", e)
    return {"duration": d, "width": int(vid[1]) if vid else None,
            "height": int(vid[2]) if vid else None, "fps": float(fps[1]) if fps else None}


def git_tracked(path: str) -> bool:
    r = subprocess.run(["git", "ls-files", "--error-unmatch", path], cwd=REPO,
                       capture_output=True, text=True)
    return r.returncode == 0


def _font(size=18):
    for cand in ("Tajawal-Bold.ttf", "Cairo-Bold.ttf"):
        p = os.path.join(ROOT, "assets", "fonts", cand)
        if os.path.isfile(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


# ── 1) الاستيعاب ─────────────────────────────────────────────────────────────
def ingest(paths, kind="video") -> list:
    idx = load_index()
    added = []
    os.makedirs(ASSETS, exist_ok=True)
    for p in paths:
        p = os.path.abspath(p)
        if not os.path.isfile(p):
            raise SystemExit(f"input not found: {p}")
        digest = sha256(p)
        dup = [sid for sid, s in idx["sources"].items() if s["sha256"] == digest]
        if dup:
            print(f"⏭️  مكرر (SHA-256 مطابق) → {dup[0]}: {os.path.basename(p)}")
            continue
        m = re.match(r"(\d+)", os.path.basename(p))
        sid = f"src-{int(m.group(1)):02d}" if m else f"src-{len(idx['sources']) + 1:02d}"
        if sid in idx["sources"]:
            base, k = sid, 2
            while sid in idx["sources"]:
                sid = f"{base}-{k}"; k += 1
        info = probe(p) if kind == "video" else {"duration": None, "width": None, "height": None, "fps": None}
        if kind == "image":
            with Image.open(p) as im:
                info["width"], info["height"] = im.size
        tracked = git_tracked(p)
        if tracked:
            rel = os.path.relpath(p, REPO)
            stored, restore = rel, f"git checkout -- '{rel}'  (متتبع في git — يُستعاد تلقائيًا)"
        else:
            dest = os.path.join(ASSETS, os.path.basename(p))
            if os.path.abspath(dest) != p:
                with open(p, "rb") as src, open(dest, "wb") as out:
                    out.write(src.read())
            stored = os.path.relpath(dest, REPO)
            restore = ("غير متتبع في git — الأصل في scene-library/assets/ (خارج git). "
                       "أعد رفع الملف الأصلي في جلسة جديدة ثم أعد ingest.")
        idx["sources"][sid] = {
            "source_id": sid, "kind": kind, "sha256": digest,
            "path": stored, "git_tracked": tracked, "restore": restore,
            **info,
        }
        added.append(sid)
        print(f"✅ استيعاب {sid}: {os.path.basename(p)} | {info['width']}x{info['height']} "
              f"| {info['duration']}s | tracked={tracked}")
    save_index(idx)
    return added


# ── 2) التحليل/kشف الحدود ────────────────────────────────────────────────────
def detect_cuts(path: str, thr: float = 0.25) -> list:
    r = subprocess.run([FF, "-i", path, "-vf", f"select='gt(scene,{thr})',showinfo",
                        "-f", "null", "-"], capture_output=True, text=True)
    return [float(m) for m in re.findall(r"pts_time:([\d.]+)", r.stderr)]


def _frame(path, t, w=200, h=356):
    o = os.path.join(PREVIEWS, f"_tmp_{t:.2f}.jpg")
    subprocess.run([FF, "-y", "-v", "error", "-ss", str(t), "-i", path,
                    "-frames:v", "1", "-vf", f"scale={w}:{h}", o], check=True)
    im = Image.open(o).convert("RGB")
    os.remove(o)
    return im


def contact_sheet(src: dict, times, cols=6, out=None):
    os.makedirs(PREVIEWS, exist_ok=True)
    path = os.path.join(REPO, src["path"])
    tw, th, lab = 200, 356, 26
    rows = math.ceil(len(times) / cols)
    canvas = Image.new("RGB", (cols * tw, rows * (th + lab)), (15, 23, 42))
    d = ImageDraw.Draw(canvas)
    f = _font(18)
    for i, t in enumerate(times):
        r, c = divmod(i, cols)
        x, y = c * tw, r * (th + lab)
        canvas.paste(_frame(path, t), (x, y))
        d.rectangle([x, y + th, x + tw, y + th + lab], fill=(15, 23, 42))
        d.text((x + 6, y + th + 3), f"{t:5.2f}s", font=f, fill=(250, 204, 21))
    out = out or os.path.join(PREVIEWS, f"contact_{src['source_id']}.jpg")
    canvas.save(out, quality=88)
    return out


def scene_preview(src: dict, scene_id: str, t: float):
    os.makedirs(PREVIEWS, exist_ok=True)
    path = os.path.join(REPO, src["path"])
    out = os.path.join(PREVIEWS, f"{scene_id}.jpg")
    subprocess.run([FF, "-y", "-v", "error", "-ss", str(t), "-i", path,
                    "-frames:v", "1", "-vf", "scale=360:640", out], check=True)
    return out


def analyze(source_id: str, thr: float = 0.25) -> list:
    idx = load_index()
    src = idx["sources"][source_id]
    path = os.path.join(REPO, src["path"])
    dur = src["duration"] or 0.0
    cuts = detect_cuts(path, thr)
    bounds = [0.0] + cuts + [dur]
    # إزالة أي مشاهد سابقة لهذا المصدر ثم إعادة البناء من الكشف
    idx["scenes"] = [s for s in idx["scenes"] if s["source_id"] != source_id]
    made = []
    for i in range(len(bounds) - 1):
        a, b = bounds[i], bounds[i + 1]
        if b - a < 0.2:
            continue
        scene_id = f"{source_id.replace('src-', 's')}-{i + 1:02d}"
        mid = (a + b) / 2
        prev = scene_preview(src, scene_id, mid)
        idx["scenes"].append({
            "scene_id": scene_id, "source_id": source_id, "start": round(a, 3), "end": round(b, 3),
            "tags": [], "description": "", "quality": 0.5, "usable": True,
            "burned_text": False, "tagged_by": "pending",
            "preview": os.path.relpath(prev, REPO), "treatment": {},
        })
        made.append(scene_id)
    times = [round(i * 1.0 + 0.5, 2) for i in range(int(dur))]
    contact_sheet(src, times)
    save_index(idx)
    print(f"🔎 {source_id}: {len(cuts)} قطع → {len(made)} مشهد مبدئي + ورقة معاينة")
    return made


# ── 3) الوسم البصري (يكتبه الوكيل بعد المعاينة) ───────────────────────────────
def apply_tags(tags_file: str) -> int:
    """يدمج وسوم/أوصاف/جودة مكتوبة من معاينة الوكيل. يسمح بتقسيم لقطات متصلة.

    صيغة الملف: {"scenes":[{scene_id, source_id, start, end, tags, description,
                          quality, usable, burned_text, treatment}, ...]}
    """
    idx = load_index()
    with open(tags_file, encoding="utf-8") as f:
        data = json.load(f)
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    count = 0
    for sc in data["scenes"]:
        sid = sc["scene_id"]
        src = idx["sources"][sc["source_id"]]
        mid = (sc["start"] + sc["end"]) / 2
        prev = scene_preview(src, sid, mid)
        rec = {
            "scene_id": sid, "source_id": sc["source_id"],
            "start": round(sc["start"], 3), "end": round(sc["end"], 3),
            "tags": sc["tags"], "description": sc["description"],
            "quality": float(sc.get("quality", 0.5)), "usable": bool(sc.get("usable", True)),
            "burned_text": bool(sc.get("burned_text", False)),
            "tagged_by": "arena-vision", "preview": os.path.relpath(prev, REPO),
            "treatment": sc.get("treatment", {}),
        }
        by_id[sid] = rec
        count += 1
    idx["scenes"] = sorted(by_id.values(), key=lambda s: (s["source_id"], s["start"]))
    save_index(idx)
    print(f"🏷️  وُسم {count} مشهدًا (arena-vision)")
    return count


# ── 4) البحث ────────────────────────────────────────────────────────────────
def search(query: str, k: int = 5, include_unusable: bool = False) -> list:
    idx = load_index()
    qtags = tokenize(query)
    src_by_id = idx["sources"]
    results = []
    for s in idx["scenes"]:
        if not include_unusable and not s["usable"]:
            continue
        stags = set(s["tags"])
        matched = qtags & stags
        if not matched:
            continue
        coverage = len(matched) / max(1, len(qtags))
        score = coverage * 10 + s["quality"] * 2 + (1.0 if s["usable"] else -5.0)
        src = src_by_id[s["source_id"]]
        results.append({
            "scene_id": s["scene_id"], "score": round(score, 2),
            "matched_tags": sorted(matched), "source_path": src["path"],
            "start": s["start"], "end": s["end"], "quality": s["quality"],
            "description": s["description"], "preview": s["preview"],
        })
    results.sort(key=lambda r: r["score"], reverse=True)
    return results[:k]


# ── 5) storyboard من معرفات المشاهد (التوقيتات من الفهرس لا من الكود) ─────────
def storyboard(scene_ids, out_spec: str, hook: str = "", hook_sec: float = 0.0,
               captions=None, endcard_sec: float = 3.0, title: str = "library-storyboard") -> dict:
    """يبني spec متوافقًا مع reel_build حيث كل توقيت مصدره الفهرس عبر scene_id."""
    idx = load_index()
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    clips = []
    cursor = hook_sec
    windows = []                                   # نوافذ كابشن مشتقة من الفهرس
    for sid in scene_ids:
        if sid not in by_id:
            raise SystemExit(f"scene_id غير موجود في الفهرس: {sid}")
        s = by_id[sid]
        if not s["usable"]:
            raise SystemExit(f"مشهد غير صالح للاستخدام: {sid}")
        src = idx["sources"][s["source_id"]]
        dur = round(s["end"] - s["start"], 3)
        # مسار مطلق حقيقي من الفهرس (لا مسار مختلق) — يقبله reel_build دون تعديل
        clip = {"path": os.path.join(REPO, src["path"]), "start": s["start"], "end": s["end"],
                "scene_id": sid}
        clip.update(s.get("treatment", {}))      # crop/proof_bar من وسوم المشهد
        clips.append(clip)
        windows.append((round(cursor, 3), round(cursor + dur, 3)))
        cursor += dur
    # كابشن: إما نوافذ صريحة، أو نصوص تُولّد نوافذها من مدد المشاهد (لا توقيت يدوي)
    if captions and all(isinstance(c, str) for c in captions):
        captions = [{"from": a, "to": b, "text": t}
                    for (a, b), t in zip(windows, captions)]
    spec = {
        "title": title, "on_screen_persons": [], "consent_persons": [],
        "clips": clips, "hook": hook, "hook_sec": hook_sec,
        "captions": captions or [], "endcard_sec": endcard_sec,
        "_library_derived": True, "_scene_ids": list(scene_ids),
    }
    os.makedirs(os.path.dirname(os.path.abspath(out_spec)), exist_ok=True)
    with open(out_spec, "w", encoding="utf-8") as f:
        json.dump(spec, f, ensure_ascii=False, indent=2)
    print(f"🎬 storyboard: {len(clips)} لقطة من الفهرس → {out_spec} (المدة {cursor:.2f}s + ختام)")
    return spec


# ── CLI ─────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="مكتبة المشاهد الذكية")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("ingest"); p.add_argument("paths", nargs="+"); p.add_argument("--kind", default="video")
    p = sub.add_parser("analyze"); p.add_argument("source_id"); p.add_argument("--thr", type=float, default=0.25)
    p = sub.add_parser("tag"); p.add_argument("tags_file")
    p = sub.add_parser("search"); p.add_argument("query"); p.add_argument("-k", type=int, default=5); p.add_argument("--all", action="store_true")
    p = sub.add_parser("storyboard"); p.add_argument("--scenes", required=True); p.add_argument("--out", required=True)
    p.add_argument("--hook", default=""); p.add_argument("--hook-sec", type=float, default=0.0); p.add_argument("--endcard-sec", type=float, default=3.0)
    p.add_argument("--captions", help="ملف JSON بقائمة نصوص كابشن (تُولّد نوافذها من مدد المشاهد)")
    p.add_argument("--title", default="library-storyboard")
    sub.add_parser("list")
    a = ap.parse_args()
    if a.cmd == "ingest":
        ingest(a.paths, a.kind)
    elif a.cmd == "analyze":
        analyze(a.source_id, a.thr)
    elif a.cmd == "tag":
        apply_tags(a.tags_file)
    elif a.cmd == "search":
        res = search(a.query, a.k, a.all)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif a.cmd == "storyboard":
        caps = None
        if a.captions:
            with open(a.captions, encoding="utf-8") as f:
                caps = json.load(f)
        storyboard(a.scenes.split(","), a.out, a.hook, a.hook_sec,
                   captions=caps, endcard_sec=a.endcard_sec, title=a.title)
    elif a.cmd == "list":
        idx = load_index()
        for sid, s in idx["sources"].items():
            print(f"{sid}: {s['path']} ({s['width']}x{s['height']}, {s['duration']}s)")
        for s in idx["scenes"]:
            print(f"  {s['scene_id']} [{s['start']}-{s['end']}] q={s['quality']} "
                  f"usable={s['usable']} tags={','.join(s['tags'])}")


if __name__ == "__main__":
    main()

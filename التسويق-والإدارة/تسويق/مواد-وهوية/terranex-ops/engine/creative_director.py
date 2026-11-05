#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Creative Director v1 — Arabic brief / Arena-authored JSON → validated ad plan.

Two authoring paths:
1. template: limited Egyptian Arabic brief → deterministic beat template;
2. creative JSON: Arena agent writes hook/shots/voice/endcard, engine validates
   scene IDs, indexed timings, identity and compliance before rendering.

No internal Arena model API is assumed or called. The agent authors JSON outside
this module; this module is the deterministic production gate.

Voice: no TTS is generated here. An approved asset plus a human-reviewed
transcript manifest are required before captions can be bound to measured
speech energy. Energy alone never proves spoken-text equality.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ENGINE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ENGINE)
sys.path.insert(0, ENGINE)
import brand as B            # noqa: E402
import critic                # noqa: E402
import qa_video              # noqa: E402
import reel_build as R       # noqa: E402
import scene_library as SL   # noqa: E402
from safe_paths import confine  # noqa: E402
from creative_store import (  # noqa: E402
    ProjectStore, BRIEF, PLAN, SPEC, MEMORY, CAPTION, STORYBOARD,
    RENDER_REPORT, CRITIC_REPORT, RELOCATION_REPORT, CREATIVE_INPUT,
    REVISION_INPUT, VOICE_TRANSCRIPT, VOICE_ASSET_NAMES,
)

REPO = SL.REPO
MARKETING_ROOT = R.MARKETING_ROOT
PROJECTS = os.path.join(ROOT, "output", "creative-projects")
INDEX_PATH = SL.INDEX
PERSONAS = os.path.join(ROOT, "context", "personas.json")
TOL = 0.05
SUPPORTED_TOPICS = ("field-followup", "feeding", "weight")
SILENT_DISCLOSURE = "مسودة بصرية للمراجعة · بدون تعليق صوتي"
VOICE_DISCLOSURE = "تعليق صوتي معتمد"
AI_VOICE_DISCLOSURE = "تعليق صوتي · مدعوم بإضافات AI"

BEATS = {
    "field-followup": [
        {"role": "establish", "tags": {"sheep"}, "weight": 1.0, "short_bonus": True,
         "text": "رأس حقيقي… مش مجرد صورة.",
         "motion": "لقطة قريبة ثابتة؛ دخول هادئ للنص فقط."},
        {"role": "followup", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "بنتابع الحيوانات على أرض الواقع.",
         "motion": "لقطة متابعة عن قرب؛ شريط إثبات يغطي العلامة المحروقة."},
        {"role": "herd", "tags": {"cows"}, "weight": 1.2, "short_bonus": True,
         "text": "من الحظيرة…", "motion": "لقطة واسعة للقطيع؛ انتقال قطع بسيط."},
        {"role": "feeding", "tags": {"feeding"}, "weight": 1.5,
         "text": "للتغذية…", "motion": "لقطة تغذية أقرب؛ إبقاء الحيوان داخل الكادر."},
        {"role": "farm", "tags": {"irrigation"}, "weight": 1.2,
         "text": "وللمزرعة.", "motion": "لقطة ري/محصول كسياق للمزرعة؛ لا ادعاء بفحص بيطري."},
        {"role": "followup-close", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "متابعة وتوثيق… خطوة بخطوة.",
         "motion": "زاوية متابعة أخرى؛ لا تكرار نفس اللقطة."},
    ],
    "feeding": [
        {"role": "establish", "tags": {"cows"}, "weight": 1.5, "short_bonus": True,
         "text": "التغذية… من قلب المزرعة.", "motion": "لقطة حظيرة واسعة."},
        {"role": "feeding", "tags": {"feeding"}, "weight": 3.0,
         "text": "علف ورعاية… خطوة بخطوة.", "motion": "لقطة تغذية قريبة."},
        {"role": "farm", "tags": {"irrigation"}, "weight": 1.5,
         "text": "ومحصول بيتغذى.", "motion": "لقطة ري."},
        {"role": "followup", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "ومتابعة على أرض الواقع.", "motion": "لقطة متابعة عن قرب."},
    ],
    "weight": [
        {"role": "establish", "tags": {"sheep"}, "weight": 1.0, "short_bonus": True,
         "text": "رأس حقيقي… مش مجرد صورة.", "motion": "لقطة خروف قريبة."},
        {"role": "followup", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "الوزن الحقلي… زي ما هو.",
         "motion": "لقطة الوزن الحقلي؛ لا ادعاء بميزان واضح إن لم يظهر."},
        {"role": "feeding", "tags": {"feeding"}, "weight": 1.5,
         "text": "وتغذية… قبل وبعدها.", "motion": "لقطة تغذية."},
        {"role": "followup-close", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "متابعة وتوثيق… خطوة بخطوة.", "motion": "زاوية وزن أخرى."},
    ],
}


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _rel(path) -> str:
    return os.path.relpath(os.path.abspath(path), REPO).replace(os.sep, "/")


def _sha256(path, root: str) -> str:
    safe = confine(str(path), root)
    h = hashlib.sha256()
    with open(safe, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _norm_text(s: str) -> str:
    s = SL._norm(s or "")
    return re.sub(r"[^\w\u0600-\u06FF]+", "", s)


_AR_DIGITS = str.maketrans({chr(0x0660 + i): str(i) for i in range(10)})
_AR_DIGITS.update({chr(0x06F0 + i): str(i) for i in range(10)})
_WORD_NUM = {"عشرة": 10, "عشر": 10, "خمستاشر": 15, "خمسة عشر": 15, "عشرين": 20,
             "ثلاثين": 30, "تلاتين": 30, "اربعة": 4, "أربعة": 4, "خمسة": 5}
_DUR_UNITS = ("ثانيةً", "ثانية", "ثانيه", "ثواني", "ث", "seconds", "second", "sec")


def _latin_digits(s: str) -> str:
    return s.translate(_AR_DIGITS)


def _number_before(n: str, i: int) -> float | None:
    j = i - 1
    while j >= 0 and n[j].isspace():
        j -= 1
    end = j + 1
    while j >= 0 and (n[j].isdigit() or n[j] in ".,"):
        j -= 1
    token = n[j + 1:end].replace(",", ".")
    if not token:
        return None
    try:
        return float(token)
    except ValueError:
        return None


def _unit_instances(n: str, unit: str):
    start = 0
    while True:
        i = n.find(unit, start)
        if i < 0:
            return
        after = i + len(unit)
        if after >= len(n) or not (n[after].isalnum() or n[after] == "ً"):
            yield i, after
        start = after


def _numeric_duration(n: str) -> float | None:
    # Linear scan instead of a backtracking regex: find a unit, then read the
    # number immediately before it. No caller text is passed to a shell/ffmpeg.
    for unit in _DUR_UNITS:
        for i, _after in _unit_instances(n, unit):
            value = _number_before(n, i)
            if value is not None:
                return value
    return None


def _parse_duration(n: str) -> float:
    dur = _numeric_duration(n)
    if dur is None:
        for w, v in sorted(_WORD_NUM.items(), key=lambda kv: -len(kv[0])):
            if SL._norm(w) in n and re.search(r"ثاني|ثواني|ث", n):
                dur = float(v)
                break
    if dur is None:
        raise ValueError("المدة غير محددة — اكتب مثلًا «20 ثانية»")
    if not (3 <= dur <= 120):
        raise ValueError("المدة المطلوبة خارج النطاق المدعوم (3–120 ثانية)")
    return dur


def _parse_topic(n: str) -> str:
    animal = any(w in n for w in ("حيوان", "حيوانات", "خروف", "خراف", "غنم", "بقر", "ابقار", "ضاني", "رأس"))
    followup = any(w in n for w in ("متابع", "بنتابع", "ارض الواقع", "ار الواقع", "توثيق"))
    feeding = any(w in n for w in ("تغذيه", "تغذية", "علف", "اكل", "أكل"))
    weight = any(w in n for w in ("وزن", "ميزان", "يتوزن", "الميزان"))
    if weight:
        return "weight"
    if feeding and not followup:
        return "feeding"
    if animal or followup or feeding:
        return "field-followup" if (animal or followup) else "feeding"
    raise ValueError("الموضوع غير مدعوم في v1 — المدعوم: متابعة الحيوانات/التغذية/الوزن الحقلي")


def _parse_audience(n: str, assumptions: list) -> str:
    if any(w in n for w in ("مستثمر", "مستثمرين", "استثمار")):
        return "مهتمون بالاستثمار الحيواني"
    if any(w in n for w in ("اصحاب اعمال", "أصحاب أعمال", "تجار", "تاجر")):
        return "أصحاب أنشطة وتجار"
    if any(w in n for w in ("عائلات", "عائلة", "مغترب")):
        return "عائلات ومغتربون"
    assumptions.append("الجمهور غير مذكور صراحةً؛ استُخدم جمهور عام بدون استهداف استثماري أو وعود.")
    return "جمهور عام مهتم بالمزرعة والمتابعة الحقيقية"


def _parse_style_voice(n: str, warnings: list) -> tuple:
    style = "مصري بسيط وهادي"
    if any(w in n for w in ("مؤسسي", "احترافي", "رسمي")):
        style = "مؤسسي احترافي بنبرة مصرية هادئة"
    if any(w in n for w in ("حماسي", "سريع", "طاقة")):
        style = "إيقاع أسرع"
        warnings.append("الإيقاع السريع قد لا يناسب نبرة العلامة الهادئة؛ راجع بشريًا.")
    voice_requested = any(w in n for w in ("تعليق صوتي", "صوت", "فويس", "voiceover", "narration", "voice"))
    voice_tone = "هادي واثق"
    if any(w in n for w in ("حماسي", "سريع")):
        voice_tone = "أكثر طاقة"
        warnings.append("نبرة الصوت المطلوبة تختلف عن الصوت المثبت؛ يلزم قرار مالك صريح قبل التبديل.")
    voice_lang = "ar-EG" if any(w in n for w in ("مصري", "مصريه", "مصرية", "عاميه", "عامية")) else "ar"
    return style, voice_requested, voice_tone, voice_lang


def parse_brief(text: str) -> dict:
    raw = text.strip()
    if not raw:
        raise ValueError("الطلب فارغ")
    n = SL._norm(_latin_digits(raw))
    warnings, assumptions = [], []
    dur = _parse_duration(n)
    topic = _parse_topic(n)
    audience = _parse_audience(n, assumptions)
    style, voice_requested, voice_tone, voice_lang = _parse_style_voice(n, warnings)
    cta = None
    if any(w in n for w in ("تواصل", "واتساب", "كلمنا", "اتصل", "تواصلوا", "رسالة")):
        cta = {"type": "contact", "text": "للتفاصيل… كلمنا على واتساب.", "phone": B.PHONE}
    variety = any(w in n for w in ("متنوع", "متنوعة", "لقطات مختلفة", "تنوع"))
    message = {
        "field-followup": "متابعة الحيوانات على أرض الواقع من المزرعة",
        "feeding": "التغذية والرعاية داخل المزرعة",
        "weight": "الوزن الحقلي الموثق — بدون ادعاء ميزان واضح إن لم يظهر",
    }[topic]
    return {
        "raw_request": raw, "language": "ar-EG", "topic": topic, "message": message,
        "duration_sec": dur, "audience": audience, "style": style,
        "voice": {"requested": voice_requested, "language": voice_lang, "tone": voice_tone,
                  "profile_id": "ar-eg-calm-confident", "status": "pending-authorized-asset"},
        "cta": cta, "variety_requested": variety,
        "assumptions": assumptions, "warnings": warnings,
        "constraints": ["real-footage-only", "no-faces-without-consent", "no-profit-promises",
                        "no-city-name", "no-invented-scenes-or-timings"],
    }


def load_index(index_path: str = INDEX_PATH) -> dict:
    with open(index_path, encoding="utf-8") as f:
        return json.load(f)


def _validate_sources(idx: dict, repo: str, check_git: bool, issues: list) -> None:
    for sid, s in idx.get("sources", {}).items():
        p = s.get("path", "")
        if not p or os.path.isabs(p) or ".." in p.split("/"):
            issues.append(f"{sid}: مسار مصدر غير نسبي/غير آمن: {p}")
            continue
        fp = os.path.join(repo, p)
        if not os.path.isfile(fp):
            issues.append(f"{sid}: المصدر غير موجود: {p}")
            continue
        if s.get("sha256") and _sha256(fp, repo) != s["sha256"]:
            issues.append(f"{sid}: SHA-256 لا يطابق الفهرس")
        if not check_git:
            continue
        r = subprocess.run(["git", "ls-files", "--error-unmatch", p], cwd=repo,
                           capture_output=True, text=True)
        if r.returncode != 0:
            issues.append(f"{sid}: المصدر غير متتبع في git — غير قابل للاستعادة تلقائيًا")
            continue
        r2 = subprocess.run(["git", "cat-file", "-e", f"HEAD:{p}"], cwd=repo,
                            capture_output=True, text=True)
        if r2.returncode != 0:
            issues.append(f"{sid}: المصدر غير موجود في HEAD — لن يُستعاد من git")


def _validate_scenes(idx: dict, repo: str, issues: list) -> None:
    seen = set()
    sources = idx.get("sources", {})
    for sc in idx.get("scenes", []):
        sid = sc.get("scene_id")
        if sid in seen:
            issues.append(f"scene_id مكرر: {sid}")
        seen.add(sid)
        if sc.get("source_id") not in sources:
            issues.append(f"{sid}: مصدر غير موجود")
            continue
        src = sources[sc["source_id"]]
        a, b = sc.get("start"), sc.get("end")
        if not (isinstance(a, (int, float)) and isinstance(b, (int, float)) and 0 <= a < b):
            issues.append(f"{sid}: توقيت غير صالح")
        elif src.get("duration") is not None and b > src["duration"] + TOL:
            issues.append(f"{sid}: نهاية المشهد تتجاوز مدة المصدر")
        pv = sc.get("preview", "")
        if not pv or os.path.isabs(pv) or not os.path.isfile(os.path.join(repo, pv)):
            issues.append(f"{sid}: معاينة غير قابلة للاسترجاع: {pv}")


def validate_index(idx: dict, repo: str = REPO, check_git: bool = True) -> list:
    issues = []
    if not idx.get("sources"):
        issues.append("الفهرس بلا مصادر")
    _validate_sources(idx, repo, check_git, issues)
    _validate_scenes(idx, repo, issues)
    return issues


def _usable(sc: dict) -> bool:
    tags = set(sc.get("tags", []))
    return bool(sc.get("usable")) and not ({"person", "endcard", "unusable"} & tags)


def rank_candidates(idx: dict, brief: dict) -> list:
    query = brief["message"] + " " + brief["raw_request"]
    qtags = SL.tokenize(query)
    out = []
    for sc in idx.get("scenes", []):
        if not _usable(sc):
            continue
        tags = set(sc.get("tags", []))
        matched = qtags & tags
        relevance = (len(matched) / max(1, len(qtags))) * 10
        score = relevance + float(sc.get("quality", 0.5)) * 2
        out.append({"scene_id": sc["scene_id"], "score": round(score, 3),
                    "matched_tags": sorted(matched), "tags": sorted(tags),
                    "quality": sc.get("quality"), "source_id": sc["source_id"],
                    "start": sc["start"], "end": sc["end"]})
    out.sort(key=lambda r: (-r["score"], r["scene_id"]))
    return out


def _fill_step(weights, caps, alloc, active, remaining):
    tw = sum(weights[i] for i in active)
    next_active, progressed = [], False
    for i in active:
        share = remaining * weights[i] / tw
        room = caps[i] - alloc[i]
        if share >= room - 1e-9:
            alloc[i] = caps[i]
            remaining -= room
            progressed = True
        else:
            next_active.append(i)
    return remaining, next_active, progressed


def _round_alloc(alloc, caps, mins, budget):
    diff = round(budget - sum(alloc), 3)
    for i in range(len(alloc) - 1, -1, -1):
        new = round(alloc[i] + diff, 3)
        if mins[i] - 1e-9 <= new <= caps[i] + 1e-9:
            alloc[i] = new
            break
    return [round(x, 3) for x in alloc]


def _waterfill(weights: list, caps: list, budget: float, mins: list | None = None) -> list:
    mins = list(mins) if mins is not None else [0.0] * len(weights)
    if budget + 1e-9 < sum(mins):
        raise ValueError("المدة المطلوبة أقصر من الحد الأدنى للمشاهد المختارة")
    if budget > sum(caps) + 1e-9:
        raise ValueError("المدة المطلوبة تتجاوز إجمالي المشاهد المتاحة بدون تكرار")
    alloc = list(mins)
    remaining = budget - sum(mins)
    active = [i for i in range(len(weights)) if caps[i] > mins[i] + 1e-9]
    while remaining > 1e-9 and active:
        remaining, active, progressed = _fill_step(weights, caps, alloc, active, remaining)
        if not progressed:
            tw = sum(weights[i] for i in active)
            for i in active:
                alloc[i] += remaining * weights[i] / tw
            remaining = 0.0
    return _round_alloc(alloc, caps, mins, budget)


def _choose_shots(idx: dict, beats: list) -> list:
    scenes = [s for s in idx["scenes"] if _usable(s)]
    used, used_sources, used_sig = set(), {}, set()
    chosen = []
    for beat in beats:
        cands = [s for s in scenes if s["scene_id"] not in used and beat["tags"] <= set(s["tags"])]
        if not cands:
            raise ValueError(f"لا يوجد مشهد صالح للدور {beat['role']} في الفهرس")
        best = max(cands, key=lambda s, b=beat: _shot_score(s, b, used_sources, used_sig))
        used.add(best["scene_id"])
        used_sources[best["source_id"]] = used_sources.get(best["source_id"], 0) + 1
        used_sig.add(tuple(sorted(best["tags"])))
        chosen.append((beat, best))
    return chosen


def _shot_score(sc: dict, beat: dict, used_sources: dict, used_sig: set) -> float:
    tags = set(sc["tags"])
    score = float(sc.get("quality", 0.5)) * 4 + len(tags & beat["tags"])
    score -= 0.3 * used_sources.get(sc["source_id"], 0)
    if tuple(sorted(tags)) in used_sig:
        score -= 0.3
    if beat.get("short_bonus") and sc["end"] - sc["start"] < 2.0:
        score += 1.5
    return score


def _excerpt(sc: dict, d: float) -> tuple:
    full = sc["end"] - sc["start"]
    if d >= full - 1e-9:
        return sc["start"], sc["end"], "full-indexed-scene"
    center = (sc["start"] + sc["end"]) / 2
    a = round(max(sc["start"], center - d / 2), 3)
    b = round(a + d, 3)
    if b > sc["end"] + 1e-9:
        b = sc["end"]
        a = round(b - d, 3)
    return a, b, "centered-excerpt-within-indexed-scene"


def _timeline_from_shots(shots: list, idx: dict) -> list:
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    timeline, cursor = [], 0.0
    for shot in shots:
        sc = by_id[shot["scene_id"]]
        d = shot["planned_duration"]
        a, b, policy = _excerpt(sc, d)
        timeline.append({
            "scene_id": sc["scene_id"], "source_id": sc["source_id"], "role": shot["role"],
            "source_start": a, "source_end": b, "planned_duration": round(b - a, 3),
            "timeline_start": round(cursor, 3), "timeline_end": round(cursor + (b - a), 3),
            "excerpt_policy": policy, "indexed_scene_start": sc["start"], "indexed_scene_end": sc["end"],
            "text": shot["text"], "motion": shot["motion"], "tags": sc["tags"],
            "quality": sc.get("quality"), "preview": sc["preview"], "treatment": sc.get("treatment", {}),
        })
        cursor += b - a
    return timeline


def _voice_windows(phrases: list, total: float, hook_sec: float) -> list:
    budget = round(total - hook_sec, 3)
    if budget <= 0:
        raise ValueError("لا وقت للتعليق بعد الهوك")
    wcounts = [max(1, len(p["text"].split())) for p in phrases]
    pdurs = _waterfill([float(w) for w in wcounts], [budget] * len(wcounts), budget,
                       [min(1.0, budget / len(wcounts))] * len(wcounts))
    vc = hook_sec
    for p, d in zip(phrases, pdurs):
        p["from"], p["to"] = round(vc, 3), round(vc + d, 3)
        vc += d
    return phrases


def select_and_schedule(idx: dict, brief: dict) -> dict:
    beats = BEATS[brief["topic"]]
    endcard = 3.0 if brief.get("cta") else 0.0
    budget = round(brief["duration_sec"] - endcard, 3)
    if budget <= 0:
        raise ValueError("المدة لا تتسع للخاتمة")
    chosen = _choose_shots(idx, beats)
    caps = [sc["end"] - sc["start"] for _, sc in chosen]
    weights = [b["weight"] for b, _ in chosen]
    durations = _waterfill(weights, caps, budget, [min(1.0, c) for c in caps])
    shots = []
    for (beat, sc), d in zip(chosen, durations):
        shots.append({"scene_id": sc["scene_id"], "role": beat["role"], "text": beat["text"],
                      "motion": beat["motion"], "planned_duration": d, "weight": beat["weight"]})
    timeline = _timeline_from_shots(shots, idx)
    hook = "الحيوانات… متابعة حقيقية."
    hook_sec = min(2.0, round(brief["duration_sec"] * 0.1, 3))
    voice_phrases = [{"role": t["role"], "text": t["text"]} for t in timeline]
    if brief.get("cta"):
        voice_phrases.append({"role": "cta", "text": brief["cta"]["text"]})
    _voice_windows(voice_phrases, brief["duration_sec"], hook_sec)
    return {
        "topic": brief["topic"], "duration_sec": brief["duration_sec"], "endcard_sec": endcard,
        "hook": hook, "hook_sec": hook_sec, "content_budget_sec": budget,
        "shots": timeline, "voice_phrases": voice_phrases,
        "caption_timing_source": "reading-budget-estimate",
        "audio_status": "silent-visual-draft",
    }


def _default_endcard(brief: dict, silent: bool = True) -> dict:
    return {"headline": "ملك حقيقي", "subtitle": "ومتابعة بعينك",
            "cta": f"واتساب {B.PHONE}" if brief.get("cta") else "TerraNex",
            "disclosure": SILENT_DISCLOSURE if silent else VOICE_DISCLOSURE}


def build_spec(idx: dict, brief: dict, sched: dict, spec_path, endcard: dict | None = None) -> dict:
    spec_dir = os.path.dirname(os.path.abspath(spec_path))
    clips = []
    for shot in sched["shots"]:
        sc = next(s for s in idx["scenes"] if s["scene_id"] == shot["scene_id"])
        src = idx["sources"][sc["source_id"]]
        source_abs = os.path.join(REPO, src["path"])
        clip = {"path": os.path.relpath(source_abs, spec_dir).replace(os.sep, "/"),
                "start": shot["source_start"], "end": shot["source_end"],
                "scene_id": sc["scene_id"],
                "_indexed_scene": [sc["start"], sc["end"]],
                "_excerpt_policy": shot["excerpt_policy"]}
        clip.update(sc.get("treatment", {}))
        clips.append(clip)
    captions = [{"from": p["from"], "to": p["to"], "text": p["text"]} for p in sched["voice_phrases"]]
    spec = {
        "title": f"creative-director-{brief['topic']}-{int(brief['duration_sec'])}s",
        "template": "corporate-no-face", "on_screen_persons": [], "consent_persons": [],
        "clips": clips, "hook": sched["hook"], "hook_sec": sched["hook_sec"],
        "captions": captions, "endcard_sec": sched["endcard_sec"],
        "endcard": endcard or _default_endcard(brief),
        "visual_draft": True,
        "audio": {"original_gain": 0.12, "ambient_from": 0, "duck": True, "lufs": -15},
        "_library_derived": True,
        "_scene_ids": [c["scene_id"] for c in clips],
        "_caption_timing_source": sched["caption_timing_source"],
    }
    return spec


def _lint_texts(texts: list) -> None:
    joined = "\n".join(t for t in texts if t)
    cr = critic.check(joined)
    if cr["hard"]:
        raise ValueError("نص الخطة يخالف قواعد الالتزام: " + "; ".join(h["code"] for h in cr["hard"]))
    for t in texts:
        if t and len(t.split()) > 14:
            raise ValueError(f"نص طويل جدًا للكادر: {t}")


def _validate_clip(shot: dict, clip: dict, by_id: dict) -> None:
    sid = shot["scene_id"]
    if sid not in by_id:
        raise ValueError(f"scene_id مختلق: {sid}")
    sc = by_id[sid]
    if not _usable(sc):
        raise ValueError(f"مشهد غير صالح: {sid}")
    if clip["scene_id"] != sid:
        raise ValueError("عدم تطابق scene_id بين الخطة والـspec")
    a, b = clip["start"], clip["end"]
    if not (sc["start"] - TOL <= a < b <= sc["end"] + TOL):
        raise ValueError(f"توقيت خارج حدود المشهد المفهرس: {sid} [{a},{b}]")
    if os.path.isabs(clip["path"]):
        raise ValueError("مسار مطلق في الـspec — غير قابل للنقل")


def _validate_caption_windows(caps: list, total: float) -> None:
    prev = 0.0
    for cap in caps:
        if not (0 <= cap["from"] < cap["to"] <= total + TOL) or cap["from"] < prev - TOL:
            raise ValueError("نوافذ الكابشن غير صالحة")
        prev = cap["to"]


def validate_plan(idx: dict, brief: dict, sched: dict, spec: dict) -> None:
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    ids = [s["scene_id"] for s in sched["shots"]]
    if len(set(ids)) != len(ids):
        raise ValueError("مشهد مكرر في الخطة")
    for shot, clip in zip(sched["shots"], spec["clips"]):
        _validate_clip(shot, clip, by_id)
    total = sum(c["end"] - c["start"] for c in spec["clips"]) + spec["endcard_sec"]
    if total > brief["duration_sec"] + TOL:
        raise ValueError(f"الخطة تتجاوز المدة المطلوبة: {total:.2f} > {brief['duration_sec']}")
    _validate_caption_windows(spec["captions"], total)
    texts = [spec["hook"]] + [c["text"] for c in spec["captions"]] + list(spec.get("endcard", {}).values())
    _lint_texts(texts)
    if len(spec["hook"].split()) > 8:
        raise ValueError("الهوك أطول من 8 كلمات")


def _reject_unknown(obj: dict, allowed: set, label: str) -> None:
    extra = set(obj) - allowed
    if extra:
        raise ValueError(f"حقول غير مدعومة في {label}: {sorted(extra)}")


def _creative_shape(creative: dict, brief: dict) -> tuple:
    if creative.get("schema_version") != 1:
        raise ValueError("creative JSON يدعم schema_version=1 فقط")
    _reject_unknown(creative, {"schema_version", "topic", "note", "hook", "endcard_sec", "shots",
                               "voice_phrases", "cta", "endcard"}, "creative JSON")
    _reject_unknown(creative.get("hook", {}), {"text", "duration_sec"}, "hook")
    for s in creative.get("shots", []):
        _reject_unknown(s, {"scene_id", "role", "text", "motion", "duration_sec", "weight",
                            "source_start", "source_end"}, "shot")
    if creative.get("endcard"):
        _reject_unknown(creative["endcard"], {"headline", "subtitle", "cta", "disclosure"}, "endcard")
    if creative.get("topic") and creative["topic"] != brief["topic"]:
        raise ValueError("موضوع creative JSON يختلف عن موضوع المشروع")
    shots_in = creative.get("shots")
    if not isinstance(shots_in, list) or not (1 <= len(shots_in) <= 12):
        raise ValueError("shots يجب أن تكون قائمة من 1 إلى 12 لقطة")
    return shots_in, float(creative.get("endcard_sec", 3.0 if brief.get("cta") else 0.0))


def _creative_shot(s: dict, i: int, by_id: dict) -> tuple:
    sid = s.get("scene_id")
    if sid not in by_id:
        raise ValueError(f"scene_id مختلق: {sid}")
    sc = by_id[sid]
    if not _usable(sc):
        raise ValueError(f"مشهد غير صالح: {sid}")
    d = float(s.get("duration_sec", sc["end"] - sc["start"]))
    if not (0.2 <= d <= sc["end"] - sc["start"] + TOL):
        raise ValueError(f"مدة لقطة خارج حدود المشهد: {sid}")
    if "source_start" in s or "source_end" in s:
        a = float(s.get("source_start", sc["start"]))
        b = float(s.get("source_end", a + d))
        if not (sc["start"] - TOL <= a < b <= sc["end"] + TOL) or abs((b - a) - d) > TOL:
            raise ValueError(f"توقيت مصدر خارج حدود الفهرس: {sid}")
    return {"scene_id": sid, "role": s.get("role", f"creative-{i+1}"),
            "text": s.get("text", ""), "motion": s.get("motion", "قطع بسيط؛ بدون حركة كاميرا مُضافة."),
            "planned_duration": round(d, 3), "weight": float(s.get("weight", 1.0))}, d


def validate_creative(idx: dict, brief: dict, creative: dict) -> dict:
    shots_in, endcard_sec = _creative_shape(creative, brief)
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    budget = round(brief["duration_sec"] - endcard_sec, 3)
    shots, total, seen = [], 0.0, set()
    for i, s in enumerate(shots_in):
        sid = s.get("scene_id")
        if sid in seen:
            raise ValueError(f"مشهد مكرر: {sid}")
        seen.add(sid)
        shot, d = _creative_shot(s, i, by_id)
        shots.append(shot)
        total += d
    if abs(total - budget) > TOL:
        raise ValueError(f"مجموع اللقطات {total:.3f} لا يطابق الميزانية {budget:.3f}")
    hook = creative.get("hook", {}).get("text", "")
    if not hook:
        raise ValueError("hook مطلوب")
    hook_sec = float(creative.get("hook", {}).get("duration_sec", min(2.0, brief["duration_sec"] * 0.1)))
    voice = creative.get("voice_phrases") or [{"role": s["role"], "text": s["text"]} for s in shots]
    if brief.get("cta") and creative.get("cta", {}).get("text"):
        voice = voice + [{"role": "cta", "text": creative["cta"]["text"]}]
    _voice_windows(voice, brief["duration_sec"], hook_sec)
    sched = {"topic": brief["topic"], "duration_sec": brief["duration_sec"], "endcard_sec": endcard_sec,
             "hook": hook, "hook_sec": hook_sec, "content_budget_sec": budget,
             "shots": _timeline_from_shots(shots, idx), "voice_phrases": voice,
             "caption_timing_source": "reading-budget-estimate", "audio_status": "silent-visual-draft"}
    endcard = creative.get("endcard") or _default_endcard(brief)
    if brief.get("cta") and B.PHONE not in endcard.get("cta", ""):
        raise ValueError("خاتمة التواصل يجب أن تحمل رقم واتساب الرسمي")
    spec = build_spec(idx, brief, sched, os.path.join(PROJECTS, "validation", SPEC), endcard)
    validate_plan(idx, brief, sched, spec)
    return {"schedule": sched, "endcard": endcard}


def _storyboard_png(brief: dict, sched: dict, out: str) -> str:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    shots = sched["shots"]
    cols = 2
    rows = (len(shots) + 1 + cols - 1) // cols
    tw, th, lab = 420, 747, 150
    header, footer = 150, 90
    W = cols * tw + 40
    H = header + rows * (th + lab) + footer
    canvas = Image.new("RGB", (W, H), B.hex2rgb(B.C["bg_dark"]))
    d = ImageDraw.Draw(canvas)

    def txt(x, y, s, px, fill, anchor="rt"):
        B.text(d, (x, y), s, B.font("bold", px), fill, anchor=anchor)

    txt(W - 24, 30, f"Creative Director v1 — {brief['topic']}", 30, B.hex2rgb(B.C["gold"]))
    txt(W - 24, 72, f"المدة {brief['duration_sec']:.0f}ث · {brief['style']}", 22, (226, 232, 240))
    status = "مسودة بصرية صامتة — ليست إعلانًا نهائيًا" if sched["audio_status"] == "silent-visual-draft" else "مرفق صوت معتمد"
    txt(W - 24, 104, status, 20, (250, 204, 21))
    panels = []
    for shot in shots:
        panels.append((shot["preview"], shot["scene_id"],
                       f"المصدر {shot['source_start']}–{shot['source_end']}s",
                       f"الخط الزمني {shot['timeline_start']}–{shot['timeline_end']}s",
                       shot["text"], shot["motion"]))
    panels.append((None, "endcard", f"ختام {sched['endcard_sec']}s",
                   f"الخط الزمني {sched['duration_sec'] - sched['endcard_sec']}–{sched['duration_sec']}s",
                   brief["cta"]["text"] if brief.get("cta") else "TerraNex",
                   "شعار كبير + دعوة تواصل + وسم الحالة"))
    for i, (pv, sid, l1, l2, text, motion) in enumerate(panels):
        r, c = divmod(i, cols)
        x, y = 20 + c * tw, header + r * (th + lab)
        if pv:
            im = Image.open(os.path.join(REPO, pv)).convert("RGB").resize((tw - 12, th))
        else:
            im = Image.new("RGBA", (tw - 12, th), B.hex2rgb(B.C["bg_mid"]) + (255,))
            B.place_logo(im, (tw - 12) // 2, th // 3, int((tw - 12) * 0.6), "full")
            im = im.convert("RGB")
        canvas.paste(im, (x, y))
        d.rectangle([x, y + th, x + tw - 12, y + th + lab], fill=B.hex2rgb(B.C["bg_mid"]))
        rx = x + tw - 24
        txt(rx, y + th + 10, f"{i + 1}. {sid}", 22, B.hex2rgb(B.C["gold"]))
        txt(rx, y + th + 40, l1 + " · " + l2, 17, (226, 232, 240))
        txt(rx, y + th + 68, text, 19, (134, 239, 172))
        txt(rx, y + th + 98, motion, 15, (148, 163, 184))
        txt(rx, y + th + 122, "الصوت: تعليق مصري هادي معتمد أو صمت موسوم", 14, (148, 163, 184))
    fy = header + rows * (th + lab) + 18
    txt(W - 24, fy, "كل التوقيتات من الفهرس عبر scene_id؛ المعاينات مصدر خام والرندر يخفي العلامة المحروقة.", 17, (148, 163, 184))
    canvas.save(out)
    return out


def _caption_text(sched: dict) -> str:
    return "\n".join([sched["hook"]] + [p["text"] for p in sched["voice_phrases"]]) + "\n\n#TerraNex #متابعة_حقيقية #مزرعة\n"


def _version_entry(mem: dict, version: int) -> dict:
    for v in mem["versions"]:
        if v["version"] == version:
            return v
    raise ValueError(f"الإصدار غير موجود: {version}")


def _video_path(project_id: str, version: int) -> str:
    safe_id = os.path.basename(project_id)
    v = int(version)
    return os.path.join(MARKETING_ROOT, "فيديوهات-المنتجة", "creative-director", safe_id, f"v{v:04d}.mp4")


def _save_current(store: ProjectStore, mem: dict, brief: dict, plan: dict, spec: dict,
                  sched: dict) -> None:
    store.write_json(BRIEF, brief)
    store.write_json(PLAN, plan)
    store.write_json(SPEC, spec)
    store.write_caption(_caption_text(sched))
    _storyboard_png(brief, sched, str(store.path(STORYBOARD)))
    mem["brief"] = brief
    mem["schedule"] = sched
    mem["selected_scene_ids"] = [s["scene_id"] for s in sched["shots"]]
    mem["updated_at"] = _now()
    mem["artifacts"].update({
        "brief": _rel(store.path(BRIEF)), "plan": _rel(store.path(PLAN)),
        "spec": _rel(store.path(SPEC)), "storyboard": _rel(store.path(STORYBOARD)),
        "caption": _rel(store.path(CAPTION)),
    })
    store.write_json(MEMORY, mem)
    store.snapshot(mem["current_version"])
    entry = _version_entry(mem, mem["current_version"])
    entry.update({"scene_ids": mem["selected_scene_ids"], "hook": sched["hook"],
                  "status": mem["status"], "snapshot": f"versions/v{mem['current_version']:04d}"})
    store.write_json(MEMORY, mem)


def _new_version(mem: dict, source: str, instruction: str | None = None) -> int:
    version = mem["current_version"] + 1
    mem["current_version"] = version
    mem["status"] = "planned"
    mem["versions"].append({"version": version, "created_at": _now(), "source": source,
                            "instruction": instruction, "status": "planned",
                            "scene_ids": [], "hook": None, "video": None, "sha256": None})
    mem["artifacts"].pop("video", None)
    mem["artifacts"].pop("render_report", None)
    mem["artifacts"].pop("critic_report", None)
    return version


def create_project(request: str, project_id: str | None = None, projects_root: str = PROJECTS,
                   index_path: str = INDEX_PATH) -> dict:
    brief = parse_brief(request)
    idx = load_index(index_path)
    issues = validate_index(idx)
    if issues:
        raise ValueError("فهرس المشاهد غير قابل للاسترجاع:\n" + "\n".join(issues))
    if not project_id:
        project_id = "cd-" + hashlib.sha256(request.encode("utf-8")).hexdigest()[:10]
    store = ProjectStore(project_id, projects_root)
    ranked = rank_candidates(idx, brief)
    sched = select_and_schedule(idx, brief)
    spec = build_spec(idx, brief, sched, store.path(SPEC))
    validate_plan(idx, brief, sched, spec)
    plan = {"brief": brief, "search_ranking": ranked[:20], "schedule": sched,
            "selected_scene_ids": [s["scene_id"] for s in sched["shots"]],
            "authoring_mode": "template",
            "spec": _rel(store.path(SPEC)), "storyboard": _rel(store.path(STORYBOARD))}
    mem = {
        "schema_version": 2, "project_id": store.project_id, "created_at": _now(), "updated_at": _now(),
        "base_commit": subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True).stdout.strip(),
        "branch": subprocess.run(["git", "branch", "--show-current"], cwd=REPO, capture_output=True, text=True).stdout.strip(),
        "current_version": 1, "status": "planned", "request": request,
        "brief": brief, "schedule": sched, "selected_scene_ids": plan["selected_scene_ids"],
        "artifacts": {}, "versions": [{"version": 1, "created_at": _now(), "source": "template",
                                       "instruction": None, "status": "planned", "scene_ids": [],
                                       "hook": None, "video": None, "sha256": None}],
        "decisions": ["استخدام فهرس المشاهد الحقيقي فقط", "مسودة بصرية صامتة حتى يتوفر تعليق معتمد"],
        "revisions": [],
    }
    _save_current(store, mem, brief, plan, spec, sched)
    store.append_event("created", {"project_id": store.project_id, "scene_ids": mem["selected_scene_ids"]})
    return {"project_dir": str(store.dir), "brief": brief, "plan": plan, "spec": spec, "memory": mem}


def load_project(project_id: str, projects_root: str = PROJECTS) -> dict:
    store = ProjectStore(project_id, projects_root)
    mem = store.read_json(MEMORY)
    if mem.get("schema_version") != 2:
        raise ValueError("ذاكرة المشروع بإصدار قديم — شغّل migration أولًا")
    plan = store.read_json(PLAN)
    spec = store.read_json(SPEC)
    return {"project_dir": str(store.dir), "memory": mem, "plan": plan, "spec": spec, "store": store}


def apply_creative(project_id: str, creative: dict | None = None, projects_root: str = PROJECTS) -> dict:
    proj = load_project(project_id, projects_root)
    store, mem, brief = proj["store"], proj["memory"], proj["memory"]["brief"]
    if creative is None:
        creative = store.read_json(CREATIVE_INPUT)
    idx = load_index()
    validated = validate_creative(idx, brief, creative)
    sched, endcard = validated["schedule"], validated["endcard"]
    version = _new_version(mem, "arena-json", creative.get("note"))
    spec = build_spec(idx, brief, sched, store.path(SPEC), endcard)
    validate_plan(idx, brief, sched, spec)
    plan = {"brief": brief, "search_ranking": proj["plan"].get("search_ranking", []),
            "schedule": sched, "selected_scene_ids": [s["scene_id"] for s in sched["shots"]],
            "authoring_mode": "arena-json", "creative_input": creative,
            "spec": _rel(store.path(SPEC)), "storyboard": _rel(store.path(STORYBOARD))}
    mem["revisions"].append({"at": _now(), "version": version, "source": "arena-json",
                             "note": creative.get("note", "سيناريو إبداعي من وكيل Arena")})
    _save_current(store, mem, brief, plan, spec, sched)
    store.append_event("creative-applied", {"version": version, "scene_ids": mem["selected_scene_ids"]})
    return {"version": version, "spec": spec, "plan": plan}


def parse_revision(instruction: str) -> dict:
    n = SL._norm(instruction or "")
    ops = []
    if any(w in n for w in ("غير البدايه", "غير البداية", "بدل البدايه", "بدل البداية", "بدايه مختلفه", "بداية مختلفة")):
        ops.append({"op": "replace_beginning"})
    if "قدم" in n and any(w in n for w in ("تغذيه", "تغذية", "العلف")):
        ops.append({"op": "promote_tag", "tag": "feeding", "position": 1 if ops else 0})
    if "قلل" in n and any(w in n for w in ("وزن", "ميزان")):
        ops.append({"op": "reduce_tag_duration", "tag": "scale", "factor": 0.7, "target": "longest"})
    if not ops:
        raise ValueError("أمر التعديل غير مدعوم في v1 — استخدم: غيّر البداية / قدم التغذية / قلل لقطة الوزن")
    return {"schema_version": 1, "operations": ops}


def _choose_replacement(idx: dict, first: dict, used: set) -> dict:
    tags = set(first.get("tags", []))
    candidates = [s for s in idx["scenes"] if _usable(s) and s["scene_id"] not in used]
    if tags:
        candidates = [s for s in candidates if tags & set(s["tags"])] or candidates
    non_scale = [s for s in candidates if "scale" not in s["tags"]]
    if non_scale:
        candidates = non_scale
    candidates.sort(key=lambda s: (-(s["end"] - s["start"]), -float(s.get("quality", 0.5)), s["scene_id"]))
    if not candidates:
        raise ValueError("لا يوجد مشهد بديل للبداية")
    return candidates[0]


def _op_replace_beginning(shots: list, op: dict, idx: dict) -> bool:
    used = {s["scene_id"] for s in shots}
    sc = _choose_replacement(idx, shots[0], used)
    shots[0].update({"scene_id": sc["scene_id"], "role": "establish-alt",
                     "text": "من المزرعة… متابعة حقيقية.",
                     "motion": "بداية مختلفة من الفهرس؛ قطع هادئ.",
                     "planned_duration": round(sc["end"] - sc["start"], 3),
                     "tags": sc["tags"]})
    return True


def _op_promote_tag(shots: list, op: dict, idx: dict) -> bool:
    tag, pos = op["tag"], int(op.get("position", 0))
    i = next((i for i, s in enumerate(shots) if tag in s.get("tags", []) and s.get("role") == tag), None)
    if i is None:
        i = next((i for i, s in enumerate(shots) if tag in s.get("tags", [])), None)
    if i is not None:
        shot = shots.pop(i)
        shots.insert(min(pos, len(shots)), shot)
        return False
    used = {x["scene_id"] for x in shots}
    cand = [s for s in idx["scenes"] if _usable(s) and tag in s["tags"] and s["scene_id"] not in used]
    if not cand:
        raise ValueError(f"لا يوجد مشهد بالوسم {tag}")
    sc = cand[0]
    shots.insert(min(pos, len(shots)), {"scene_id": sc["scene_id"], "role": f"promoted-{tag}",
                                        "text": "التغذية… من قلب المزرعة.",
                                        "motion": "تقديم لقطة التغذية.",
                                        "planned_duration": round(sc["end"] - sc["start"], 3),
                                        "tags": sc["tags"]})
    return False


def _op_reduce_tag(shots: list, op: dict, idx: dict) -> bool:
    tag = op["tag"]
    tagged = [s for s in shots if tag in s.get("tags", [])]
    if not tagged:
        raise ValueError(f"لا توجد لقطة بالوسم {tag} لتقليلها")
    target = max(tagged, key=lambda s: s["planned_duration"]) if op.get("target") == "longest" else tagged[0]
    target["max_duration"] = round(max(0.5, target["planned_duration"] * float(op.get("factor", 0.7))), 3)
    return False


def _apply_ops(shots: list, ops: list, idx: dict) -> tuple:
    shots = copy.deepcopy(shots)
    handlers = {"replace_beginning": _op_replace_beginning, "promote_tag": _op_promote_tag,
                "reduce_tag_duration": _op_reduce_tag, "set_hook": lambda s, o, i: True}
    hook_changed = False
    for op in ops:
        handler = handlers.get(op.get("op"))
        if handler is None:
            raise ValueError(f"عملية تعديل غير مدعومة: {op.get('op')}")
        hook_changed = handler(shots, op, idx) or hook_changed
    return shots, hook_changed


def _shot_caps(shots: list, by_id: dict) -> list:
    return [min(by_id[s["scene_id"]]["end"] - by_id[s["scene_id"]]["start"],
                s.get("max_duration", 1e9)) for s in shots]


def _add_balance_scene(shots: list, idx: dict, used: set, prefer_tags: set) -> None:
    cand = [s for s in idx["scenes"] if _usable(s) and s["scene_id"] not in used]
    cand.sort(key=lambda s: (-(len(prefer_tags & set(s["tags"]))), -float(s.get("quality", 0.5)), s["scene_id"]))
    if not cand:
        raise ValueError("المادة المتاحة لا تكفي إعادة التوازن بعد التعديل")
    sc = cand[0]
    used.add(sc["scene_id"])
    insert_at = next((i for i, s in enumerate(shots) if "scale" in s.get("tags", [])), len(shots))
    shots.insert(insert_at, {"scene_id": sc["scene_id"], "role": "added-for-balance",
                             "text": "ومن المزرعة… خطوة بخطوة.",
                             "motion": "لقطة إضافية من الفهرس لحفظ المدة.",
                             "planned_duration": round(sc["end"] - sc["start"], 3),
                             "tags": sc["tags"], "weight": 1.0})


def _rebalance(shots: list, idx: dict, budget: float, prefer_tags: set) -> list:
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    for s in shots:
        sc = by_id[s["scene_id"]]
        s["tags"] = sc["tags"]
        s["weight"] = s.get("weight", 1.0) * (2.0 if prefer_tags & set(sc["tags"]) else 1.0)
    used = {s["scene_id"] for s in shots}
    while sum(_shot_caps(shots, by_id)) < budget - 1e-9:
        _add_balance_scene(shots, idx, used, prefer_tags)
    cs = _shot_caps(shots, by_id)
    durations = _waterfill([s.get("weight", 1.0) for s in shots], cs, budget, [min(1.0, c) for c in cs])
    for s, d in zip(shots, durations):
        s["planned_duration"] = d
    return shots


def revise_project(project_id: str, instruction: str | None = None, patch: dict | None = None,
                   projects_root: str = PROJECTS) -> dict:
    proj = load_project(project_id, projects_root)
    store, mem, plan = proj["store"], proj["memory"], proj["plan"]
    brief = mem["brief"]
    if patch is None:
        if instruction:
            patch = parse_revision(instruction)
        elif store.exists(REVISION_INPUT):
            patch = store.read_json(REVISION_INPUT)
        else:
            raise ValueError("لا يوجد أمر تعديل أو patch")
    if patch.get("schema_version") != 1:
        raise ValueError("revision JSON يدعم schema_version=1 فقط")
    idx = load_index()
    sched = copy.deepcopy(plan["schedule"])
    shots, hook_changed = _apply_ops(sched["shots"], patch.get("operations", []), idx)
    prefer = {"feeding"} if any(op.get("tag") == "feeding" for op in patch.get("operations", [])) else set()
    shots = _rebalance(shots, idx, sched["content_budget_sec"], prefer)
    timeline = _timeline_from_shots(shots, idx)
    sched["shots"] = timeline
    if hook_changed:
        sched["hook"] = "من المزرعة… متابعة حقيقية."
    voice = [{"role": t["role"], "text": t["text"]} for t in timeline]
    if brief.get("cta"):
        voice.append({"role": "cta", "text": brief["cta"]["text"]})
    _voice_windows(voice, brief["duration_sec"], sched["hook_sec"])
    sched["voice_phrases"] = voice
    sched["caption_timing_source"] = "reading-budget-estimate"
    sched["audio_status"] = "silent-visual-draft"
    version = _new_version(mem, "natural-language" if instruction else "structured-patch", instruction)
    spec = build_spec(idx, brief, sched, store.path(SPEC))
    validate_plan(idx, brief, sched, spec)
    plan.update({"schedule": sched, "selected_scene_ids": [s["scene_id"] for s in timeline],
                 "authoring_mode": "revision", "revision_patch": patch,
                 "spec": _rel(store.path(SPEC)), "storyboard": _rel(store.path(STORYBOARD))})
    mem["revisions"].append({"at": _now(), "version": version, "source": "revision",
                             "note": instruction or json.dumps(patch, ensure_ascii=False)})
    _save_current(store, mem, brief, plan, spec, sched)
    store.append_event("revised", {"version": version, "instruction": instruction,
                                   "scene_ids": mem["selected_scene_ids"]})
    return {"version": version, "spec": spec, "plan": plan}


def rollback_project(project_id: str, version: int, projects_root: str = PROJECTS) -> dict:
    proj = load_project(project_id, projects_root)
    store, mem = proj["store"], proj["memory"]
    entry = _version_entry(mem, int(version))
    store.restore(int(version))
    plan = store.read_json(PLAN)
    mem["current_version"] = int(version)
    mem["status"] = entry.get("status", "planned")
    mem["schedule"] = plan["schedule"]
    mem["selected_scene_ids"] = plan["selected_scene_ids"]
    mem["updated_at"] = _now()
    mem["artifacts"]["video"] = entry.get("video")
    store.write_json(MEMORY, mem)
    store.append_event("rollback", {"version": int(version)})
    return mem


def measure_phrases(audio_path, expected: int, thr_db: float = -38.0, merge_gap: float = 0.30) -> list:
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    # Audio bytes go through stdin: no caller-supplied path becomes an ffmpeg argument.
    with open(audio_path, "rb") as f:
        data = f.read()
    p = subprocess.run([ff, "-v", "error", "-i", "pipe:0", "-ac", "1", "-ar", "16000",
                        "-f", "s16le", "-"], input=data, capture_output=True)
    if p.returncode != 0:
        raise ValueError("تعذر قراءة الصوت")
    a = np.frombuffer(p.stdout, dtype=np.int16).astype(np.float32) / 32768
    win = 800
    n = len(a) // win
    if n == 0:
        raise ValueError("الصوت أقصر من أن يُقاس")
    rms = np.array([np.sqrt(np.mean(a[i * win:(i + 1) * win] ** 2)) for i in range(n)])
    db = 20 * np.log10(rms + 1e-9)
    segs, cur, start = [], None, 0
    for i, v in enumerate(db):
        s = bool(v > thr_db)
        if cur is None:
            cur, start = s, i
        elif s != cur:
            segs.append((cur, start * 0.05, i * 0.05))
            cur, start = s, i
    segs.append((cur, start * 0.05, n * 0.05))
    speech = [(x, y) for s, x, y in segs if s and y - x > 0.10]
    merged = []
    for x, y in speech:
        if merged and x - merged[-1][1] < merge_gap:
            merged[-1] = (merged[-1][0], y)
        else:
            merged.append((x, y))
    if len(merged) != expected:
        raise ValueError(f"عدد الجمل المقاس {len(merged)} لا يطابق السيناريو {expected} — لا تخمين تزامن")
    return [(round(x, 3), round(y, 3)) for x, y in merged]


def _verify_transcript(transcript: dict, phrases: list) -> None:
    if transcript.get("verification_method") != "human-reviewed":
        raise ValueError("مطلوب تفريغ بشري معتمد للنص المنطوق — الطاقة وحدها لا تثبت المطابقة")
    if not transcript.get("reviewer") or not transcript.get("approval_note"):
        raise ValueError("مطلوب اسم المراجع وإذن الاستخدام")
    tp = transcript.get("phrases")
    if not isinstance(tp, list) or len(tp) != len(phrases):
        raise ValueError("عدد جمل التفريغ لا يطابق السيناريو")
    for expected, got in zip(phrases, tp):
        if _norm_text(expected["text"]) != _norm_text(got.get("text", "")):
            raise ValueError("النص المنطوق في التفريغ لا يطابق الكابشن — رُفض الإرفاق")


def attach_voice(project_id: str, approval_note: str, projects_root: str = PROJECTS,
                 profile_id: str = "ar-eg-calm-confident") -> dict:
    proj = load_project(project_id, projects_root)
    store, mem, plan, spec = proj["store"], proj["memory"], proj["plan"], proj["spec"]
    with open(PERSONAS, encoding="utf-8") as f:
        personas = json.load(f)
    bank = personas.get("voice_bank", {}).get("default_narrator", {})
    if profile_id != bank.get("id"):
        raise ValueError("الصوت المطلوب ليس الصوت المثبت في الهوية")
    if not approval_note.strip():
        raise ValueError("يلزم توثيق إذن استخدام الصوت")
    asset = store.first_existing(VOICE_ASSET_NAMES)
    if asset is None:
        raise ValueError("ضع ملف الصوت المعتمد باسم voice-input.wav/mp3/m4a داخل مجلد المشروع")
    if not store.exists(VOICE_TRANSCRIPT):
        raise ValueError("مطلوب voice-transcript.json بتفريغ بشري معتمد — الطاقة وحدها لا تثبت مطابقة النص")
    transcript = store.read_json(VOICE_TRANSCRIPT)
    _verify_transcript(transcript, plan["schedule"]["voice_phrases"])
    phrases = plan["schedule"]["voice_phrases"]
    windows = measure_phrases(asset, len(phrases))
    total = sum(c["end"] - c["start"] for c in spec["clips"]) + spec["endcard_sec"]
    if windows[-1][1] > total + TOL:
        raise ValueError("الصوت أطول من الفيديو — لا قصّ تلقائي للكلام")
    padded = [(max(0.0, x - 0.05), min(total, y + 0.05)) for x, y in windows]
    spec["captions"] = [{"from": x, "to": y, "text": p["text"]} for p, (x, y) in zip(phrases, padded)]
    spec["hook_sec"] = min(spec.get("hook_sec", 0.0), padded[0][0])
    spec["visual_draft"] = False
    spec["endcard"]["disclosure"] = AI_VOICE_DISCLOSURE if transcript.get("ai_generated") else VOICE_DISCLOSURE
    spec["voice"] = {"path": asset.name, "profile_id": profile_id, "sha256": _sha256(asset, str(store.dir)),
                     "timing_source": "measured-energy+approved-transcript",
                     "approval_note": approval_note,
                     "transcript_sha256": _sha256(store.path(VOICE_TRANSCRIPT), str(store.dir)),
                     "transcript_verification": "human-reviewed"}
    spec["_caption_timing_source"] = "measured-energy+approved-transcript"
    plan["schedule"]["caption_timing_source"] = spec["_caption_timing_source"]
    plan["schedule"]["audio_status"] = "voice-attached"
    for p, (x, y) in zip(phrases, padded):
        p["from"], p["to"] = x, y
    mem["status"] = "voice-attached"
    mem["decisions"].append("إرفاق صوت معتمد + تفريغ بشري مطابق + تزامن مقاس بالطاقة")
    _save_current(store, mem, mem["brief"], plan, spec, plan["schedule"])
    entry = _version_entry(mem, mem["current_version"])
    entry["voice_sha256"] = spec["voice"]["sha256"]
    store.write_json(MEMORY, mem)
    store.append_event("voice-attached", {"sha256": spec["voice"]["sha256"], "phrases": len(phrases)})
    return spec


def publication_readiness(spec: dict, qa_report: dict, critic_report: dict) -> dict:
    blockers = []
    if spec.get("visual_draft"):
        blockers.append("لا يوجد تعليق صوتي معتمد مطابق للسكربت")
    if not qa_report.get("pass"):
        blockers.append("فحص الفيديو التقني لم ينجح")
    if critic_report.get("hard") or critic_report.get("score", 0) < 80:
        blockers.append("النص لم يجتز بوابة الالتزام")
    voice = spec.get("voice") or {}
    if voice.get("transcript_verification") != "human-reviewed":
        blockers.append("مطابقة النص المنطوق غير موثقة بتفريغ بشري")
    blockers.append("قرار النشر الفعلي من المالك غير مسجل")
    return {"ready": False, "decision": "غير جاهز للنشر", "blockers": blockers,
            "text_success": not critic_report.get("hard") and critic_report.get("score", 0) >= 80,
            "technical_success": bool(qa_report.get("pass"))}


def render_project(project_id: str, projects_root: str = PROJECTS, force: bool = False) -> dict:
    proj = load_project(project_id, projects_root)
    store, mem, spec, plan = proj["store"], proj["memory"], proj["spec"], proj["plan"]
    idx = load_index()
    validate_plan(idx, mem["brief"], plan["schedule"], spec)
    entry = _version_entry(mem, mem["current_version"])
    video = confine(os.path.join(REPO, entry["video"]), REPO) if entry.get("video") else _video_path(store.project_id, mem["current_version"])
    if not force and entry.get("sha256") and os.path.isfile(video):
        report = store.read_json(RENDER_REPORT) if store.exists(RENDER_REPORT) else {}
        return {"render": {"out": video, "sha256": entry["sha256"], "cached": True},
                "qa": report, "video": video}
    voice = None
    if spec.get("voice"):
        if spec["voice"]["path"] not in VOICE_ASSET_NAMES:
            raise ValueError("مسار الصوت غير مسموح")
        voice = str(store.path(spec["voice"]["path"]))
    os.makedirs(os.path.dirname(video), exist_ok=True)
    result = R.build(str(store.path(SPEC)), voice, video)
    sha = _sha256(video, MARKETING_ROOT)
    visual_draft = bool(spec.get("visual_draft"))
    report = qa_video.qa(video, "reels", visual_draft=visual_draft)
    expected = mem["brief"]["duration_sec"]
    if abs(result["duration"] - expected) > 0.1:
        report["warns"].append(f"المدة الفعلية {result['duration']}ث تختلف عن المطلوبة {expected}ث")
    report["expected_duration_sec"] = expected
    report["visual_draft"] = visual_draft
    report["technical_pass"] = report["pass"]
    report["status"] = "visual-draft" if visual_draft else "rendered-with-voice"
    cr = critic.check(store.read_text(CAPTION))
    cr["scope"] = "text-only"
    cr["text_decision"] = cr.pop("decision")
    cr["decision"] = "نص فقط — ليس قرار نشر"
    pub = publication_readiness(spec, report, cr)
    report["publication"] = pub
    cr["publication"] = pub
    store.write_json(RENDER_REPORT, report)
    store.write_json(CRITIC_REPORT, cr)
    mem["status"] = report["status"]
    mem["artifacts"]["video"] = _rel(video)
    mem["artifacts"]["render_report"] = _rel(store.path(RENDER_REPORT))
    mem["artifacts"]["critic_report"] = _rel(store.path(CRITIC_REPORT))
    entry.update({"video": _rel(video), "sha256": sha, "status": mem["status"]})
    store.write_json(MEMORY, mem)
    store.snapshot(mem["current_version"])
    store.append_event("rendered", {"version": mem["current_version"], "video": _rel(video),
                                     "qa_pass": report["pass"], "sha256": sha,
                                     "publication_ready": pub["ready"]})
    return {"render": {**result, "sha256": sha}, "qa": report, "video": video}


def prove_relocation(project_id: str, projects_root: str = PROJECTS) -> dict:
    proj = load_project(project_id, projects_root)
    store, mem = proj["store"], proj["memory"]
    entry = _version_entry(mem, mem["current_version"])
    expected_sha = entry.get("sha256")
    with tempfile.TemporaryDirectory(prefix="cd-relocation-") as td:
        dest_root = os.path.join(td, os.path.basename(MARKETING_ROOT))
        shutil.copytree(MARKETING_ROOT, dest_root)
        copied_spec = os.path.join(dest_root, os.path.relpath(store.path(SPEC), MARKETING_ROOT))
        copied_engine = os.path.join(dest_root, os.path.relpath(os.path.join(ROOT, "engine"), MARKETING_ROOT))
        out = os.path.join(td, "relocated.mp4")
        r = subprocess.run([sys.executable, os.path.join(copied_engine, "reel_build.py"),
                            "--spec", copied_spec, "--out", out], cwd=td,
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("فشل الرندر من المسار المنقول:\n" + r.stderr[-1200:])
        sha = _sha256(out, td)
        report = {"project_id": store.project_id, "version": mem["current_version"],
                  "render_stdout": r.stdout.strip(), "sha256": sha,
                  "expected_sha256": expected_sha,
                  "identical_to_original": bool(expected_sha and sha == expected_sha),
                  "spec_relative": True}
    store.write_json(RELOCATION_REPORT, report)
    mem["artifacts"]["relocation_report"] = _rel(store.path(RELOCATION_REPORT))
    mem["updated_at"] = _now()
    store.write_json(MEMORY, mem)
    store.append_event("relocation-proven", {"identical": report["identical_to_original"], "sha256": sha})
    return report


def migrate_legacy_project(project_id: str, projects_root: str = PROJECTS) -> dict:
    store = ProjectStore(project_id, projects_root)
    mem = store.read_json(MEMORY)
    if mem.get("schema_version") == 2:
        return mem
    plan = store.read_json(PLAN)
    video_rel = mem.get("artifacts", {}).get("video")
    sha = None
    if video_rel:
        vp = os.path.join(REPO, video_rel)
        if os.path.isfile(vp):
            sha = _sha256(vp, REPO)
    mem["schema_version"] = 2
    mem["current_version"] = 1
    mem["versions"] = [{"version": 1, "created_at": mem.get("created_at", _now()),
                        "source": "legacy-migration", "instruction": None,
                        "status": mem.get("status", "planned"),
                        "scene_ids": plan.get("selected_scene_ids", []),
                        "hook": plan.get("schedule", {}).get("hook"),
                        "video": video_rel, "sha256": sha,
                        "snapshot": "versions/v0001"}]
    mem.setdefault("revisions", [])
    store.write_json(MEMORY, mem)
    store.snapshot(1)
    store.append_event("migrated", {"schema_version": 2, "sha256": sha})
    return mem


def main():
    ap = argparse.ArgumentParser(description="Creative Director v1 — brief/JSON → validated plan → render")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan"); p.add_argument("request"); p.add_argument("--project-id")
    p = sub.add_parser("apply-creative"); p.add_argument("project_id")
    p = sub.add_parser("render"); p.add_argument("project_id"); p.add_argument("--force", action="store_true")
    p = sub.add_parser("attach-voice"); p.add_argument("project_id")
    p.add_argument("--approval-note", required=True); p.add_argument("--profile-id", default="ar-eg-calm-confident")
    p = sub.add_parser("revise"); p.add_argument("project_id"); p.add_argument("instruction", nargs="?")
    p = sub.add_parser("rollback"); p.add_argument("project_id"); p.add_argument("version", type=int)
    p = sub.add_parser("show"); p.add_argument("project_id")
    p = sub.add_parser("prove-relocation"); p.add_argument("project_id")
    p = sub.add_parser("migrate"); p.add_argument("project_id")
    a = ap.parse_args()
    if a.cmd == "plan":
        r = create_project(a.request, a.project_id)
        print(json.dumps({"project_dir": r["project_dir"], "scene_ids": r["plan"]["selected_scene_ids"],
                          "duration": r["brief"]["duration_sec"], "status": r["memory"]["status"]},
                         ensure_ascii=False, indent=2))
    elif a.cmd == "apply-creative":
        r = apply_creative(a.project_id)
        print(json.dumps({"version": r["version"], "scene_ids": r["plan"]["selected_scene_ids"]}, ensure_ascii=False))
    elif a.cmd == "render":
        r = render_project(a.project_id, force=a.force)
        print(json.dumps(r, ensure_ascii=False, indent=2))
    elif a.cmd == "attach-voice":
        attach_voice(a.project_id, a.approval_note, profile_id=a.profile_id)
        print("تم إرفاق الصوت بعد مطابقة التفريغ البشري وقياس الطاقة")
    elif a.cmd == "revise":
        r = revise_project(a.project_id, a.instruction)
        print(json.dumps({"version": r["version"], "scene_ids": r["plan"]["selected_scene_ids"]}, ensure_ascii=False))
    elif a.cmd == "rollback":
        mem = rollback_project(a.project_id, a.version)
        print(json.dumps({"current_version": mem["current_version"], "status": mem["status"]}, ensure_ascii=False))
    elif a.cmd == "show":
        proj = load_project(a.project_id)
        print(json.dumps(proj["memory"], ensure_ascii=False, indent=2))
    elif a.cmd == "prove-relocation":
        r = prove_relocation(a.project_id)
        print(json.dumps(r, ensure_ascii=False, indent=2))
    elif a.cmd == "migrate":
        mem = migrate_legacy_project(a.project_id)
        print(json.dumps({"current_version": mem["current_version"], "schema_version": mem["schema_version"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()

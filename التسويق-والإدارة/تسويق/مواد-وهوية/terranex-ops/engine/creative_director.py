#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Creative Director v1 — من طلب عربي مصري إلى خطة إنتاج قابلة للتنفيذ.

ليس نموذج لغة عامًا ولا يدّعي فهمًا مفتوحًا: محلل قواعد محدد بالموضوعات المدعومة،
يختار من scene-library/index.json فقط، ويولّد spec لـreel_build. كل توقيت مصدر
مشتق من الفهرس (مشهد كامل أو excerpt محسوب داخل حدوده) — لا توقيتات مختلقة.

المخرجات لكل مشروع (تحت output/creative-projects/<id>/):
  brief.json, plan.json, spec.json, storyboard.png, caption.txt,
  memory.json, decisions.jsonl, render-report.json

الصوت: لا يولّد هذا المحرك صوتًا. يرفق ملفًا معتمدًا عبر attach-voice ويقيس
حدود الجمل بالطاقة لربط الكابشنات بالصوت الفعلي. بدون ملف معتمد = مسودة بصرية
صامتة موسومة بوضوح، وليست إعلانًا نهائيًا.
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
import tempfile
from datetime import datetime, timezone

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

REPO = SL.REPO
MARKETING_ROOT = R.MARKETING_ROOT
PROJECTS = os.path.join(ROOT, "output", "creative-projects")
INDEX_PATH = SL.INDEX
PERSONAS = os.path.join(ROOT, "context", "personas.json")
TOL = 0.05

SUPPORTED_TOPICS = ("field-followup", "feeding", "weight")

# أدوار السيناريو المدعومة. الوسوم تشير إلى فهرس المشاهد الحقيقي؛ لا scene_id مكتوب هنا.
BEATS = {
    "field-followup": [
        {"role": "establish", "tags": {"sheep"}, "weight": 1.0, "short_bonus": True,
         "text": "رأس حقيقي… مش مجرد صورة.",
         "motion": "لقطة قريبة ثابتة؛ دخول هادئ للنص فقط."},
        {"role": "followup", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "بنتابع الحيوانات على أرض الواقع.",
         "motion": "لقطة متابعة عن قرب؛ شريط إثبات يغطي العلامة المحروقة."},
        {"role": "herd", "tags": {"cows"}, "weight": 1.2, "short_bonus": True,
         "text": "من الحظيرة…",
         "motion": "لقطة واسعة للقطيع؛ انتقال قطع بسيط."},
        {"role": "feeding", "tags": {"feeding"}, "weight": 1.5,
         "text": "للتغذية…",
         "motion": "لقطة تغذية أقرب؛ إبقاء الحيوان داخل الكادر."},
        {"role": "farm", "tags": {"irrigation"}, "weight": 1.2,
         "text": "وللمزرعة.",
         "motion": "لقطة ري/محصول كسياق للمزرعة؛ لا ادعاء بفحص بيطري."},
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
         "text": "الوزن الحقلي… زي ما هو.", "motion": "لقطة الوزن الحقلي؛ لا ادعاء بميزان واضح إن لم يظهر."},
        {"role": "feeding", "tags": {"feeding"}, "weight": 1.5,
         "text": "وتغذية… قبل وبعدها.", "motion": "لقطة تغذية."},
        {"role": "followup-close", "tags": {"animal", "person-hand"}, "weight": 3.0,
         "text": "متابعة وتوثيق… خطوة بخطوة.", "motion": "زاوية وزن أخرى."},
    ],
}


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _rel(path: str, base: str = REPO) -> str:
    return os.path.relpath(os.path.abspath(path), base).replace(os.sep, "/")


def _read_json(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


_AR_DIGITS = str.maketrans({chr(0x0660+i): str(i) for i in range(10)})
_AR_DIGITS.update({chr(0x06F0+i): str(i) for i in range(10)})
_WORD_NUM = {"عشرة": 10, "عشر": 10, "خمستاشر": 15, "خمسة عشر": 15, "عشرين": 20,
             "ثلاثين": 30, "تلاتين": 30, "اربعة": 4, "أربعة": 4, "خمسة": 5}


def _latin_digits(s: str) -> str:
    return s.translate(_AR_DIGITS)


def parse_brief(text: str) -> dict:
    """استخراج محدود ومعلن. ما لا يُذكر صراحةً يُسجّل كافتراض، لا كحقيقة."""
    raw = text.strip()
    if not raw:
        raise ValueError("الطلب فارغ")
    n = SL._norm(_latin_digits(raw))
    warnings, assumptions = [], []

    dur = None
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:ثانية|ثواني|ث|ثانيةً|second|seconds|sec)", n)
    if m:
        dur = float(m.group(1))
    else:
        for w, v in _WORD_NUM.items():
            if SL._norm(w) in n and re.search(r"ثاني|ثواني|ث", n):
                dur = float(v)
                break
    if dur is None:
        raise ValueError("المدة غير محددة — اكتب مثلًا «20 ثانية»")
    if not (3 <= dur <= 120):
        raise ValueError("المدة المطلوبة خارج النطاق المدعوم (3–120 ثانية)")

    animal = any(w in n for w in ("حيوان", "حيوانات", "خروف", "خراف", "غنم", "بقر", "ابقار", "ضاني", "رأس"))
    followup = any(w in n for w in ("متابع", "بنتابع", "ارض الواقع", "ار الواقع", "المزرعه", "المزرعة", "توثيق"))
    feeding = any(w in n for w in ("تغذيه", "تغذية", "علف", "اكل", "أكل"))
    weight = any(w in n for w in ("وزن", "ميزان", "يتوزن", "الميزان"))
    if weight:
        topic = "weight"
    elif feeding and not followup:
        topic = "feeding"
    elif animal and followup:
        topic = "field-followup"
    elif feeding:
        topic = "feeding"
    elif animal or followup:
        topic = "field-followup"
    else:
        raise ValueError("الموضوع غير مدعوم في v1 — المدعوم: متابعة الحيوانات/التغذية/الوزن الحقلي")

    audience = None
    if any(w in n for w in ("مستثمر", "مستثمرين", "استثمار")):
        audience = "مهتمون بالاستثمار الحيواني"
    elif any(w in n for w in ("اصحاب اعمال", "أصحاب أعمال", "تجار", "تاجر")):
        audience = "أصحاب أنشطة وتجار"
    elif any(w in n for w in ("عائلات", "عائلة", "مغترب")):
        audience = "عائلات ومغتربون"
    if audience is None:
        audience = "جمهور عام مهتم بالمزرعة والمتابعة الحقيقية"
        assumptions.append("الجمهور غير مذكور صراحةً؛ استُخدم جمهور عام بدون استهداف استثماري أو وعود.")

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

    cta = None
    if any(w in n for w in ("تواصل", "واتساب", "كلمنا", "اتصل", "تواصلوا", "رسالة")):
        cta = {"type": "contact", "text": f"للتفاصيل… كلمنا على واتساب.", "phone": B.PHONE}

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
    return _read_json(index_path)


def validate_index(idx: dict, repo: str = REPO, check_git: bool = True) -> list:
    issues = []
    sources = idx.get("sources", {})
    scenes = idx.get("scenes", [])
    if not sources:
        issues.append("الفهرس بلا مصادر")
    seen = set()
    for sid, s in sources.items():
        p = s.get("path", "")
        if not p or os.path.isabs(p) or ".." in p.split("/"):
            issues.append(f"{sid}: مسار مصدر غير نسبي/غير آمن: {p}")
            continue
        fp = os.path.join(repo, p)
        if not os.path.isfile(fp):
            issues.append(f"{sid}: المصدر غير موجود: {p}")
            continue
        if s.get("sha256") and _sha256(fp) != s["sha256"]:
            issues.append(f"{sid}: SHA-256 لا يطابق الفهرس")
        if check_git:
            r = subprocess.run(["git", "ls-files", "--error-unmatch", p], cwd=repo,
                               capture_output=True, text=True)
            if r.returncode != 0:
                issues.append(f"{sid}: المصدر غير متتبع في git — غير قابل للاستعادة تلقائيًا")
            else:
                r2 = subprocess.run(["git", "cat-file", "-e", f"HEAD:{p}"], cwd=repo,
                                    capture_output=True, text=True)
                if r2.returncode != 0:
                    issues.append(f"{sid}: المصدر غير موجود في HEAD — لن يُستعاد من git")
    for sc in scenes:
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


def _waterfill(weights: list, caps: list, budget: float, mins: list | None = None) -> list:
    n = len(weights)
    mins = mins or [0.0] * n
    if budget + 1e-9 < sum(mins):
        raise ValueError("المدة المطلوبة أقصر من الحد الأدنى للمشاهد المختارة")
    if budget > sum(caps) + 1e-9:
        raise ValueError("المدة المطلوبة تتجاوز إجمالي المشاهد المتاحة بدون تكرار")
    alloc = [0.0] * n
    remaining = budget
    active = set(range(n))
    while active:
        tw = sum(weights[i] for i in active)
        clamped = []
        for i in sorted(active):
            share = remaining * weights[i] / tw
            if share >= caps[i] - 1e-9:
                alloc[i] = caps[i]
                clamped.append(i)
        if clamped:
            for i in clamped:
                remaining -= alloc[i]
                active.remove(i)
        else:
            for i in active:
                alloc[i] = remaining * weights[i] / tw
            break
    # ضبط التقريب على آخر عنصر قابل للتعديل بدون كسر الحدود.
    diff = round(budget - sum(alloc), 3)
    for i in range(n - 1, -1, -1):
        new = round(alloc[i] + diff, 3)
        if mins[i] - 1e-9 <= new <= caps[i] + 1e-9:
            alloc[i] = new
            break
    return [round(x, 3) for x in alloc]


def select_and_schedule(idx: dict, brief: dict) -> dict:
    topic = brief["topic"]
    beats = BEATS[topic]
    endcard = 3.0 if brief.get("cta") else 0.0
    budget = round(brief["duration_sec"] - endcard, 3)
    if budget <= 0:
        raise ValueError("المدة لا تتسع للخاتمة")
    scenes = [s for s in idx["scenes"] if _usable(s)]
    used, used_sources, used_sig = set(), {}, set()
    chosen = []
    for beat in beats:
        best, best_score = None, -1e9
        for sc in scenes:
            sid = sc["scene_id"]
            if sid in used:
                continue
            tags = set(sc["tags"])
            if not beat["tags"] <= tags:
                continue
            dur = sc["end"] - sc["start"]
            score = float(sc.get("quality", 0.5)) * 4
            score += len(tags & beat["tags"])
            score -= 0.3 * used_sources.get(sc["source_id"], 0)
            sig = tuple(sorted(tags))
            if sig in used_sig:
                score -= 0.3
            if beat.get("short_bonus") and dur < 2.0:
                score += 1.5
            if score > best_score:
                best, best_score = sc, score
        if best is None:
            raise ValueError(f"لا يوجد مشهد صالح للدور {beat['role']} في الفهرس")
        used.add(best["scene_id"])
        used_sources[best["source_id"]] = used_sources.get(best["source_id"], 0) + 1
        used_sig.add(tuple(sorted(best["tags"])))
        chosen.append((beat, best))

    caps = [sc["end"] - sc["start"] for _, sc in chosen]
    weights = [b["weight"] for b, _ in chosen]
    mins = [min(1.0, c) for c in caps]
    durations = _waterfill(weights, caps, budget, mins)

    timeline, cursor = [], 0.0
    for (beat, sc), d in zip(chosen, durations):
        full = sc["end"] - sc["start"]
        if d >= full - 1e-9:
            a, b = sc["start"], sc["end"]
            policy = "full-indexed-scene"
        else:
            center = (sc["start"] + sc["end"]) / 2
            a = round(max(sc["start"], center - d / 2), 3)
            b = round(a + d, 3)
            if b > sc["end"] + 1e-9:
                b = sc["end"]
                a = round(b - d, 3)
            policy = "centered-excerpt-within-indexed-scene"
        timeline.append({
            "scene_id": sc["scene_id"], "source_id": sc["source_id"], "role": beat["role"],
            "source_start": a, "source_end": b, "planned_duration": round(b - a, 3),
            "timeline_start": round(cursor, 3), "timeline_end": round(cursor + (b - a), 3),
            "excerpt_policy": policy, "indexed_scene_start": sc["start"], "indexed_scene_end": sc["end"],
            "text": beat["text"], "motion": beat["motion"], "tags": sc["tags"],
            "quality": sc.get("quality"), "preview": sc["preview"], "treatment": sc.get("treatment", {}),
        })
        cursor += b - a

    hook = "الحيوانات… متابعة حقيقية."
    hook_sec = min(2.0, round(brief["duration_sec"] * 0.1, 3))
    voice_phrases = [{"role": t["role"], "text": t["text"]} for t in timeline]
    if brief.get("cta"):
        voice_phrases.append({"role": "cta", "text": brief["cta"]["text"]})
    # نوافذ قراءة تقديرية للصمت فقط؛ عند إرفاق صوت تُستبدل بقياس الطاقة الفعلي.
    voice_budget = round(brief["duration_sec"] - hook_sec, 3)
    wcounts = [max(1, len(p["text"].split())) for p in voice_phrases]
    pdurs = _waterfill([float(w) for w in wcounts], [voice_budget] * len(wcounts),
                       voice_budget, [min(1.0, voice_budget / len(wcounts))] * len(wcounts))
    vc = hook_sec
    for p, d in zip(voice_phrases, pdurs):
        p["from"], p["to"] = round(vc, 3), round(vc + d, 3)
        vc += d

    return {
        "topic": topic, "duration_sec": brief["duration_sec"], "endcard_sec": endcard,
        "hook": hook, "hook_sec": hook_sec, "content_budget_sec": budget,
        "shots": timeline, "voice_phrases": voice_phrases,
        "caption_timing_source": "reading-budget-estimate",
        "audio_status": "silent-visual-draft",
    }


def build_spec(idx: dict, brief: dict, sched: dict, spec_path: str) -> dict:
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
    captions = [{"from": p["from"], "to": p["to"], "text": p["text"]}
                for p in sched["voice_phrases"]]
    silent_disclosure = "مسودة بصرية للمراجعة · بدون تعليق صوتي"
    spec = {
        "title": f"creative-director-{brief['topic']}-{int(brief['duration_sec'])}s",
        "template": "corporate-no-face", "on_screen_persons": [], "consent_persons": [],
        "clips": clips, "hook": sched["hook"], "hook_sec": sched["hook_sec"],
        "captions": captions, "endcard_sec": sched["endcard_sec"],
        "endcard": {"headline": "ملك حقيقي", "subtitle": "ومتابعة بعينك",
                    "cta": f"واتساب {B.PHONE}" if brief.get("cta") else "TerraNex",
                    "disclosure": silent_disclosure},
        "visual_draft": True,
        "audio": {"original_gain": 0.12, "ambient_from": 0, "duck": True, "lufs": -15},
        "_library_derived": True,
        "_scene_ids": [c["scene_id"] for c in clips],
        "_caption_timing_source": sched["caption_timing_source"],
    }
    _write_json(spec_path, spec)
    return spec


def validate_plan(idx: dict, brief: dict, sched: dict, spec: dict) -> None:
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    if len(set(sched["shots"][i]["scene_id"] for i in range(len(sched["shots"])))) != len(sched["shots"]):
        raise ValueError("مشهد مكرر في الخطة")
    for shot, clip in zip(sched["shots"], spec["clips"]):
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
    total = sum(c["end"] - c["start"] for c in spec["clips"]) + spec["endcard_sec"]
    if total > brief["duration_sec"] + TOL:
        raise ValueError(f"الخطة تتجاوز المدة المطلوبة: {total:.2f} > {brief['duration_sec']}")
    texts = [spec["hook"]] + [c["text"] for c in spec["captions"]]
    texts += list(spec.get("endcard", {}).values())
    joined = "\n".join(texts)
    cr = critic.check(joined)
    if cr["hard"]:
        raise ValueError("نص الخطة يخالف قواعد الالتزام: " + "; ".join(h["code"] for h in cr["hard"]))


def _storyboard_png(idx: dict, brief: dict, sched: dict, out: str) -> str:
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


def create_project(request: str, project_id: str | None = None, projects_root: str = PROJECTS,
                   index_path: str = INDEX_PATH) -> dict:
    brief = parse_brief(request)
    idx = load_index(index_path)
    issues = validate_index(idx)
    if issues:
        raise ValueError("فهرس المشاهد غير قابل للاسترجاع:\n" + "\n".join(issues))
    if not project_id:
        project_id = "cd-" + hashlib.sha256(request.encode("utf-8")).hexdigest()[:10]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,80}", project_id):
        raise ValueError("project_id غير آمن")
    pdir = os.path.join(projects_root, project_id)
    os.makedirs(pdir, exist_ok=True)
    ranked = rank_candidates(idx, brief)
    sched = select_and_schedule(idx, brief)
    spec_path = os.path.join(pdir, "spec.json")
    spec = build_spec(idx, brief, sched, spec_path)
    validate_plan(idx, brief, sched, spec)
    sb = _storyboard_png(idx, brief, sched, os.path.join(pdir, "storyboard.png"))
    caption = "\n".join([sched["hook"]] + [p["text"] for p in sched["voice_phrases"]])
    caption += "\n\n#TerraNex #متابعة_حقيقية #مزرعة"
    with open(os.path.join(pdir, "caption.txt"), "w", encoding="utf-8") as f:
        f.write(caption + "\n")
    plan = {"brief": brief, "search_ranking": ranked[:20], "schedule": sched,
            "selected_scene_ids": [s["scene_id"] for s in sched["shots"]],
            "spec": _rel(spec_path), "storyboard": _rel(sb)}
    _write_json(os.path.join(pdir, "brief.json"), brief)
    _write_json(os.path.join(pdir, "plan.json"), plan)
    memory = {
        "schema_version": 1, "project_id": project_id, "created_at": _now(), "updated_at": _now(),
        "base_commit": subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True).stdout.strip(),
        "branch": subprocess.run(["git", "branch", "--show-current"], cwd=REPO, capture_output=True, text=True).stdout.strip(),
        "status": "planned", "request": request, "brief": brief, "schedule": sched,
        "selected_scene_ids": plan["selected_scene_ids"],
        "artifacts": {"brief": _rel(os.path.join(pdir, "brief.json")),
                      "plan": _rel(os.path.join(pdir, "plan.json")),
                      "spec": _rel(spec_path), "storyboard": _rel(sb),
                      "caption": _rel(os.path.join(pdir, "caption.txt"))},
        "decisions": ["استخدام فهرس المشاهد الحقيقي فقط", "مسودة بصرية صامتة حتى يتوفر تعليق معتمد"],
        "revisions": [],
    }
    _write_json(os.path.join(pdir, "memory.json"), memory)
    _append_event(pdir, "created", {"project_id": project_id, "scene_ids": plan["selected_scene_ids"]})
    return {"project_dir": pdir, "brief": brief, "plan": plan, "spec": spec, "memory": memory}


def _append_event(pdir: str, kind: str, data: dict) -> None:
    with open(os.path.join(pdir, "decisions.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps({"at": _now(), "kind": kind, **data}, ensure_ascii=False) + "\n")


def load_project(project_id: str, projects_root: str = PROJECTS) -> dict:
    pdir = os.path.join(projects_root, project_id)
    mem = _read_json(os.path.join(pdir, "memory.json"))
    plan = _read_json(os.path.join(pdir, "plan.json"))
    spec = _read_json(os.path.join(pdir, "spec.json"))
    return {"project_dir": pdir, "memory": mem, "plan": plan, "spec": spec}


def revise_project(project_id: str, note: str, projects_root: str = PROJECTS) -> dict:
    proj = load_project(project_id, projects_root)
    pdir = proj["project_dir"]
    mem = proj["memory"]
    mem["revisions"].append({"at": _now(), "note": note})
    mem["updated_at"] = _now()
    _write_json(os.path.join(pdir, "memory.json"), mem)
    _append_event(pdir, "revision", {"note": note})
    return mem


def measure_phrases(audio_path: str, expected: int, thr_db: float = -38.0, merge_gap: float = 0.30) -> list:
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    p = subprocess.run([ff, "-v", "error", "-i", audio_path, "-ac", "1", "-ar", "16000",
                        "-f", "s16le", "-"], capture_output=True)
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


def attach_voice(project_id: str, audio_path: str, approval_note: str,
                 projects_root: str = PROJECTS, profile_id: str = "ar-eg-calm-confident") -> dict:
    proj = load_project(project_id, projects_root)
    pdir, mem, plan, spec = proj["project_dir"], proj["memory"], proj["plan"], proj["spec"]
    personas = _read_json(PERSONAS)
    bank = personas.get("voice_bank", {}).get("default_narrator", {})
    if profile_id != bank.get("id"):
        raise ValueError("الصوت المطلوب ليس الصوت المثبت في الهوية")
    if not approval_note.strip():
        raise ValueError("يلزم توثيق إذن استخدام الصوت")
    audio_path = os.path.abspath(audio_path)
    if not os.path.isfile(audio_path):
        raise ValueError("ملف الصوت غير موجود")
    dest = os.path.join(pdir, "voice" + os.path.splitext(audio_path)[1])
    if os.path.abspath(dest) != audio_path:
        with open(audio_path, "rb") as src, open(dest, "wb") as out:
            out.write(src.read())
    phrases = plan["schedule"]["voice_phrases"]
    windows = measure_phrases(dest, len(phrases))
    total = sum(c["end"] - c["start"] for c in spec["clips"]) + spec["endcard_sec"]
    if windows[-1][1] > total + TOL:
        raise ValueError("الصوت أطول من الفيديو — لا قصّ تلقائي للكلام")
    # ربط الكابشنات بالطاقة الفعلية، ليس بمدة المشهد.
    padded = [(max(0.0, x - 0.05), min(total, y + 0.05)) for x, y in windows]
    spec["captions"] = [{"from": x, "to": y, "text": p["text"]} for p, (x, y) in zip(phrases, padded)]
    spec["hook_sec"] = min(spec.get("hook_sec", 0.0), padded[0][0])
    spec["visual_draft"] = False
    spec["endcard"]["disclosure"] = "تعليق صوتي · مدعوم بإضافات AI"
    spec["voice"] = {"path": os.path.relpath(dest, pdir).replace(os.sep, "/"),
                     "profile_id": profile_id, "sha256": _sha256(dest),
                     "timing_source": "measured-energy", "approval_note": approval_note}
    spec["_caption_timing_source"] = "measured-energy"
    _write_json(os.path.join(pdir, "spec.json"), spec)
    plan["schedule"]["caption_timing_source"] = "measured-energy"
    plan["schedule"]["audio_status"] = "voice-attached"
    for p, (x, y) in zip(phrases, padded):
        p["from"], p["to"] = x, y
    _write_json(os.path.join(pdir, "plan.json"), plan)
    mem["status"] = "voice-attached"
    mem["updated_at"] = _now()
    mem["artifacts"]["voice"] = _rel(dest)
    mem["decisions"].append("إرفاق صوت معتمد وربط الكابشنات بقياس الطاقة الفعلي")
    _write_json(os.path.join(pdir, "memory.json"), mem)
    _append_event(pdir, "voice-attached", {"sha256": spec["voice"]["sha256"], "phrases": len(phrases)})
    return spec


def render_project(project_id: str, out_path: str | None = None, projects_root: str = PROJECTS) -> dict:
    proj = load_project(project_id, projects_root)
    pdir, mem, spec = proj["project_dir"], proj["memory"], proj["spec"]
    spec_path = os.path.join(pdir, "spec.json")
    voice = None
    if spec.get("voice"):
        voice = os.path.normpath(os.path.join(pdir, spec["voice"]["path"]))
    if out_path is None:
        day = datetime.now(timezone.utc).date().isoformat()
        out_path = os.path.join(MARKETING_ROOT, "فيديوهات-المنتجة", day, f"{project_id}.mp4")
    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    result = R.build(spec_path, voice, out_path)
    visual_draft = bool(spec.get("visual_draft"))
    report = qa_video.qa(out_path, "reels", visual_draft=visual_draft)
    expected = mem["brief"]["duration_sec"]
    if abs(result["duration"] - expected) > 0.1:
        report["warns"].append(f"المدة الفعلية {result['duration']}ث تختلف عن المطلوبة {expected}ث")
    report["expected_duration_sec"] = expected
    report["visual_draft"] = visual_draft
    report["status"] = "visual-draft" if visual_draft else "rendered-with-voice"
    _write_json(os.path.join(pdir, "render-report.json"), report)
    cap_path = os.path.join(pdir, "caption.txt")
    cr = {}
    if os.path.isfile(cap_path):
        with open(cap_path, encoding="utf-8") as f:
            cr = critic.check(f.read())
        _write_json(os.path.join(pdir, "critic-report.json"), cr)
    mem["status"] = report["status"]
    mem["updated_at"] = _now()
    mem["artifacts"]["video"] = _rel(out_path)
    mem["artifacts"]["render_report"] = _rel(os.path.join(pdir, "render-report.json"))
    if cr:
        mem["artifacts"]["critic_report"] = _rel(os.path.join(pdir, "critic-report.json"))
    _write_json(os.path.join(pdir, "memory.json"), mem)
    _append_event(pdir, "rendered", {"video": _rel(out_path), "qa_pass": report["pass"],
                                     "duration": result["duration"], "visual_draft": visual_draft})
    return {"render": result, "qa": report, "video": out_path}


def prove_relocation(project_id: str, projects_root: str = PROJECTS,
                     original_video: str | None = None) -> dict:
    """ينسخ شجرة التسويق إلى مسار مؤقت مختلف ويعيد الرندر من هناك بنفس الـspec النسبي.
    يثبت أن المشروع لا يعتمد على /home/user/Terranex أو CWD الأصلي."""
    proj = load_project(project_id, projects_root)
    pdir, mem = proj["project_dir"], proj["memory"]
    spec_abs = os.path.join(REPO, mem["artifacts"]["spec"])
    if original_video is None and mem.get("artifacts", {}).get("video"):
        original_video = os.path.join(REPO, mem["artifacts"]["video"])
    with tempfile.TemporaryDirectory(prefix="cd-relocation-") as td:
        dest_root = os.path.join(td, os.path.basename(MARKETING_ROOT))
        shutil.copytree(MARKETING_ROOT, dest_root)
        copied_spec = os.path.join(dest_root, os.path.relpath(spec_abs, MARKETING_ROOT))
        copied_engine = os.path.join(dest_root, os.path.relpath(os.path.join(ROOT, "engine"), MARKETING_ROOT))
        out = os.path.join(td, "relocated.mp4")
        r = subprocess.run([sys.executable, os.path.join(copied_engine, "reel_build.py"),
                            "--spec", copied_spec, "--out", out], cwd=td,
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("فشل الرندر من المسار المنقول:\n" + r.stderr[-1200:])
        sha = _sha256(out)
        orig_sha = _sha256(original_video) if original_video and os.path.isfile(original_video) else None
        report = {"project_id": project_id, "relocated_root": dest_root,
                  "render_stdout": r.stdout.strip(), "sha256": sha,
                  "original_sha256": orig_sha,
                  "identical_to_original": (orig_sha is not None and sha == orig_sha),
                  "cwd": td, "spec_relative": True}
    _write_json(os.path.join(pdir, "relocation-report.json"), report)
    mem["artifacts"]["relocation_report"] = _rel(os.path.join(pdir, "relocation-report.json"))
    mem["updated_at"] = _now()
    _write_json(os.path.join(pdir, "memory.json"), mem)
    _append_event(pdir, "relocation-proven", {"identical": report["identical_to_original"], "sha256": sha})
    return report


def main():
    ap = argparse.ArgumentParser(description="Creative Director v1 — طلب عربي → خطة → spec → رندر")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan"); p.add_argument("request"); p.add_argument("--project-id")
    p = sub.add_parser("render"); p.add_argument("project_id"); p.add_argument("--out")
    p = sub.add_parser("attach-voice"); p.add_argument("project_id"); p.add_argument("audio")
    p.add_argument("--approval-note", required=True); p.add_argument("--profile-id", default="ar-eg-calm-confident")
    p = sub.add_parser("revise"); p.add_argument("project_id"); p.add_argument("note")
    p = sub.add_parser("show"); p.add_argument("project_id")
    p = sub.add_parser("prove-relocation"); p.add_argument("project_id"); p.add_argument("--video")
    a = ap.parse_args()
    if a.cmd == "plan":
        r = create_project(a.request, a.project_id)
        print(json.dumps({"project_dir": r["project_dir"], "scene_ids": r["plan"]["selected_scene_ids"],
                          "duration": r["brief"]["duration_sec"], "status": r["memory"]["status"]},
                         ensure_ascii=False, indent=2))
    elif a.cmd == "render":
        r = render_project(a.project_id, a.out)
        print(json.dumps(r, ensure_ascii=False, indent=2))
    elif a.cmd == "attach-voice":
        attach_voice(a.project_id, a.audio, a.approval_note, profile_id=a.profile_id)
        print("تم إرفاق الصوت وربط الكابشنات بالقياس الفعلي")
    elif a.cmd == "revise":
        revise_project(a.project_id, a.note)
        print("تم تسجيل المراجعة")
    elif a.cmd == "show":
        proj = load_project(a.project_id)
        print(json.dumps(proj["memory"], ensure_ascii=False, indent=2))
    elif a.cmd == "prove-relocation":
        r = prove_relocation(a.project_id, original_video=a.video)
        print(json.dumps(r, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

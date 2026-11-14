#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""reel_build.py — بناء ريل 9:16 من لقطات حقيقية بنظام الهوية الثابت (19/10).

القواعد المثبتة هنا (لا تُكسر):
  B9  — لا ذكر للمدينة افتراضيًا؛ حملة محلية موثقة فقط يمكنها ذكر نطاقها الجغرافي.
  B4  — لقطات حقيقية فقط. AI زخرفة فقط (screen) ولا يُستبدل أي فريم حقيقي.
  B10 — لا يظهر المالك/أي شخص على الشاشة إلا بإذن صريح في الـspec.
  العلامة المائية الرسمية (شعار + TerraNex) في مكان وحجم ثابتين في كل فريم.
  الكابشنات المترجمة من الصوت في شريط ثابت واحد بحدّ 6 كلمات/سطر.

  python engine/reel_build.py --spec spec.json [--voice vo.mp3] --out out.mp4
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand as B  # noqa: E402
import critic  # noqa: E402
import voice_identity as VI  # noqa: E402
from safe_paths import confine  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# جذر مساحة التسويق (تسويق/) — يُسمح بمراجعته بالمسارات النسبية بدل المسارات المطلقة القديمة.
MARKETING_ROOT = os.path.abspath(os.path.join(ROOT, "..", ".."))
PERSONAS = os.path.join(ROOT, "context", "personas.json")
W, H, FPS = 1080, 1920, 30
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp", ".bmp")

CAP_CY = 0.70           # منتصف شريط الكابشن — ثابت في كل الفيديو (داخل شريط الدليل)
BOTTOM_BAND = 0.870     # بداية الشريط السفلي الذي يغطي أي علامة محروقة في الفوتاج
CAP_MAX_WORDS = 6       # كلمات لكل سطر
CAP_FONT = 54


def _safe_input_path(path: str, *roots: str) -> str:
    """مسار إدخال آمن: موجود، لا يبدأ بشرطة (حقن خيارات ffmpeg)، وداخل أحد الجذور
    المسموحة بعد فكّ الروابط الرمزية (realpath) — يسدّ symlink-escape وpath traversal.

    يُرجع المسار الحقيقي (realpath) ليقرأ ffmpeg الملف المقصود فعليًا لا رابطًا خادعًا.
    """
    rp = os.path.realpath(path)
    if os.path.basename(rp).startswith("-") or os.path.basename(path).startswith("-"):
        raise SystemExit(f"unsafe input path (option injection): {path}")
    if not os.path.exists(rp):
        raise SystemExit(f"input not found: {path}")
    for r in roots:
        root = os.path.realpath(r)
        try:
            if rp == root or os.path.commonpath([rp, root]) == root:
                return confine(rp, root)
        except ValueError:
            continue
    raise SystemExit(f"input path outside allowed roots: {path}")


def _clip_vf(c: dict) -> str:
    """سلسلة فلاتر القصّ/الملء للقطة.

    الأولوية لحقل crop={top,bottom,left,right} (كنسب من المصدر): نقصّ منطقة العلامة
    المحروقة أولًا ثم نملأ 1080×1920 ونوسّط — يبقى الحيوان/الميزان في الكادر.
    إن غاب crop نرجع للسلوك القديم (hide_burnt_logo / crop_bottom_pct) توافقًا مع specs السابقة.
    """
    crop = c.get("crop")
    # crop={} صراحةً تعني «بلا قصّ لكن استخدم السلسلة الحديثة»؛ غياب المفتاح وحده يرجع للقديم.
    if crop is not None:
        ct = max(0.0, min(0.60, float(crop.get("top", 0.0))))
        cb = max(0.0, min(0.60, float(crop.get("bottom", 0.0))))
        cl = max(0.0, min(0.40, float(crop.get("left", 0.0))))
        cr = max(0.0, min(0.40, float(crop.get("right", 0.0))))
        kw = max(0.20, 1.0 - cl - cr)
        kh = max(0.20, 1.0 - ct - cb)
        cropf = f"crop=iw*{kw:.4f}:ih*{kh:.4f}:iw*{cl:.4f}:ih*{ct:.4f}"
        # sharpen=False ممنوع فيه أي تحسين حدّة صناعي (قرار مالك AD-1):
        # مواد واتساب مضغوطة أصلًا، والـunsharp يبرز بلوكات الضغط ولا يستعيد تفصيلًا مفقودًا.
        sharp = ",unsharp=5:5:0.5:5:5:0.0" if c.get("sharpen", True) else ""
        # flags=lanczos يعيد تحجيمًا أنظف من الافتراضي عند التكبير — ليس حدّة صناعية.
        sf = c.get("scale_flags")
        flags = f":flags={sf}" if sf in ("lanczos", "bicubic", "bilinear", "spline", "area") else ""
        return (f"{cropf},scale={W}:{H}:force_original_aspect_ratio=increase{flags},"
                f"crop={W}:{H}{sharp},fps={FPS},setsar=1")
    if c.get("hide_burnt_logo", True):
        cut = float(c.get("crop_bottom_pct", 0.34))
        fct = 1.0 / max(0.5, 1.0 - cut)
        return (f"scale={int(W*fct)}:{int(H*fct)}:force_original_aspect_ratio=increase,"
                f"crop={W}:{H}:0:0,fps={FPS},setsar=1")
    return (f"scale={W}:{H}:force_original_aspect_ratio=increase,"
            f"crop={W}:{H},fps={FPS},setsar=1")


def ff() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


# ---------------- بوابات ----------------
def _delivery_city_authorized(spec: dict | None) -> bool:
    """استثناء B9 لـAD08 موثق بسجل قرار مالك منظم.

    اسم allow_delivery_city قديم ومحفوظ للتوافق؛ لا يمنح تصريحًا بالتوصيل.
    """
    spec = spec or {}
    consent = (spec or {}).get("consent")
    if not isinstance(consent, dict):
        return False
    note = consent.get("delivery_city_approval_note", "")
    return critic.city_exception_authorized(
        allow_delivery_city=consent.get("allow_delivery_city") is True,
        campaign_scope=spec.get("campaign_scope", "general"),
        delivery_city_approval_note=note,
        track=spec.get("track", "general"),
        campaign_id=spec.get("ad_id"),
        owner_approval=consent.get("owner_approval"),
    )


def lint_text(text: str, allow_city: bool = False) -> None:
    """B9 — المدينة ممنوعة افتراضيًا إلا في حملات التوصيل المصرح بها نصًا من المالك."""
    if allow_city:
        return
    hits = [c for c in B.CITY_BAN if c in (text or "")]
    if hits:
        raise SystemExit(f"⛔ B9: ذكر المدينة «{hits[0]}» يحتاج campaign_local وموافقة موثقة.")


def require_consent(spec: dict) -> None:
    """B10 — أي شخص في الكادر لازم له إذن صريح. غياب الإذن = غياب الشخص."""
    with open(PERSONAS, encoding="utf-8") as f:
        data = json.load(f)
    consents = [c.strip() for c in spec.get("consent_persons", [])]
    known = {p["id"]: p for p in data["people"]}
    for pid in spec.get("on_screen_persons", []):
        p = known.get(pid)
        if p and p.get("on_screen") == "explicit-only" and pid not in consents:
            raise SystemExit(
                f"⛔ B10: «{p['name_ar']}» لا يظهر بدون إذن صريح.\n"
                f"   المطلوب: consent_persons: [\"{pid}\"] بعد طلب مكتوب منه في نفس الجلسة."
            )


# ---------------- طبقات ----------------
def topbar() -> Image.Image:
    """علامة مائية خفيفة أعلى الفريم (B11): تدرّج شفاف + الرمز وTerraNex بمكان/حجم ثابتين.

    بدل الشريط الصلب الثقيل: تعتيم متدرّج يتلاشى لأسفل حتى لا يحجب اللقطة.
    """
    th = 150
    lay = Image.new("RGBA", (W, th), (0, 0, 0, 0))
    grad = Image.new("L", (1, th))
    for y in range(th):
        grad.putpixel((0, y), int(150 * (1 - y / th) ** 1.5))
    scrim = Image.new("RGBA", (W, th), B.hex2rgb(B.C["bg_dark"]) + (255,))
    lay.paste(scrim, (0, 0), grad.resize((W, th)))
    d = ImageDraw.Draw(lay)
    emb = B.logo(96, "emblem")
    ey = (th - emb.height) // 2 - 6
    lay.alpha_composite(emb, (44, ey))
    B.text(d, (44 + emb.width + 18, th // 2 - 6), "TerraNex", B.font("black", 40),
           B.hex2rgb(B.C["cream"]) + (235,), anchor="lm", direction="ltr")
    B.text(d, (W - 44, th // 2 - 6), "استثمار حيواني", B.font("medium", 26),
           B.hex2rgb(B.C["gold"]) + (205,), anchor="rm")
    return lay


def bottom_band() -> Image.Image:
    """تدرّج سفلي خفيف لمنطقة الكابشن والـUI الآمنة — بدل الشريط المعتم الثقيل.

    العلامات المحروقة في الفوتاج تُقصّ الآن عبر crop، فلا حاجة لتغطية معتمة.
    """
    y0 = int(H * 0.58)
    h = H - y0
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    grad = Image.new("L", (1, h))
    for y in range(h):
        grad.putpixel((0, y), int(185 * (y / h) ** 1.7))
    band = Image.new("RGBA", (W, h), B.hex2rgb(B.C["bg_dark"]) + (255,))
    lay.paste(band, (0, y0), grad.resize((W, h)))
    return lay


def proofbar_layer() -> Image.Image:
    """شريط دليل سفلي (lower-third) للقطات التي تحمل علامة محروقة في منتصف الكادر.

    يغطّي منطقة العلامة («TerraNex LLC» عند ~63%) ويستضيف الكابشن، مع خط ذهبي رفيع.
    رأس الحيوان وفعل الوزن يبقيان ظاهرين فوق الشريط — لا القصّ ولا التمويه.
    """
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    top, bot = int(H * 0.56), int(H * 0.80)
    core0, core1 = int(H * 0.60), int(H * 0.76)   # معتم تمامًا فوق منطقة العلامة (~63%)
    h = bot - top
    grad = Image.new("L", (1, h))
    for y in range(h):
        yy = top + y
        if yy < core0:
            a = int(255 * ((yy - top) / (core0 - top)) ** 1.3)
        elif yy <= core1:
            a = 255
        else:
            a = int(255 * (1 - (yy - core1) / (bot - core1)) ** 1.3)
        grad.putpixel((0, y), a)
    bar = Image.new("RGBA", (W, h), B.hex2rgb(B.C["bg_dark"]) + (255,))
    lay.paste(bar, (0, top), grad.resize((W, h)))
    d = ImageDraw.Draw(lay)
    B.hairline(d, 0, W, core0, B.C["gold"], 2, 180)
    return lay


def ornament(size, opacity=0.55):
    p = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     "..", "assets", "ai-ornament-black.png"))
    if not os.path.exists(p):
        return None
    src = Image.open(p).convert("RGB")
    bb = src.convert("L").point(lambda v: 255 if v > 22 else 0).getbbox()
    if bb:
        src = src.crop(bb)
    src = src.resize(size, Image.LANCZOS)
    mask = src.convert("L").point(lambda v: 0 if v < 26 else min(255, int((v - 26) * 255 / 150)))
    mask = mask.filter(ImageFilter.GaussianBlur(0.4))
    lay = Image.new("RGBA", size, (0, 0, 0, 0))
    lay.paste(Image.new("RGB", size, B.hex2rgb(B.C["gold_hi"])), (0, 0),
              mask.point(lambda v: int(v * opacity)))
    return lay


def _balanced_lines(text: str, f, max_w: int) -> list:
    """سطر واحد إن اتسع، وإلا سطرين متوازنين (لا كلمة يتيمة في سطر لوحدها)."""
    if B.measure(text, f) <= max_w:
        return [text]
    words = text.split()
    best, best_w = None, None
    for k in range(1, len(words)):
        l1, l2 = " ".join(words[:k]), " ".join(words[k:])
        w1, w2 = B.measure(l1, f), B.measure(l2, f)
        if w1 <= max_w and w2 <= max_w:
            score = max(w1, w2)
            if best_w is None or score < best_w:
                best, best_w = [l1, l2], score
    return best or B.wrap(text, f, max_w, max_lines=2)


def hook_layer(text: str, allow_city: bool = False) -> Image.Image:
    lint_text(text, allow_city=allow_city)
    f = B.font("black", 88)
    lines = _balanced_lines(text, f, int(W * 0.86))
    tw = max(int(B.measure(l, f)) for l in lines)
    lh = int(f.size * 1.26)
    pw, ph = min(W - 56, tw + 80), len(lines) * lh + 52
    y0 = int(H * 0.295)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d0 = ImageDraw.Draw(img)
    d0.rounded_rectangle([(W - pw) // 2, y0, (W + pw) // 2, y0 + ph], radius=24,
                         fill=B.hex2rgb(B.C["bg_dark"]) + (165,))
    d = ImageDraw.Draw(img)
    y = y0 + 26 + lh // 2
    for ln in lines:
        B.text(d, (W // 2, y), ln, f, (255, 255, 255, 255), anchor="mm",
               stroke=3, stroke_fill=B.hex2rgb(B.C["green_deep"]) + (255,))
        y += lh
    return img


def cap_layer(text: str, cy: float | None = None, allow_city: bool = False) -> Image.Image:
    """شريط الكابشن المترجم — نفس المكان والحجم في كل سطر (لا عشوائية).

    cy اختياري على مستوى الـspec كله (لا لكل لقطة) لضبط الشريط الثابت مرة واحدة
    بحيث لا يغطي الحيوان ولا علامة الميزان. الافتراض يبقى CAP_CY توافقًا مع Specs السابقة.
    """
    lint_text(text, allow_city=allow_city)
    cy = CAP_CY if cy is None else max(0.30, min(0.90, float(cy)))
    f = B.font("black", CAP_FONT)
    lines = _balanced_lines(text, f, int(W * 0.86))
    if len(lines) > 1 and sum(len(l.split()) for l in lines) > CAP_MAX_WORDS * 2:
        lines = lines[:1]
    tw = max(int(B.measure(l, f)) for l in lines)
    lh = int(f.size * 1.28)
    pw, ph = min(W - 48, tw + 72), len(lines) * lh + 40
    y0 = int(H * cy) - ph // 2
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d0 = ImageDraw.Draw(img)
    d0.rounded_rectangle([(W - pw) // 2, y0, (W + pw) // 2, y0 + ph], radius=16,
                         fill=B.hex2rgb(B.C["bg_dark"]) + (120,))
    d = ImageDraw.Draw(img)
    y = y0 + 22 + lh // 2
    for ln in lines:
        B.text(d, (W // 2, y), ln, f, (255, 255, 255, 255), anchor="mm",
               stroke=3, stroke_fill=B.hex2rgb(B.C["green_deep"]) + (255,))
        y += lh
    return img


def endcard_layer(endcard: dict | None = None, allow_city: bool = False) -> Image.Image:
    """بطاقة ختام بالهوية الثابتة. النصوص الافتراضية محفوظة للقوالب القديمة.

    يمكن للـCreative Director تمرير headline/subtitle/cta/disclosure صراحةً؛
    المسودة الصامتة يجب ألا تدّعي وجود تعليق صوتي.
    """
    ec = endcard or {}
    headline = ec.get("headline", "ملك حقيقي")
    subtitle = ec.get("subtitle", "ومتابعة بعينك")
    cta = ec.get("cta", f"واتساب {B.PHONE}")
    disclosure = ec.get("disclosure", "تعليق صوتي · مدعوم بإضافات AI")
    for t in (headline, subtitle, cta, disclosure):
        lint_text(t, allow_city=allow_city)
    img = Image.new("RGBA", (W, H), B.hex2rgb(B.C["bg_dark"]) + (253,))
    box = B.place_logo(img, W // 2, int(H * 0.245), int(W * 0.50), "full")
    d = ImageDraw.Draw(img)
    y = box[3] + int(H * 0.075)
    B.text(d, (W // 2, y), headline, B.font("black", 82), (255, 255, 255, 255), anchor="mm")
    B.text(d, (W // 2, y + 82), subtitle, B.font("bold", 52),
           B.hex2rgb(B.C["gold"]) + (255,), anchor="mm")
    B.text(d, (W // 2, y + 172), cta, B.font("black", 52),
           (255, 255, 255, 255), anchor="mm")
    o = ornament((860, 150), 0.5)
    if o is not None:
        img.alpha_composite(o, ((W - 860) // 2, int(H * 0.842)))
    B.text(d, (W // 2, int(H * 0.788)), "#TerraNex", B.font("black", 58),
           B.hex2rgb(B.C["gold"]) + (255,), anchor="mm", direction="ltr")
    B.text(d, (W // 2, int(H * 0.834)), disclosure, B.font("medium", 27),
           (208, 222, 204, 215), anchor="mm")
    B.text(d, (W // 2, int(H * 0.872)), "المحتوى البصري تصوير حقيقي", B.font("medium", 26),
           (172, 192, 172, 205), anchor="mm")
    return img


# ---------------- البناء ----------------
def mix_audio(spec: dict, voice: str, original: str, total: float, out: str) -> str:
    """التعليق الصوتي واضحًا + الصوت الأصلي ~20% مع دكّ تلقائي + تايل عند الختام −15 LUFS.

    الصوت الأصلي في المصادر هنا صاخب، فالدكّ (sidechain) ضروري لا اختياري.
    """
    f = ff()
    vo_dur = 0.0
    pr = subprocess.run([f, "-hide_banner", "-i", voice], capture_output=True, text=True)
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", pr.stderr)
    if m:
        vo_dur = int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3])
    tail_len = max(0.0, total - vo_dur)
    a = float(spec.get("audio", {}).get("original_gain", 0.20))

    fc = ("[0:a]aformat=sample_rates=48000:channel_layouts=stereo,apad=whole_dur=%.2f,"
          "asplit=2[voA][voB];" % total)
    fade_out = max(0.0, total - 0.9)
    fc += ("[1:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=%.3f,"
           "afade=t=in:st=0:d=0.5,afade=t=out:st=%.2f:d=0.9[o20];" % (a, fade_out))
    fc += ("[o20][voA]sidechaincompress=threshold=0.03:ratio=8:attack=5:release=250[duck];")
    if tail_len > 0.3:
        # تايل من نهاية المقطع الأصلي لتفادي صمت ميت في إطار الختام
        ss = max(0.0, total - tail_len - 0.2)
        fc += ("[1:a]atrim=start=%.2f,asetpts=N/SR/TB,volume=%.3f[tail];" % (ss, a))
        fc += ("[voB][duck][tail]amix=inputs=3:duration=longest:dropout_transition=0:"
               "normalize=0,")
    else:
        fc += "[voB][duck]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,"
    fc += "atrim=0:%.2f,loudnorm=I=-15:TP=-1.5:LRA=11[aout]" % total
    p = subprocess.run([f, "-y", "-v", "error", "-i", voice, "-i", original,
                        "-filter_complex", fc, "-map", "[aout]",
                        "-c:a", "pcm_s16le", "-ar", "48000", out],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit("audio mix failed:\n" + p.stderr[-900:])
    return out


def build(spec_path: str, voice: str | None, out: str) -> dict:
    # الـspec يجب أن يعيش داخل مساحة التسويق، لكن لا يشترط أن يكون CWD هو مجلد التشغيل.
    # هذا يجعل الرندر يعمل بعد استعادة المستودع في مسار مختلف ومن أي CWD.
    spec_path = _safe_input_path(spec_path, MARKETING_ROOT)
    if os.path.basename(out).startswith("-") or os.path.basename(out) == "":
        raise SystemExit(f"unsafe output path: {out}")
    out = os.path.abspath(out)
    with open(spec_path, encoding="utf-8") as f:
        spec = json.load(f)
    if "render_approved" in spec and spec.get("render_approved") is not True:
        raise SystemExit("⛔ الرندر محجوب: render_approved يجب أن يكون true بعد اعتماد المواصفة.")
    if voice:
        voice = _safe_input_path(voice, os.path.dirname(spec_path), os.getcwd())
        VI.require_narration(spec.get("voice"), voice)
    # المسارات النسبية في الـspec تُحسب من مجلد الـspec نفسه (لا من CWD)
    base = os.path.dirname(os.path.abspath(spec_path))
    for c in spec["clips"]:
        if not os.path.isabs(c["path"]):
            c["path"] = os.path.normpath(os.path.join(base, c["path"]))
        c["path"] = _safe_input_path(c["path"], base, MARKETING_ROOT)

    require_consent(spec)
    allow_city = _delivery_city_authorized(spec)
    lint_text(spec.get("hook", ""), allow_city=allow_city)
    for c in spec.get("captions", []):
        lint_text(c["text"], allow_city=allow_city)

    clips = spec["clips"]
    dur = sum(c["end"] - c["start"] for c in clips)
    endcard_sec = float(spec.get("endcard_sec", 3.2))
    total = dur + endcard_sec

    tmpdir = out + ".seg"
    os.makedirs(tmpdir, exist_ok=True)
    segs = []
    for i, c in enumerate(clips):
        p = os.path.join(tmpdir, f"{i:02d}.mp4")
        vf = _clip_vf(c)
        # الصور الثابتة تحتاج -loop 1 وإلا أنتج ffmpeg إطارًا واحدًا فقط وانهارت المدة.
        is_img = os.path.splitext(c["path"])[1].lower() in IMAGE_EXT
        loop = ["-loop", "1"] if is_img else []
        subprocess.run([ff(), "-y", "-v", "error", "-ss", str(c["start"]),
                        "-t", str(c["end"] - c["start"])] + loop + ["-i", c["path"],
                        "-vf", vf,
                        "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
                        "-pix_fmt", "yuv420p", "-an", p], check=True)
        segs.append(p)

    lst = os.path.join(tmpdir, "list.txt")
    with open(lst, "w", encoding="utf-8") as f:
        for s in segs:
            f.write("file '%s'\n" % os.path.abspath(s))
    seq = os.path.join(tmpdir, "seq.mp4")
    subprocess.run([ff(), "-y", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", lst, "-c", "copy", seq], check=True)

    hook = hook_layer(spec["hook"], allow_city=allow_city) if spec.get("hook") else None
    hook_until = float(spec.get("hook_sec", 3.0))
    top = topbar()
    band = bottom_band()
    proofbar = proofbar_layer()
    proof_ranges, tacc = [], 0.0
    for c in clips:
        cd = c["end"] - c["start"]
        if c.get("proof_bar"):
            proof_ranges.append((tacc, tacc + cd))
        tacc += cd
    cap_cy = spec.get("caption_cy")
    caps = [(float(c["from"]), float(c["to"]), cap_layer(c["text"], cap_cy, allow_city=allow_city))
            for c in spec["captions"]]
    end = endcard_layer(spec.get("endcard"), allow_city=allow_city)

    dec = subprocess.Popen([ff(), "-v", "error", "-i", seq, "-f", "rawvideo",
                            "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL)
    cmd = [ff(), "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
    mixed = None
    if voice:
        voice = _safe_input_path(voice, base, os.getcwd())
        mixed = os.path.join(tmpdir, "mix.wav")
        # أرضية الصوت الأصلي: من اللقطة المحدّدة في audio.ambient_from (افتراضي الأولى).
        # للإعلان المؤسسي نختار لقطة المزرعة الحقيقية لا صوت البرومو الترويجي.
        amb_idx = int(spec.get("audio", {}).get("ambient_from", 0))
        amb_idx = max(0, min(len(clips) - 1, amb_idx))
        mix_audio(spec, voice, clips[amb_idx]["path"], total, mixed)
        cmd += ["-i", mixed]
    cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
            "-profile:v", "high", "-level", "4.1", "-movflags", "+faststart"]
    if mixed:
        cmd += ["-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "192k", "-ar", "48000"]
    else:
        cmd += ["-an"]
    cmd += ["-t", f"{total:.2f}", out]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    fb = W * H * 3
    n = 0
    while True:
        buf = dec.stdout.read(fb)
        if len(buf) < fb:
            break
        t = n / FPS
        img = Image.frombytes("RGB", (W, H), buf).convert("RGBA")
        img.alpha_composite(top)
        img.alpha_composite(band)
        if any(a <= t < b for a, b in proof_ranges):
            img.alpha_composite(proofbar)
        if hook is not None and t < hook_until:
            a = min(1.0, t / 0.28) * (1.0 if t < hook_until - 0.35
                                      else max(0.0, (hook_until - t) / 0.35))
            hk = hook.copy()
            hk.putalpha(hk.getchannel("A").point(lambda v: int(v * a)))
            img.alpha_composite(hk)
        for a0, a1, lay in caps:
            if a0 <= t < a1:
                al = min(1.0, (t - a0) / 0.20) * min(1.0, (a1 - t) / 0.20)
                cl = lay.copy()
                cl.putalpha(cl.getchannel("A").point(lambda v: int(v * al)))
                img.alpha_composite(cl)
                break
        try:
            enc.stdin.write(img.convert("RGB").tobytes())
        except BrokenPipeError:
            print(enc.stderr.read().decode(errors="ignore")[-1200:])
            raise SystemExit("encoder died at frame %d" % n)
        n += 1

    dec.stdout.close()
    dec.wait()
    last = img.convert("RGB") if n > 0 else None
    end_rgb = end.convert("RGB")
    while n / FPS < total:          # إطار الختام بعد نهاية اللقطات (ذوبان ناعم 0.35ث)
        ec_t = n / FPS - dur
        try:
            if last is not None and ec_t < 0.35:
                fr = Image.blend(last, end_rgb, min(1.0, ec_t / 0.35))
                enc.stdin.write(fr.tobytes())
            else:
                enc.stdin.write(end_rgb.tobytes())
        except BrokenPipeError:
            break
        n += 1
    enc.stdin.close()
    err = enc.stderr.read().decode(errors="ignore")
    if enc.wait() != 0:
        raise SystemExit("encode failed:\n" + err[-1200:])

    # تنظيف مقاطع التركيب الوسيطة بعد نجاح الرندر (لا تترك .seg بحجم مضاعف).
    shutil.rmtree(tmpdir, ignore_errors=True)
    return {"out": out, "frames": n, "duration": round(total, 2),
            "kb": os.path.getsize(out) // 1024, "clips": len(clips)}


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--voice", default=None)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    r = build(a.spec, a.voice, a.out)
    print(f"OK {r['out']} · {r['frames']} إطار · {r['duration']}ث · {r['kb']}KB")

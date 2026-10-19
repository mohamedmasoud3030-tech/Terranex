#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""reel_build.py — بناء ريل 9:16 من لقطات حقيقية بنظام الهوية الثابت (19/10).

القواعد المثبتة هنا (لا تُكسر):
  B9  — لا ذكر للمدينة: أي نص فيه «الإسكندرية» يُرفض قبل البناء.
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
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand as B  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PERSONAS = os.path.join(ROOT, "context", "personas.json")
W, H, FPS = 1080, 1920, 30

CAP_CY = 0.663          # منتصف شريط الكابشن — ثابت في كل الفيديو
BOTTOM_BAND = 0.870     # بداية الشريط السفلي الذي يغطي أي علامة محروقة في الفوتاج
CAP_MAX_WORDS = 6       # كلمات لكل سطر
CAP_FONT = 54


def ff() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


# ---------------- بوابات ----------------
def lint_text(text: str) -> None:
    """B9 — المدينة ممنوعة في أي نص يظهر للمشاهد."""
    hits = [c for c in B.CITY_BAN if c in (text or "")]
    if hits:
        raise SystemExit(f"⛔ B9: ذكر المدينة «{hits[0]}» في النص — ممنوع نهائيًا.")


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
    """العلامة المائية الرسمية أعلى الفريم: الرمز + TerraNex في قفل واحد ثابت."""
    th = 168
    lay = Image.new("RGBA", (W, th), B.hex2rgb(B.C["bg_dark"]) + (252,))
    d = ImageDraw.Draw(lay)
    d.rectangle([0, th - 3, W, th], fill=B.hex2rgb(B.C["gold"]) + (150,))
    emb = B.logo(104, "emblem")
    lay.alpha_composite(emb, (44, (th - emb.height) // 2 - 4))
    B.text(d, (44 + emb.width + 22, th // 2 - 4), "TerraNex", B.font("black", 44),
           B.hex2rgb(B.C["cream"]) + (245,), anchor="lm", direction="ltr")
    B.text(d, (W - 42, th // 2 - 4), "استثمار حيواني", B.font("medium", 27),
           B.hex2rgb(B.C["gold"]) + (215,), anchor="rm")
    return lay


def bottom_band() -> Image.Image:
    """شريط سفلي متدرّج: يغطي «TerraNex LLC» المحروقة في الفوتاج + منطقة UI الآمنة."""
    y0 = int(H * BOTTOM_BAND)
    h = H - y0
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # تدرّج سريع ثم معتم تمامًا: العلامة المحروقة في الفوتاج تقع عند 85–92% فيجب تغطيتها كاملة
    grad = Image.new("L", (1, h))
    ramp = max(1, int(h * 0.30))
    for y in range(h):
        v = 253 if y >= ramp else int(253 * (y / ramp) ** 0.8)
        grad.putpixel((0, y), v)
    band = Image.new("RGBA", (W, h), B.hex2rgb(B.C["bg_dark"]) + (255,))
    lay.paste(band, (0, y0), grad.resize((W, h)))
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


def hook_layer(text: str) -> Image.Image:
    lint_text(text)
    f = B.font("black", 88)
    lines = B.wrap(text, f, int(W * 0.84), max_lines=2)
    tw = max(int(B.measure(l, f)) for l in lines)
    lh = int(f.size * 1.30)
    pw, ph = min(W - 56, tw + 84), len(lines) * lh + 56
    y0 = int(H * 0.285)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d0 = ImageDraw.Draw(img)
    d0.rounded_rectangle([(W - pw) // 2, y0, (W + pw) // 2, y0 + ph], radius=26,
                         fill=B.hex2rgb(B.C["bg_dark"]) + (212,),
                         outline=B.hex2rgb(B.C["gold"]) + (105,), width=2)
    d = ImageDraw.Draw(img)
    y = y0 + 28 + lh // 2
    for ln in lines:
        B.text(d, (W // 2, y), ln, f, (255, 255, 255, 255), anchor="mm",
               stroke=3, stroke_fill=B.hex2rgb(B.C["green_deep"]) + (255,))
        y += lh
    o = ornament((820, 140), 0.8)
    if o is not None:
        img.alpha_composite(o, ((W - 820) // 2, y0 + ph + 26))
    return img


def cap_layer(text: str) -> Image.Image:
    """شريط الكابشن المترجم — نفس المكان والحجم في كل سطر (لا عشوائية)."""
    lint_text(text)
    f = B.font("black", CAP_FONT)
    lines = B.wrap(text, f, int(W * 0.84), max_lines=2)
    if len(lines) > 1 and sum(len(l.split()) for l in lines) > CAP_MAX_WORDS * 2:
        lines = lines[:1]
    tw = max(int(B.measure(l, f)) for l in lines)
    lh = int(f.size * 1.28)
    pw, ph = min(W - 48, tw + 72), len(lines) * lh + 44
    y0 = int(H * CAP_CY) - ph // 2
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d0 = ImageDraw.Draw(img)
    d0.rounded_rectangle([(W - pw) // 2, y0, (W + pw) // 2, y0 + ph], radius=18,
                         fill=B.hex2rgb(B.C["bg_dark"]) + (200,),
                         outline=B.hex2rgb(B.C["gold"]) + (70,), width=2)
    d = ImageDraw.Draw(img)
    y = y0 + 22 + lh // 2
    for ln in lines:
        B.text(d, (W // 2, y), ln, f, (255, 255, 255, 255), anchor="mm",
               stroke=3, stroke_fill=B.hex2rgb(B.C["green_deep"]) + (255,))
        y += lh
    return img


def endcard_layer() -> Image.Image:
    img = Image.new("RGBA", (W, H), B.hex2rgb(B.C["bg_dark"]) + (253,))
    box = B.place_logo(img, W // 2, int(H * 0.245), int(W * 0.50), "full")
    d = ImageDraw.Draw(img)
    y = box[3] + int(H * 0.075)
    B.text(d, (W // 2, y), "ملك حقيقي", B.font("black", 82), (255, 255, 255, 255), anchor="mm")
    B.text(d, (W // 2, y + 82), "ومتابعة بعينك", B.font("bold", 52),
           B.hex2rgb(B.C["gold"]) + (255,), anchor="mm")
    B.text(d, (W // 2, y + 172), f"واتساب {B.PHONE}", B.font("black", 52),
           (255, 255, 255, 255), anchor="mm")
    o = ornament((860, 150), 0.5)
    if o is not None:
        img.alpha_composite(o, ((W - 860) // 2, int(H * 0.842)))
    B.text(d, (W // 2, int(H * 0.788)), "#TerraNex", B.font("black", 58),
           B.hex2rgb(B.C["gold"]) + (255,), anchor="mm", direction="ltr")
    B.text(d, (W // 2, int(H * 0.834)), "تعليق صوتي · مدعوم بإضافات AI", B.font("medium", 27),
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
    fc += ("[1:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=%.3f[o20];" % a)
    fc += ("[o20][voA]sidechaincompress=threshold=0.03:ratio=8:attack=5:release=250[duck];")
    if tail_len > 0.3:
        # تايل من نهاية المقطع الأصلي لتفادي صمت ميت في إطار الختام
        ss = max(0.0, total - tail_len - 0.2)
        fc += ("[1:a]atrim=start=%.2f,asetpts=N/SR/TB,volume=%.3f[tail];" % (ss, a))
        fc += ("[voB][duck][tail]amix=inputs=3:duration=longest:dropout_transition=0:"
               "normalize=0," % ())
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
    with open(spec_path, encoding="utf-8") as f:
        spec = json.load(f)
    # المسارات النسبية في الـspec تُحسب من مجلد الـspec نفسه (لا من CWD)
    base = os.path.dirname(os.path.abspath(spec_path))
    for c in spec["clips"]:
        if not os.path.isabs(c["path"]):
            c["path"] = os.path.normpath(os.path.join(base, c["path"]))

    require_consent(spec)
    lint_text(spec.get("hook", ""))
    for c in spec.get("captions", []):
        lint_text(c["text"])

    clips = spec["clips"]
    dur = sum(c["end"] - c["start"] for c in clips)
    endcard_sec = float(spec.get("endcard_sec", 3.2))
    total = dur + endcard_sec

    tmpdir = out + ".seg"
    os.makedirs(tmpdir, exist_ok=True)
    segs = []
    for i, c in enumerate(clips):
        p = os.path.join(tmpdir, f"{i:02d}.mp4")
        # hide_burnt_logo: نُكبّر 1.16× ونقصّ من الأعلى — يُزيل العلامة المحروقة
        # («TerraNex LLC») الموجودة أسفل المصدر بدل تغطيتها. الحل الأنظف وأقل تدخلًا.
        if c.get("hide_burnt_logo", True):
            # نكبّر ثم نأخذ أعلى الكادر فقط: العلامة المحروقة في أسفل المصدر تُقصّ نهائيًا
            cut = float(c.get("crop_bottom_pct", 0.34))
            fct = 1.0 / max(0.5, 1.0 - cut)
            vf = (f"scale={int(W*fct)}:{int(H*fct)}:force_original_aspect_ratio=increase,"
                  f"crop={W}:{H}:0:0,fps={FPS},setsar=1")
        else:
            vf = (f"scale={W}:{H}:force_original_aspect_ratio=increase,"
                  f"crop={W}:{H},fps={FPS},setsar=1")
        subprocess.run([ff(), "-y", "-v", "error", "-ss", str(c["start"]),
                        "-t", str(c["end"] - c["start"]), "-i", c["path"],
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

    hook = hook_layer(spec["hook"]) if spec.get("hook") else None
    hook_until = float(spec.get("hook_sec", 3.0))
    top = topbar()
    band = bottom_band()
    caps = [(float(c["from"]), float(c["to"]), cap_layer(c["text"])) for c in spec["captions"]]
    end = endcard_layer()

    dec = subprocess.Popen([ff(), "-v", "error", "-i", seq, "-f", "rawvideo",
                            "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL)
    cmd = [ff(), "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
    mixed = None
    if voice:
        mixed = os.path.join(tmpdir, "mix.wav")
        mix_audio(spec, voice, clips[0]["path"], total, mixed)
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
    while n / FPS < total:          # إطار الختام بعد نهاية اللقطات
        try:
            enc.stdin.write(end.convert("RGB").tobytes())
        except BrokenPipeError:
            break
        n += 1
    enc.stdin.close()
    err = enc.stderr.read().decode(errors="ignore")
    if enc.wait() != 0:
        raise SystemExit("encode failed:\n" + err[-1200:])

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

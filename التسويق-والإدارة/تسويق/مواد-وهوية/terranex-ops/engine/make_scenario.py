#!/usr/bin/env python3
"""make_scenario — سيناريو تصوري: إطارات 9:16 بهوية TerraNex فوق صورة أساس.

الغرض: تقديم **نموذج عرض (mock)** أثناء مرحلة الاختبار أو لعرض أمثلة شغل،
حين لا تتوفر مادة تصوير حقيقية بعد. المخرجات **ليست** محتوى الشركة الرسمي
ويجب أن تحمل وسم «نموذج تصوري» (بند 3.4 في context/compliance.md).

الاستخدام:
  python engine/make_scenario.py --spec سيناريو-تصوري/spec.json \
      --outdir سيناريو-تصوري/frames --video سيناريو-تصوري/teaser.mp4
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand as B  # noqa: E402

W, H = 1080, 1920
FPS = 24


# ---------------------------------------------------------------- صورة الأساس
def cover(img: Image.Image, w: int, h: int, zoom: float = 1.0) -> Image.Image:
    """قصّ مركزي بنسبة الأبعاد المطلوبة + تكبير اختياري."""
    r = max(w / img.width, h / img.height) * zoom
    im = img.resize((max(1, int(round(img.width * r))), max(1, int(round(img.height * r)))),
                    Image.LANCZOS)
    x = (im.width - w) // 2
    y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def grade(img: Image.Image) -> Image.Image:
    """توحيد اللون مع الهوية: ميل أخضر في الظلال + دفء في الهايلايت."""
    base = img.convert("RGB")
    shadow = Image.new("RGB", base.size, B.hex2rgb(B.C["bg_dark"]))
    mask = base.convert("L").point(lambda v: int(max(0, 92 - v) * 0.55))
    base = Image.composite(shadow, base, mask)
    warm = Image.new("RGB", base.size, B.hex2rgb(B.C["gold_hi"]))
    wm = base.convert("L").point(lambda v: int(max(0, v - 168) * 0.30))
    return Image.composite(warm, base, wm)


def scrim_layer() -> Image.Image:
    """قناع تظليل متصل بدون أي حدود — يُحسب مرة واحدة بـnumpy.

    بروفايل واحد ناعم: قوي في الأعلى، يخفّ في الوسط، يقوى في الأسفل،
    ثم شريط سفلي شبه معتم يضمن قراءة الفوتر على أي صورة.
    """
    ys = np.linspace(0.0, 1.0, H, dtype=np.float64)
    top = 0.80 * np.clip(1 - ys / 0.34, 0, 1) ** 1.35
    bot = 0.62 * np.clip((ys - 0.52) / 0.30, 0, 1) ** 1.25
    bar = np.clip((ys - 0.855) / 0.055, 0, 1) ** 0.9 * 0.86
    base = np.maximum(top, np.maximum(bot, bar))
    # ضمان حد أدنى للتباين في كل الإطار
    alpha = np.clip(base + 0.20, 0, 0.95)

    a = (alpha * 255).astype(np.uint8)
    mask = np.repeat(a[:, None], W, axis=1)
    tint = np.zeros((H, W, 4), dtype=np.uint8)
    tint[..., 0], tint[..., 1], tint[..., 2] = 5, 14, 9
    tint[..., 3] = mask
    return Image.fromarray(tint, "RGBA")


_SCRIM = None


# ---------------------------------------------------------------- طبقة النص
def text_layer(fr: dict, index: int, total: int, disclosure: str) -> Image.Image:
    """كتلة علوية (kicker + headline [+ stat]) ولوحة سفلية (sub + رقم + وسم)."""
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    pad = int(W * 0.085)

    # ================= الكتلة العلوية =================
    _lbox = B.place_logo(lay, W // 2, int(H * 0.075), int(W * 0.36), "full")

    if fr.get("kicker"):
        B.text(d, (W // 2, _lbox[3] + 40), fr["kicker"], B.font("medium", 30),
               B.hex2rgb(B.C["gold"]) + (242,), anchor="mm")
        B.hairline(d, int(W * 0.395), int(W * 0.605), _lbox[3] + 78, B.C["gold"], 2, 140)

    fh = B.font("black", 106 if len(fr["headline"]) <= 20 else 90)
    lines = B.wrap(fr["headline"], fh, W - 2 * pad, max_lines=3)
    lh = int(fh.size * 1.15)
    y = max(int(H * 0.172), _lbox[3] + 120)
    for ln in lines:
        B.text(d, (W // 2, y + int(lh * 0.5)), ln, fh, B.hex2rgb(B.C["cream"]) + (255,), anchor="mm")
        y += lh

    # ---- الرقم: مباشرة تحت العنوان (مكان مضمون ومقروء)
    if fr.get("stat") is not None:
        y += int(H * 0.012)
        fs = B.font("black", 206)
        stat_h = int(fs.size * 1.0)
        num = str(fr["stat"])
        fu = B.font("bold", 64)
        wn = B.measure(num, fs, "ltr")
        wu = B.measure(fr.get("unit", ""), fu) if fr.get("unit") else 0
        blockw = wn + (wu + 30 if wu else 0)
        x_num = W // 2 + int(blockw / 2) - int(wn / 2)

        gl = Image.new("L", (W, H), 0)
        ImageDraw.Draw(gl).ellipse([x_num - wn * 0.62, y + stat_h * 0.03,
                                    x_num + wn * 0.62, y + stat_h * 0.97], fill=64)
        gl = gl.filter(ImageFilter.GaussianBlur(66))
        halo = Image.new("RGBA", (W, H), B.hex2rgb(B.C["gold"]) + (0,))
        halo.putalpha(gl)
        lay.alpha_composite(halo)

        B.text(d, (x_num, y + stat_h * 0.50), num, fs, B.hex2rgb(B.C["gold"]) + (255,),
               anchor="mm", direction="ltr")
        if wu:
            B.text(d, (x_num + wn / 2 + 30 + wu / 2, y + stat_h * 0.535), fr["unit"], fu,
                   B.hex2rgb(B.C["cream"]) + (255,), anchor="mm")
        y += stat_h

    # ================= اللوحة السفلية =================
    fsub = B.font("regular", 44)
    slines = B.wrap(fr["sub"], fsub, W - 2 * pad - 40, max_lines=2) if fr.get("sub") else []
    s_lh = int(fsub.size * 1.42)
    y = int(H * 0.878) - (len(slines) * s_lh)

    for ln in slines:
        B.text(d, (W // 2, y + int(s_lh * 0.5)), ln, fsub,
               B.hex2rgb(B.C["cream"]) + (222,), anchor="mm")
        y += s_lh

    B.hairline(d, pad, W - pad, int(H * 0.888), B.C["gold"], 2, 120)
    B.text(d, (W // 2, int(H * 0.918)), f"واتساب  {B.PHONE}", B.font("bold", 38),
           B.hex2rgb(B.C["cream"]) + (245,), anchor="mm")
    B.text(d, (W // 2, int(H * 0.947)), "متابعة بالصور والوزن داخل الدورة",
           B.font("regular", 24), B.hex2rgb(B.C["cream"]) + (160,), anchor="mm")
    B.text(d, (W // 2, int(H * 0.972)), disclosure, B.font("medium", 23),
           B.hex2rgb(B.C["gold_hi"]) + (200,), anchor="mm")
    B.text(d, (pad, int(H * 0.972)), f"{index:02d} / {total:02d}", B.font("medium", 21),
           B.hex2rgb(B.C["cream"]) + (125,), anchor="lm", direction="ltr")

    return lay


# ---------------------------------------------------------------- بناء
def build(spec: dict, outdir: str, base_dir: str):
    global _SCRIM
    os.makedirs(outdir, exist_ok=True)
    _SCRIM = scrim_layer()

    frames = spec["frames"]
    disclosure = spec.get("disclosure", "نموذج تصوري — صور مولّدة بالذكاء الاصطناعي")
    prepared = []

    for i, fr in enumerate(frames, 1):
        src = os.path.join(base_dir, fr["img"])
        if not os.path.exists(src):
            raise FileNotFoundError(f"صورة غير موجودة: {src}")
        photo = grade(cover(Image.open(src).convert("RGB"), W, H))  # بلا تظليل
        overlay = text_layer(fr, i, len(frames), disclosure)

        out = photo.convert("RGBA")
        out.alpha_composite(_SCRIM)
        out.alpha_composite(overlay)

        name = f"{i:02d}-{fr.get('slug', f'frame-{i}')}.png"
        out.convert("RGB").save(os.path.join(outdir, name), quality=95)
        prepared.append({
            "photo": photo, "overlay": overlay, "name": name,
            "dur": float(fr.get("dur", 3.5)), "zoom": fr.get("zoom", "in"),
        })
        print(f"OK {name}")

    # ورقة تواصل
    cols, tw = 6, 300
    th_img = int(tw * H / W)
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * 10, th_img + 20), (8, 16, 12))
    for i, p in enumerate(prepared):
        t = Image.open(os.path.join(outdir, p["name"]))
        t.thumbnail((tw, th_img), Image.LANCZOS)
        sheet.paste(t, (10 + i * (tw + 10), 10))
    sheet.save(os.path.join(outdir, "..", "storyboard.png"))
    print("OK storyboard.png")
    return prepared


def render_video(prepared, out_path: str):
    import imageio_ffmpeg
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    cmd = [ffmpeg, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium",
           "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", out_path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    n = 0
    for p in prepared:
        n_frames = max(1, int(p["dur"] * FPS))
        for f in range(n_frames):
            t = f / max(1, n_frames - 1)
            z = 1.02 + 0.055 * (t if p["zoom"] == "in" else 1 - t)
            im = cover(p["photo"], W, H, zoom=z).convert("RGBA")
            im.alpha_composite(_SCRIM)          # تظليل ثابت لا يتحرك مع الزوم
            im.alpha_composite(p["overlay"])
            proc.stdin.write(im.convert("RGB").tobytes())
            n += 1
        print(f"  … {n} إطار", end="\r")
    proc.stdin.close()
    err = proc.stderr.read().decode("utf-8", "ignore")
    rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"ffmpeg فشل ({rc}):\n{err[-2000:]}")
    print(f"\nOK {out_path} — {n} إطار · {n / FPS:.1f} ث")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--video", default=None)
    a = ap.parse_args()

    spec_path = os.path.abspath(a.spec)
    base_dir = os.path.dirname(spec_path)
    with open(spec_path, encoding="utf-8") as f:
        spec = json.load(f)

    prepared = build(spec, a.outdir, base_dir)
    if a.video:
        render_video(prepared, a.video)


if __name__ == "__main__":
    main()

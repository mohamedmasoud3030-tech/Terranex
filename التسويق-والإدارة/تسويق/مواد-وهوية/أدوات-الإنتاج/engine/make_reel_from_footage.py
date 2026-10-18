#!/usr/bin/env python3
"""make_reel_from_footage.py — يبني ريل نهائي من فيديو حقيقي + هوية TerraNex + كابشن محروق.

  python engine/make_reel_from_footage.py \
      --video "../google_drive/04-الأربعاء-الوزن-على-الطبيعة.mp4" \
      --captions output/captions-04.json --out output/reel-weight-branded.mp4

why frame-by-frame: العربي بيتشكّل بـPIL+libraqm (مضمون) بدل libass/drawtext.
الصوت الأصلي بيتنقل كما هو (أو يُستبدل بصوت مولّد عبر --voice-over).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand as B  # noqa: E402

W, H = 1080, 1920


def ffmpeg_bin():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def probe(path):
    ff = ffmpeg_bin()
    out = subprocess.run([ff, "-hide_banner", "-i", path], capture_output=True, text=True).stderr
    dur = 0.0
    for line in out.splitlines():
        if "Duration:" in line:
            h, m, s = line.split("Duration:")[1].split(",")[0].strip().split(":")
            dur = int(h) * 3600 + int(m) * 60 + float(s)
    return dur


# ---------- طبقات ثابتة ----------
def top_layer():
    """بار علوي كامل العرض (كحلي/أخضر) — بيغطي أي نص محروق في المصدر فوق."""
    TH = 250
    lay = Image.new("RGBA", (W, TH), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rectangle([0, 0, W, TH], fill=(11, 42, 23, 252))
    d.rectangle([0, TH - 4, W, TH], fill=(132, 204, 22, 140))
    B.brand_mark(lay, 84, TH // 2, d=66)
    f = B.font("black", 36)
    B.text(d, (132, TH // 2), "TERRANEX", f, B.hex2rgb(B.C["cream50"]) + (245,), anchor="lm", direction="ltr")
    f2 = B.font("medium", 27)
    B.text(d, (W - 40, TH // 2), "استثمار حيواني · الإسكندرية", f2, (214, 226, 210, 215), anchor="rm")
    return lay


def bottom_layer():
    """شريط سفلي خفيف + رقم — فوق منطقة الـUI."""
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    gh = 300
    grad = Image.new("L", (1, gh))
    for y in range(gh):
        grad.putpixel((0, y), int(200 * (y / gh) ** 1.5))
    grad = grad.resize((W, gh))
    dark = Image.new("RGBA", (W, gh), (11, 42, 23, 255))
    lay.paste(Image.composite(dark, Image.new("RGBA", (W, gh), (0, 0, 0, 0)),
                              grad.point(lambda v: v)), (0, H - gh))
    f = B.font("bold", 30)
    B.text(d, (W // 2, H - 210), f"واتساب {B.PHONE}", f, B.hex2rgb(B.C["cream50"]) + (215,), anchor="mm")
    return lay


def caption_tile(text: str):
    """يرسم سطر الكابشن مرة واحدة ويرجّع tile + مكانه."""
    f = B.font("black", 58)
    lines = B.wrap(text, f, int(W * 0.86), max_lines=2)
    pad_x, pad_y, gap = 34, 24, 12
    w = max(int(B.measure(l, f)) for l in lines) + pad_x * 2
    lh = int(f.size * 1.30)
    h = len(lines) * lh + pad_y * 2 - gap
    tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    r = 20
    td.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=(11, 42, 23, 214),
                         outline=(132, 204, 22, 90), width=2)
    y = pad_y + lh // 2
    for ln in lines:
        B.text(td, (w // 2, y), ln, f, (255, 255, 255, 255), anchor="mm")
        y += lh
    return tile, (W - w) // 2, int(H * 0.335) - h // 2


def endcard_layer():
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rectangle([0, 0, W, H], fill=(11, 42, 23, 255))
    B.brand_mark(lay, W // 2, int(H * 0.245), d=136)
    f0 = B.font("bold", 30)
    B.text(d, (W // 2, int(H * 0.245) + 108), "TERRANEX", f0, (240, 246, 238, 235), anchor="mm", direction="ltr")
    f1 = B.font("black", 74)
    B.text(d, (W // 2, int(H * 0.395)), "ملك حقيقي", f1, (255, 255, 255, 255), anchor="mm")
    f2 = B.font("bold", 52)
    B.text(d, (W // 2, int(H * 0.462)), "ومتابعة بعينك", f2, B.hex2rgb(B.C["lime500"]) + (255,), anchor="mm")
    fa = B.font("regular", 38)
    B.text(d, (W // 2, int(H * 0.528)), "الوزن · الفحص · التغذية — بالصور والتاريخ", fa, (216, 226, 210, 225), anchor="mm")
    B.hairline(d, int(W * 0.18), int(W * 0.82), int(H * 0.588), B.C["lime500"], 2, 140)
    fp = B.font("black", 60)
    B.text(d, (W // 2, int(H * 0.655)), B.PHONE, fp, (255, 255, 255, 255), anchor="mm", direction="ltr")
    fw = B.font("medium", 31)
    B.text(d, (W // 2, int(H * 0.703)), "واتساب — الإسكندرية", fw, (214, 226, 210, 210), anchor="mm")
    return lay


def render(video, captions, out, voice_over=None, endcard=2.6, keep_audio=True):
    ff = ffmpeg_bin()
    dur = probe(video)

    # 1) فك الفيديو → إطارات 1080×1920
    dec = [ff, "-v", "error", "-i", video, "-vf",
           f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},fps=30",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    dp = subprocess.Popen(dec, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    # 2) تجهيز الطبقات
    top, bot = top_layer(), bottom_layer()
    tiles = []
    for c in captions:
        t, x, y = caption_tile(c["text"])
        tiles.append(((float(c["from"]), float(c["to"])), t, x, y))
    end = endcard_layer()

    # 3) الترميز + الصوت
    cmd = [ff, "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{W}x{H}", "-r", "30", "-i", "-"]
    audio_src = voice_over or (video if keep_audio else None)
    if audio_src:
        cmd += ["-i", audio_src]
    cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", "21", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart"]
    if audio_src:
        cmd += ["-c:a", "aac", "-b:a", "160k", "-af", "loudnorm=I=-15:TP=-1.5:LRA=11"]
    else:
        cmd += ["-an"]
    cmd += ["-t", f"{dur:.2f}", out]
    ep = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    n, i = 0, 0
    frame_bytes = W * H * 3
    while True:
        buf = dp.stdout.read(frame_bytes)
        if len(buf) < frame_bytes:
            break
        t = n / 30.0
        img = Image.frombytes("RGB", (W, H), buf).convert("RGBA")
        in_end = t >= dur - endcard
        if in_end:
            a = min(1.0, (t - (dur - endcard)) / 0.40)
            ec = end.copy()
            ec.putalpha(ec.getchannel("A").point(lambda v: int(v * a)))
            img.alpha_composite(ec)
        else:
            img.alpha_composite(top)
            img.alpha_composite(bot)
            for (f0, f1), tile, x, y in tiles:
                if f0 <= t < f1:
                    a = min(1.0, (t - f0) / 0.18) * min(1.0, (f1 - t) / 0.15)
                    tt = tile.copy()
                    tt.putalpha(tt.getchannel("A").point(lambda v: int(v * a)))
                    img.alpha_composite(tt, (x, y))
                    break
        try:
            ep.stdin.write(img.convert("RGB").tobytes())
        except BrokenPipeError:
            err = ep.stderr.read().decode(errors="ignore")
            raise SystemExit(f"encoder died at frame {n}:\n{err[-1200:]}")
        n += 1
        if n % 150 == 0:
            print(f"  … {n} إطار", flush=True)

    dp.stdout.close(); dp.wait()
    ep.stdin.close()
    err = ep.stderr.read().decode(errors="ignore")
    if ep.wait() != 0:
        raise SystemExit("encode failed:\n" + err[-1200:])
    return n, dur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--captions", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--voice-over", default=None, help="مسارات صوت بديلة (مولّدة أو مسجلة)")
    ap.add_argument("--no-audio", action="store_true")
    ap.add_argument("--endcard", type=float, default=2.6)
    a = ap.parse_args()
    caps = json.load(open(a.captions, encoding="utf-8"))["captions"]
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    n, dur = render(a.video, caps, a.out, a.voice_over, a.endcard, not a.no_audio)
    print(f"OK {a.out} {n} إطار · {dur:.1f} ث · {os.path.getsize(a.out)//1024}KB")


if __name__ == "__main__":
    main()

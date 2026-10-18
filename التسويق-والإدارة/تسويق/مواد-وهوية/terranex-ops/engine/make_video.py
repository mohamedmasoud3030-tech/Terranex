#!/usr/bin/env python3
"""محرّك الريل — يبني فيديو 9:16 من سكربت JSON بدون أي API key.

  python engine/make_video.py --script output/script.json --out output/reel.mp4
  python engine/make_video.py --script output/script.json --voice recording.m4a --out output/reel.mp4

قواعد الالتزام مطبّقة في المحرّك نفسه:
  • لا يولّد صوتًا أبدًا (Piper/TTS ممنوع). الصوت يُمرَّر من تسجيل حقيقي فقط.
  • العربي يُرسم بـPIL + libraqm (شكل واتجاه صحيح)، لا drawtext.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand as B  # noqa: E402

W, H, FPS = 1080, 1920, 25


def ease_out(t: float) -> float:
    return 1 - (1 - t) ** 3


def background(idx: int, total: int):
    palettes = [
        [(0.0, B.C["bg_dark"]), (1.0, B.C["bg_mid"])],
        [(0.0, B.C["bg_mid"]), (1.0, B.C["green_deep"])],
        [(0.0, B.C["bg_dark"]), (1.0, B.C["green_deep"])],
    ]
    p = palettes[idx % len(palettes)]
    base = B.vgradient((W, H), p).convert("RGBA")
    base = B.glow(base, (int(W * 0.7), int(H * 0.2)), int(W * 0.8), B.C["gold"], alpha=34)
    base = B.vignette(base, 120)
    return base


def draw_scene(canvas: Image.Image, sc: dict, p: float, i: int, total: int):
    """p = تقدّم المشهد 0→1. كل العناصر بتتقاس وتتوازن رأسيًا."""
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    e = ease_out(min(1.0, p * 3.2))
    out = 1.0 - max(0.0, (p - 0.84) / 0.16)
    a = int(255 * min(e, out))
    dy = int((1 - e) * 64)

    # عناصر ثابتة
    B.place_logo(canvas, W // 2, 122, 150)
    f_logo = B.font("bold", 25)
    B.text(d, (W // 2, 196), "TERRANEX", f_logo, B.hex2rgb(B.C["cream"]) + (a,),
           anchor="mm", direction="ltr")

    # قياس البلوك
    fk = B.font("medium", 32)
    fh = B.font("black", int(sc.get("size", 96)))
    hlines = B.wrap(sc.get("headline", ""), fh, int(W * 0.84), max_lines=3)
    fsub = B.font("regular", 46)
    slines = B.wrap(sc.get("sub", ""), fsub, int(W * 0.82), max_lines=3) if sc.get("sub") else []
    fs = B.font("black", 240) if sc.get("stat") else None

    kh = 46 if sc.get("kicker") else 0
    hh = len(hlines) * int(fh.size * 1.12)
    sh = int(fs.size * 0.74) if fs else 0
    subh = len(slines) * int(fsub.size * 1.42)
    g1 = 78 if fs else 0
    g2 = 46 if slines else 0
    total_h = kh + hh + g1 + sh + g2 + subh

    top, bottom = int(H * 0.215), int(H * 0.815)
    y = top + max(0, ((bottom - top) - total_h) // 2) + dy

    if sc.get("kicker"):
        B.text(d, (W // 2, y + 20), sc["kicker"], fk, B.hex2rgb(B.C["gold"]) + (a,), anchor="mm")
        B.hairline(d, int(W * 0.32), int(W * 0.68), y + 54, B.C["gold_mid"], 2, a // 2)
        y += kh

    for ln in hlines:
        B.text(d, (W // 2, y + int(fh.size * 0.56)), ln, fh, B.hex2rgb(B.C["cream"]) + (a,), anchor="mm")
        y += int(fh.size * 1.12)

    if fs:
        y += g1
        num = str(sc["stat"])
        wn = B.measure(num, fs, "ltr")
        wu = B.measure(sc.get("unit", ""), B.font("bold", 68)) if sc.get("unit") else 0
        blockw = wn + (wu + 26 if wu else 0)
        x_num = W // 2 + int(blockw / 2) - int(wn / 2)
        B.text(d, (x_num, y + sh * 0.5), num, fs, B.hex2rgb(B.C["gold"]) + (a,),
               anchor="mm", direction="ltr")
        if wu:
            B.text(d, (x_num + wn / 2 + 26 + wu / 2, y + sh * 0.54), sc["unit"],
                   B.font("bold", 68), B.hex2rgb(B.C["cream"]) + (a,), anchor="mm")
        y += sh

    if slines:
        y += g2
        for ln in slines:
            B.text(d, (W // 2, y + int(fsub.size * 0.6)), ln, fsub, (216, 226, 210, a), anchor="mm")
            y += int(fsub.size * 1.42)

    canvas.alpha_composite(lay)

    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    prog = (i + p) / max(1, total)
    od.rectangle([0, H - 10, int(W * prog), H], fill=B.hex2rgb(B.C["gold"]) + (210,))
    ff = B.font("medium", 28)
    od.text((W // 2, H - 96) if False else (W // 2, H - 96), f"واتساب {B.PHONE}", font=ff,
            fill=B.hex2rgb(B.C["cream"]) + (165,), anchor="mm", direction="rtl", language="ar")
    canvas.alpha_composite(ov)


def render(script: dict, out_path: str, voice: str | None = None):
    scenes = script["scenes"]
    total_frames = int(float(script.get("duration", sum(s["to"] for s in scenes))) * FPS)
    # اشتقاق مدة كل مشهد
    specs = []
    for i, s in enumerate(scenes):
        dur = float(s.get("dur") or (float(s["to"]) - float(s["from"])))
        specs.append((i, s, max(1, int(dur * FPS))))
    total_frames = sum(f for _, _, f in specs)

    ff = B.__dict__.get("_ffmpeg")
    ffmpeg = ff or _ffmpeg()
    cmd = [ffmpeg, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-"]
    if voice:
        cmd += ["-i", voice]
    cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart"]
    cmd += ["-c:a", "aac", "-b:a", "128k", "-shortest"] if voice else ["-an"]
    cmd += [out_path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)

    n = 0
    for i, sc, frames in specs:
        bg = background(i, len(specs))
        for f in range(frames):
            canvas = bg.copy()
            draw_scene(canvas, sc, f / frames, i, len(specs))
            proc.stdin.write(canvas.convert("RGB").tobytes())
            n += 1
            if n % 125 == 0:
                print(f"  … {n} frame", flush=True)
    proc.stdin.close()
    err = proc.stderr.read().decode(errors="ignore")
    if proc.wait() != 0:
        raise SystemExit("ffmpeg failed:\n" + err[-1500:])
    return n


def _ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--voice", default=None, help="تسجيل صوتي حقيقي (ممنوع أي TTS)")
    a = ap.parse_args()

    script = json.load(open(a.script, encoding="utf-8"))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    n = render(script, a.out, a.voice)
    size = os.path.getsize(a.out) // 1024
    print(f"OK {a.out} {n} frames {size}KB")


if __name__ == "__main__":
    main()

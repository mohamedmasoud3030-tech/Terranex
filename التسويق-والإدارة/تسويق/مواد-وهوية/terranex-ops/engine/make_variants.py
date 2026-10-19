#!/usr/bin/env python3
"""make_variants.py — نسخ بمقاسات المنصات من الفيديو الرئيسي.

  python engine/make_variants.py --video master.mp4 --outdir output/variants/الوزن

من الماستر 9:16 (720×1280 أو 1080×1920) يولّد:
  reels/   1080×1920  (ترقية دقيقة — انستجرام/فيسبوك ريلز/تيك توك)
  feed45/  1080×1350  (قصّ عمودي مركزي — بوست الفيد)
  square/  1080×1080  (قصّ مربع مركزي مؤمّن — واتساب/فيد تاني)

الأمان: القص مركزي، والماستر مصمم أصلًا بمساحات آمنة (brand-kit §4) —
لو القص قصّ كلامًا مهمًا، القرار النهائي للعين البشرية (يقال صراحة في التقرير).
الصوت يُنسخ كما هو (aac copy). لا شبكة.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys


def _ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


# من ماستر 9:16: نسبة 4:5 و1:1 أعرض نسبيًا ← القص من الطول (أعلى/أسفل) مع تثبيت العرض.
VARIANTS = {
    "reels": "scale=1080:1920:flags=lanczos",
    # feed45: الطول الهدف in_w×5/4 (زوجي) — قص من الأعلى/الأسفل بتثبيت العرض
    "feed45": "crop=in_w:trunc(in_w*5/8)*2:0:(in_h-trunc(in_w*5/8)*2)/2,scale=1080:1350:flags=lanczos",
    "square": "crop=in_w:in_w:0:(in_h-in_w)/2,scale=1080:1080:flags=lanczos",
}


def build(video: str, outdir: str) -> list[dict]:
    ff = _ffmpeg()
    os.makedirs(outdir, exist_ok=True)
    base = os.path.splitext(os.path.basename(video))[0]
    made = []
    for name, vf in VARIANTS.items():
        out = os.path.join(outdir, f"{base}-{name}.mp4")
        cmd = [ff, "-y", "-i", video, "-vf", vf,
               "-c:v", "libx264", "-preset", "medium", "-crf", "20",
               "-pix_fmt", "yuv420p", "-profile:v", "high", "-level", "4.1",
               "-movflags", "+faststart", "-c:a", "copy", out]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        if p.returncode != 0:
            raise SystemExit(f"ffmpeg فشل في {name}:\n{p.stderr[-1200:]}")
        made.append({"variant": name, "path": out, "kb": os.path.getsize(out) // 1024})
    return made


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--outdir", required=True)
    a = ap.parse_args()
    made = build(a.video, a.outdir)
    print(f"\n🎛️  نسخ المنصات من {os.path.basename(a.video)}")
    for m in made:
        print(f"   ✅ {m['variant']:<8} {os.path.basename(m['path'])} ({m['kb']}KB)")
    print("   ⚠️  راجع feed45/square بعينك: القص مركزي وقد يقترب من النصوص الجانبية.\n")


if __name__ == "__main__":
    main()

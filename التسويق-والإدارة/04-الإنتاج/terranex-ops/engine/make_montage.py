#!/usr/bin/env python3
"""make_montage.py — مونتاج متقاطع من عدة لقطات (MoviePy — برخصة MIT، Zulko/moviepy).

  python engine/make_montage.py --clips c1.mp4 c2.mp4 [--trims 0:4,2:6] \\
      --out output/montage.mp4 [--size 1080x1920] [--fps 30]

لماذا MoviePy؟ «المونتاج المتقاطع من أكثر من مصدر» (قاعدة الإنتاج 4) كان بلا محرك:
make_reel_from_footage لقطعة واحدة، والأداة المرجعية القديمة (OpenMontage) غير موجودة.
MoviePy أثبتت في اختبار معزول: تركيب لقطتين حقيقيتين من نماذج النشر بصوتهما في 15 ثانية.

القواعد:
  • توحيد المقاس والـfps قبل التركيب (اختلاف مصادر الموبايل طبيعي).
  • لا كابشن/براند هنا — الطبقات تُضاف لاحقًا عبر make_reel_from_footage (مسار واحد).
  • loudnorm −15 LUFS بعد التصدير (توحيد الجهارة).
  • لا صوت مولّد — صوت اللقطات كما هو.
لا شبكة.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def montage(clips: list[str], trims: list[tuple[float, float] | None], out: str,
            size: tuple[int, int], fps: int = 30) -> dict:
    from moviepy import VideoFileClip, concatenate_videoclips

    loaded = []
    for i, (path, trim) in enumerate(zip(clips, trims)):
        clip = VideoFileClip(path)
        if trim:
            clip = clip.subclipped(trim[0], trim[1])
        clip = clip.resized(new_size=size).with_fps(fps)
        loaded.append(clip)
    total = sum(c.duration for c in loaded)
    final = concatenate_videoclips(loaded, method="compose")

    tmp = out + ".tmp.mp4"
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    final.write_videofile(tmp, codec="libx264", audio_codec="aac", fps=fps,
                          ffmpeg_params=["-pix_fmt", "yuv420p", "-profile:v", "high",
                                         "-level", "4.1", "-crf", "20",
                                         "-movflags", "+faststart"], logger=None)
    for c in loaded:
        c.close()
    final.close()

    # توحيد الجهارة في مرور ثانٍ سريع (نفس معيار المنصات)
    ff = _ffmpeg()
    p = subprocess.run([ff, "-y", "-i", tmp, "-af", "loudnorm=I=-15:TP=-1.5:LRA=11",
                        "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", out],
                       capture_output=True, text=True, timeout=900)
    if p.returncode != 0:
        raise SystemExit(f"loudnorm فشل:\n{p.stderr[-800:]}")
    os.remove(tmp)
    return {"clips": len(clips), "duration": round(total, 2),
            "kb": os.path.getsize(out) // 1024}


def parse_trims(spec: str | None, n: int) -> list[tuple[float, float] | None]:
    if not spec:
        return [None] * n
    parts = spec.split(",")
    if len(parts) != n:
        raise SystemExit(f"--trims فيه {len(parts)} مدخلًا مقابل {n} مقطعًا")
    out = []
    for p in parts:
        if p.strip() == "-":
            out.append(None)
        else:
            a, b = p.split(":")
            out.append((float(a), float(b)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", nargs="+", required=True)
    ap.add_argument("--trims", default=None,
                    help='مثال: "0:4,2:6,-" (قصّ أول مقطعين، الثالث كامل)')
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", default="1080x1920")
    ap.add_argument("--fps", type=int, default=30)
    a = ap.parse_args()
    w, h = (int(x) for x in a.size.split("x"))
    r = montage(a.clips, parse_trims(a.trims, len(a.clips)), a.out, (w, h), a.fps)
    print(f"\n🎬 مونتاج: {r['clips']} مقاطع → {os.path.basename(a.out)} "
          f"({r['duration']}ث · {r['kb']}KB)\n")


if __name__ == "__main__":
    main()

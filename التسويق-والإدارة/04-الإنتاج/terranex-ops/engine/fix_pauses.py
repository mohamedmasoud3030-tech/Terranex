#!/usr/bin/env python3
"""fix_pauses.py — قصّ الوقفات الصامتة من فيديو المقدم (تنفيذ محلي، بديل auto-editor).

لماذا محلي؟ auto-editor النسخة الحالية على PyPI «مُنزّل» لباينري Rust يُحمَّل من
خوادم خارج النطاق الشبكي للبيئة — غير قابل للحصول هنا (موثق في مخزون الأدوات).
هذا المحرك يقوم بنفس المهمة عبر ffmpeg فقط:
  • كشف الصمت: silencedetect (نفس الآلية المثبتة في qa_video) — noise=-35dB.
  • عكس المقاطع + هامش أمان صغير عند حدود الكلام.
  • تجميع بلا فقد إطارات + loudnorm -15 LUFS في نفس المرور.

  python engine/fix_pauses.py --in raw.mp4 --out cut.mp4 [--min-pause 0.6] [--margin 0.06]

لا يغيّر أبعاد الفيديو (البراند يُضاف لاحقًا عبر make_reel_from_footage).
لا شبكة · مقطع واحد فقط لكل استدعاء.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys


def _ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def duration(ff: str, path: str) -> float:
    p = subprocess.run([ff, "-hide_banner", "-i", path], capture_output=True, text=True, timeout=120)
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", p.stderr)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0


def silences(ff: str, path: str, noise: str, min_pause: float, dur: float) -> list[tuple[float, float]]:
    p = subprocess.run([ff, "-hide_banner", "-nostats", "-i", path,
                        "-af", f"silencedetect=n={noise}:d={min_pause}", "-vn", "-sn", "-f", "null", "-"],
                       capture_output=True, text=True, timeout=900)
    spans, open_from = [], None
    for line in p.stderr.splitlines():
        m1 = re.search(r"silence_start: ([\d.]+)", line)
        m2 = re.search(r"silence_end: ([\d.]+)", line)
        if m1:
            open_from = float(m1.group(1))
        elif m2 and open_from is not None:
            spans.append((open_from, float(m2.group(1))))
            open_from = None
    if open_from is not None:
        spans.append((open_from, dur))          # صمت ختامي حتى النهاية
    return [(a, b) for a, b in spans if b - a >= min_pause]


def keep_segments(spans: list[tuple[float, float]], dur: float, margin: float) -> list[tuple[float, float]]:
    keeps, cur = [], 0.0
    for a, b in spans:
        keeps.append((cur, max(cur, a - margin)))
        cur = min(dur, b + margin)
    keeps.append((cur, dur))
    return [(a, b) for a, b in keeps if b - a > 0.05]


def cut(inp: str, outp: str, min_pause: float = 0.6, margin: float = 0.06,
        noise: str = "-35dB") -> dict:
    ff = _ffmpeg()
    dur = duration(ff, inp)
    spans = silences(ff, inp, noise, min_pause, dur)
    keeps = keep_segments(spans, dur, margin)
    os.makedirs(os.path.dirname(os.path.abspath(outp)), exist_ok=True)

    if len(keeps) <= 1 and not spans:
        graph = "[0:v]copy[v];[0:a]loudnorm=I=-15:TP=-1.5:LRA=11[a]"
        cmd = [ff, "-y", "-i", inp, "-filter_complex",
               "[0:a]loudnorm=I=-15:TP=-1.5:LRA=11[a]", "-map", "0:v", "-map", "[a]",
               "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", "-c:a", "aac", "-b:a", "160k", outp]
    else:
        parts = "".join(
            f"[0:v]trim=start={a:.3f}:end={b:.3f},setpts=PTS-STARTPTS[v{i}];"
            f"[0:a]atrim=start={a:.3f}:end={b:.3f},asetpts=PTS-STARTPTS[a{i}];"
            for i, (a, b) in enumerate(keeps))
        cat = "".join(f"[v{i}][a{i}]" for i in range(len(keeps))) + \
              f"concat=n={len(keeps)}:v=1:a=1[vc][ac];[ac]loudnorm=I=-15:TP=-1.5:LRA=11[a]"
        cmd = [ff, "-y", "-i", inp, "-filter_complex", parts + cat,
               "-map", "[vc]", "-map", "[a]",
               "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", "-c:a", "aac", "-b:a", "160k", outp]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    if p.returncode != 0:
        raise SystemExit(f"ffmpeg فشل:\n{p.stderr[-1500:]}")
    removed = max(0.0, dur - sum(b - a for a, b in keeps))
    out_dur = duration(ff, outp)
    return {"in_dur": dur, "out_dur": out_dur, "removed": removed,
            "pauses_cut": len(spans), "segments": len(keeps)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", dest="outp", required=True)
    ap.add_argument("--min-pause", type=float, default=0.6, help="أقصر صمت يُقص (ثواني)")
    ap.add_argument("--margin", type=float, default=0.06, help="هامش حول الكلام (ثواني)")
    ap.add_argument("--noise", default="-35dB")
    a = ap.parse_args()
    r = cut(a.inp, a.outp, a.min_pause, a.margin, a.noise)
    print(f"\n✂️  قصّ الوقفات: {a.inp}")
    print(f"   {r['in_dur']:.1f}ث → {r['out_dur']:.1f}ث | اتشال {r['removed']:.1f}ث "
          f"({r['pauses_cut']} وقفة · {r['segments']} مقطع)\n")


if __name__ == "__main__":
    main()

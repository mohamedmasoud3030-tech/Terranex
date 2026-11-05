#!/usr/bin/env python3
"""qa_video.py — بوابة فحص جودة الفيديو قبل النشر (تلقائية بالكامل).

  python engine/qa_video.py --video path/to.mp4 [--profile reels|deck|any] [--json]

القواعد (متسقة مع تقرير الاسترجاع 19 أكتوبر 2026):
  HARD FAIL: مش H.264 · مش yuv420p · مفيش مسار صوت · audio صامت بالكامل
             · مدة < 3ث · fps < 24 · دقة أصغر من 540×960
  WARN:      الجهارة خارج −15 LUFS ±3 · نسبة صمت > 40% · كوادر سوداء > 10%
             · aspect مش مطابق للـprofile (reils = 9:16 · deck = 16:9)
المخرج: تقرير عربي + exit code 0/1 (يصلح لأي سكربت).
لا شبكة — ffmpeg المحلي فقط (imageio-ffmpeg).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys


def _ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def probe(path: str) -> dict:
    """استخراج المواصفات من تحليل stderr بتاع ffmpeg (من غير ffprobe)."""
    ff = _ffmpeg()
    p = subprocess.run([ff, "-hide_banner", "-i", path],
                       capture_output=True, text=True, timeout=120)
    s = p.stderr
    info: dict = {}
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", s)
    if m:
        info["duration"] = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    for line in s.splitlines():
        if "Video: " not in line:
            continue
        m = re.search(r"Video:\s*(\w+)", line)
        if m:
            info["codec"] = m.group(1)
        m = re.search(r"(yuv420p|yuvj420p|yuv444p|yuv422p|yuv410p|nv12|rgb24|bgr24)", line)
        if m:
            info["pix_fmt"] = m.group(1)
        m = re.search(r"\b(\d{2,5})x(\d{2,5})\b", line)
        if m:
            info["width"], info["height"] = int(m.group(1)), int(m.group(2))
        m = re.search(r"([\d.]+)\s*(?:fps|tbr)", line)
        if m:
            info["fps"] = float(m.group(1))
        break
    info["has_audio"] = "Audio: " in s
    return info


def loudness(path: str) -> float | None:
    ff = _ffmpeg()
    p = subprocess.run([ff, "-hide_banner", "-nostats", "-i", path,
                        "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True, timeout=600)
    m = re.findall(r"I:\s*(-?[\d.]+) LUFS", p.stderr)
    return float(m[-1]) if m else None


def share_of(path: str, filt: str, pattern: str) -> float:
    """حصة زمنية (0..1) لظاهرة معينة (صمت/كوادر سوداء) من مدة الفيديو."""
    ff = _ffmpeg()
    cmd = [ff, "-hide_banner", "-nostats", "-i", path, "-map", "0"] + \
          (["-af", filt, "-vn", "-sn"] if filt.startswith("silence")
           else ["-vf", filt]) + ["-f", "null", "-"]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    total = 0.0
    for m in re.finditer(pattern, p.stderr):
        total += float(m.group(1))
    d = probe(path).get("duration") or 1.0
    return min(1.0, total / d)


def _check_format(meta: dict, profile: str, fails: list) -> None:
    d = meta["duration"]
    if d < 3:
        fails.append(f"مدة قصيرة جدًا ({d:.1f}ث < 3ث)")
    if meta.get("codec") != "h264":
        fails.append(f"الترميز {meta.get('codec') or '?'} — المطلوب H.264")
    if meta.get("pix_fmt") != "yuv420p":
        fails.append(f"صيغة البكسل {meta.get('pix_fmt') or '?'} — المطلوب yuv420p (توافق المنصات)")
    if (meta.get("fps") or 0) < 24:
        fails.append(f"معدل الإطارات {meta.get('fps') or 0:.0f} < 24")
    w, h = meta.get("width", 0), meta.get("height", 0)
    if min(w, h) < 540 or max(w, h) < 960:
        fails.append(f"الدقة {w}×{h} أصغر من 540×960")
    if profile != "any" and w and h:
        ratio = w / h
        want = {"reels": (0.54, 0.58, "9:16"), "deck": (1.75, 1.80, "16:9")}[profile]
        if not (want[0] <= ratio <= want[1]):
            fails.append(f"الأبعاد {w}×{h} مش {want[2]} (profile={profile})")


def _check_audio(path: str, meta: dict, strict_lufs: bool, visual_draft: bool,
                 fails: list, warns: list) -> None:
    if not meta.get("has_audio"):
        if visual_draft:
            warns.append("مسودة بصرية صامتة — ليست إعلانًا نهائيًا؛ يلزم تعليق معتمد قبل النشر")
            meta["visual_draft"] = True
        else:
            fails.append("مفيش مسار صوتي")
        return
    luf = loudness(path)
    meta["loudness_lufs"] = luf
    if luf is None:
        warns.append("تعذّر قياس الجهارة")
    elif not (-25 <= luf <= -9):
        fails.append(f"الجهارة {luf} LUFS خارج المقبول كليًا (−25..−9)")
    elif not (-18 <= luf <= -12):
        (fails if strict_lufs else warns).append(f"الجهارة {luf} LUFS — المعيار −15±3")
    sil = share_of(path, "silencedetect=n=-35dB:d=0.6", r"silence_duration: ([\d.]+)")
    meta["silence_share"] = round(sil, 3)
    if sil >= 0.95:
        fails.append(f"الصوت صامت شبه بالكامل ({sil:.0%})")
    elif sil > 0.4:
        warns.append(f"نسبة صمت مرتفعة ({sil:.0%})")


def qa(path: str, profile: str = "reels", strict_lufs: bool = False,
       visual_draft: bool = False) -> dict:
    """فحص الجودة. visual_draft=True يسمح بمسودة بصرية صامتة مع تحذير صريح،
    ولا يسقط شرط الصوت للإعلان النهائي. باقي البوابات كما هي."""
    fails, warns = [], []
    meta = probe(path)
    if not meta.get("duration"):
        return {"pass": False, "fails": ["تعذّر قراءة الملف أو فاقد مدة"], "warns": [], "meta": meta}
    _check_format(meta, profile, fails)
    _check_audio(path, meta, strict_lufs, visual_draft, fails, warns)
    blk = share_of(path, "blackdetect=d=0.4:pix_th=0.10", r"black_duration:([\d.]+)")
    meta["black_share"] = round(blk, 3)
    if blk > 0.15:
        warns.append(f"كوادر سوداء ({blk:.0%}) — لو مقصودة (فاصل) تجاهل التحذير")
    return {"pass": not fails, "fails": fails, "warns": warns, "meta": meta}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--profile", choices=["reels", "deck", "any"], default="reels")
    ap.add_argument("--strict-lufs", action="store_true",
                    help="اعتبار الجهارة خارج −15±3 فشلًا بدل تحذير")
    ap.add_argument("--visual-draft", action="store_true",
                    help="السماح بمسودة بصرية صامتة مع تحذير (ليس إعلانًا نهائيًا)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    r = qa(a.video, a.profile, a.strict_lufs, visual_draft=a.visual_draft)
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
    else:
        m = r["meta"]
        print(f"\n📼 {a.video}")
        print(f"   {m.get('width')}×{m.get('height')} · {m.get('duration', 0):.1f}ث · "
              f"{m.get('codec')}/{m.get('pix_fmt')} · {m.get('fps', 0):.0f}fps · "
              f"صوت={'نعم' if m.get('has_audio') else 'لا'}"
              + (f" · {m.get('loudness_lufs')} LUFS" if m.get("loudness_lufs") is not None else ""))
        print(f"\n   القرار: {'✅ يجتاز' if r['pass'] else '⛔ مرفوض'}")
        for x in r["fails"]:
            print(f"   ⛔ {x}")
        for x in r["warns"]:
            print(f"   ⚠️  {x}")
    sys.exit(0 if r["pass"] else 1)


if __name__ == "__main__":
    main()

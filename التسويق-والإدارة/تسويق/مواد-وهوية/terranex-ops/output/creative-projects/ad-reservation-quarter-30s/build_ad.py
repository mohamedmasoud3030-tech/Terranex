#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""حملة الحجز — إعلان رأسي ٩:١٦ من فيديو حقيقي فقط (B4).

خط التصنيع: استراتيجي → مدير إبداعي → كاتب → مونتير → منتج.
لا صور مولّدة، لا أصوات غريبة، لا ذكر مدينة (B9).
"""
import json, os, shutil, subprocess, sys

ROOT = "/home/user/terranex/التسويق-والإدارة/تسويق/مواد-وهوية/terranex-ops"
PROJ = os.path.join(ROOT, "output/creative-projects/ad-reservation-quarter-30s")
SRC = "/home/user/tn_work/camp/media"
VOD = "/home/user/tn_work/camp/vo"
sys.path.insert(0, os.path.join(ROOT, "engine"))
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()

for d in ("media", "render", "_amb", "vo"):
    os.makedirs(os.path.join(PROJ, d), exist_ok=True)

# ---------- ١) مدير إبداعي: اختيار اللقطات (كلها فيديو حقيقي مفحوص) ----------
SHOTS = [
    # (ملف, start, end, سبب الاختيار) — كل النوافذ مفحوصة إطارًا بإطار: صفر وجه بشري
    ("gh-a28.mp4", 2.0, 6.4,  "كبش برقي في الفناء — الهوك"),
    ("gh-a26.mp4", 2.0, 8.4,  "خروف يمشي حر — الفري رينج"),
    ("gh-a27.mp4", 2.0, 5.0,  "على ميزان TerraNex — إيدين فقط بلا وجه"),
    ("gh-a31.mp4", 0.5, 2.6,  "دفع الحيوان ناحية الميزان — ظهره للكاميرا"),
    ("gh-a38.mp4", 7.5, 10.5, "رفع الخروف للوزن — ذراعين فقط"),
    ("gh-a39.mp4", 2.0, 5.4,  "تحميل على السيارة — التوصيل"),
    ("gh-a17.mp4", 8.0, 13.4, "القطيع على المعلف — ختام بصري"),
]

for fn, *_ in SHOTS:
    dst = os.path.join(PROJ, "media", fn)
    s = os.path.join(SRC, fn)
    if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(s):
        shutil.copy2(s, dst)

# ---------- ٢) كاتب: السكربت (جديد بالكامل — لا يكرر أي فيديو سابق) ----------
VO = {
    "k1": {"t": 0.40, "text": "باب الحجز مفتوح… ربع خروف برقي حر."},
    "k2": {"t": 5.25, "text": "متوسط الأوزان… أربعة وأربعين كيلو للخروف."},
    "k3": {"t": 10.30, "text": "الكيلو قايم بميتين وسبعين جنيه… والذبح والتنظيف والتغليف سبعمية جنيه."},
    "k4": {"t": 17.30, "text": "يعني الربع يطلعلك حوالي تلات آلاف ومية جنيه… شامل كل حاجة."},
    "k5": {"t": 22.80, "text": "والتوصيل لحد باب بيتك… احجز واتساب."},
}
CAPTIONS = [
    {"from": 0.45, "to": 4.20, "text": "باب الحجز مفتوح · ربع برقي حر"},
    {"from": 4.70, "to": 8.60, "text": "الخروف متوسط ٤٤ كيلو"},
    {"from": 8.90, "to": 14.20, "text": "الكيلو ٢٧٠ جنيه · خدمات ٧٠٠"},
    {"from": 14.60, "to": 19.00, "text": "الربع ≈ ٣١٠٠ جنيه شامل كل حاجة"},
    {"from": 19.30, "to": 22.60, "text": "التوصيل لحد باب بيتك · واتساب"},
]
ENDCARD = {
    "headline": "احجز ربعك",
    "subtitle": "واتساب فقط",
    "cta": "01010154221",
    "disclosure": "تعليق صوتي مولّد · لقطات حقيقية ١٠٠٪",
}

clips = [{"path": f"media/{fn}", "start": s, "end": e, "crop": {"top": 0.0},
          "sharpen": False, "scale_flags": "lanczos"} for fn, s, e, _ in SHOTS]

spec = {
    "project": "ad-reservation-quarter-30s",
    "title": "احجز ربعك",
    
    "voice": {
        "voice_id": "voice-00",
        "approval_note": ("سكربت جديد خاص بحملة الحجز — لا يكرر أي جملة من أي فيديو سابق. "
                          "لقطات أرشيف حقيقية ١٠٠٪، بلا أي شخص ظاهر بوجهه."),
        "sha256": "",
        "transcript_verification": "human-reviewed",
        "transcript": [v["text"] for v in VO.values()],
    },
    "clips": clips,
    "captions": CAPTIONS,
    "endcard_sec": 2.6,
    "endcard": ENDCARD,
    "audio": {"original_gain": 0.0, "ambient_from": 0},
    "on_screen_persons": [],
    "consent_persons": [],
    "format": "video",
}
with open(os.path.join(PROJ, "spec.json"), "w", encoding="utf-8") as f:
    json.dump(spec, f, ensure_ascii=False, indent=2)

# ---------- ٣) أمبينس حقيقي من الأرشيف (بلا كلام بشري) ----------
amb = os.path.join(PROJ, "_amb", "farm.wav")
if not os.path.exists(amb):
    subprocess.run([FF, "-y", "-v", "error", "-ss", "5.6", "-t", "34",
                    "-i", os.path.join(SRC, "gh-a17.mp4"), "-vn",
                    "-af", "highpass=f=140,lowpass=f=6000", "-ar", "48000", "-ac", "2", amb], check=True)

# ---------- ٤) مونتير: رندر صامت ----------
silent = os.path.join(PROJ, "render", "master-silent.mp4")
subprocess.run([sys.executable, os.path.join(ROOT, "engine/reel_build.py"),
                "--spec", os.path.join(PROJ, "spec.json"), "--out", silent], check=True,
               cwd=ROOT, stdout=subprocess.DEVNULL)

# ---------- ٥) منتج: تركيب الصوت (تعليق + أمبينس مع دك) ----------
# بناء مسار التعليق
vo_wav = os.path.join(PROJ, "vo", "vo-track.wav")
inputs = []
for k in VO:
    inputs += ["-i", os.path.join(VOD, f"{k}.mp3")]
parts = []
n = len(VO)
for i, (k, v) in enumerate(VO.items()):
    ms = int(v["t"] * 1000)
    parts.append(f"[{i}:a]adelay={ms}|{ms},aresample=48000[a{i}]")
mixv = "".join(f"[a{i}]" for i in range(n))
filt = ";".join(parts) + f";{mixv}amix=inputs={n}:normalize=0[vo]"
subprocess.run([FF, "-y", "-v", "error"] + inputs + ["-filter_complex", filt,
                "-map", "[vo]", "-ac", "2", "-ar", "48000", vo_wav], check=True)

final = os.path.join(PROJ, "render", "ad-reservation-quarter-30s.mp4")
total = sum(c["end"] - c["start"] for c in clips) + spec["endcard_sec"]
af = (f"[1:a]atrim=0:{total:.3f},volume=0.55,afade=t=in:st=0:d=0.6,"
      f"afade=t=out:st={total-1.2:.3f}:d=1.2[amb];"
      f"[2:a]apad,asplit=2[vo1][vo2];"
      f"[amb][vo1]sidechaincompress=threshold=0.04:ratio=6:attack=8:release=320[duck];"
      f"[duck][vo2]amix=inputs=2:normalize=0,loudnorm=I=-15:TP=-1.5:LRA=11[out]")
subprocess.run([FF, "-y", "-v", "error", "-i", silent, "-stream_loop", "-1", "-i", amb,
                "-i", vo_wav, "-filter_complex", af, "-map", "0:v", "-map", "[out]",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
                "-movflags", "+faststart", "-shortest", final], check=True)

print(json.dumps({"out": final, "bytes": os.path.getsize(final), "total_sec": round(total, 2)}, ensure_ascii=False))

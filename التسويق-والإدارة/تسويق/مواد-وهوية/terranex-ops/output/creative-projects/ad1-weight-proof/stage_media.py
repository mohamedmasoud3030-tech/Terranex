#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""تجهيز وسائط AD-1 من نسخ الاستيعاب إلى مجلد المشروع — روابط صلبة، بلا نسخ بايتات جديدة.

لماذا روابط صلبة لا روابط رمزية؟
  حاجز المسارات في reel_build يفكّ الروابط الرمزية (realpath) ويرفض ما يخرج عن جذور
  مسموحة. الرابط الصلب ملف حقيقي داخل الجذر المسموح، فيبقى الحاجز كما هو بلا تخفيف،
  ولا تُنسخ البايتات مرتين على القرص.

التشغيل بعد استعادة المستودع في جلسة جديدة:
  1) اجلب مراجع الفروع (الأوامر في media-manifest.json)
  2) شغّل extract_github_branches.py
  3) شغّل هذا الملف
"""
import hashlib
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
G = os.path.join(OPS, "archive-intake", "github-branches")

man = json.load(open(os.path.join(G, "manifest.json"), encoding="utf-8"))
vr = json.load(open(os.path.join(G, "visual-review.json"), encoding="utf-8"))["assets"]
prev = json.load(open(os.path.join(HERE, "media-manifest.json"), encoding="utf-8"))
by = {a["file_name"]: a for a in man["assets"]}

os.makedirs(os.path.join(HERE, "media"), exist_ok=True)
rows, ok = [], 0
for want in prev["assets"]:
    aid = want["asset_id"]
    v = vr[aid]
    a = by[v["file_name"]]
    src = a["working_copy"]
    if not os.path.isfile(src):
        raise SystemExit(f"نسخة الاستيعاب مفقودة: {src}\nشغّل extract_github_branches.py أولًا.")
    dst = os.path.join(HERE, "media", os.path.basename(src))
    if not os.path.exists(dst):
        try:
            os.link(src, dst)
            mode = "hardlink"
        except OSError:
            shutil.copy2(src, dst)
            mode = "copy"
    else:
        mode = "exists"
    h = hashlib.sha256(open(dst, "rb").read()).hexdigest()
    if h != a["sha256"]:
        raise SystemExit(f"⛔ SHA-256 مختلف لـ{aid} — لا إنتاج على مادة غير مطابقة.")
    ok += 1
    rows.append({**want, "staged_path": os.path.relpath(dst, HERE), "staging_mode": mode})

prev["assets"] = rows
with open(os.path.join(HERE, "media-manifest.json"), "w", encoding="utf-8") as f:
    json.dump(prev, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"staged+verified {ok}/{len(rows)} assets")

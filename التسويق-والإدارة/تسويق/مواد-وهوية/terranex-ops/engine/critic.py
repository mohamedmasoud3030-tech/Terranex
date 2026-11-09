#!/usr/bin/env python3
"""critic.py — بوّابة الالتزام. قواعد قابلة للتشغيل مش نصايح.

  python engine/critic.py --file output/caption.txt
  python engine/critic.py --text "استثمار آمن بعائد مضمون 30%"
  echo "..." | python engine/critic.py -
"""
from __future__ import annotations

import argparse
import json
import re
import sys

# (code, نوع, regex, رسالة, إصلاح)
RULES = [
    ("B1", "hard", r"(عائد|ربح|مكسب|نسبة)\s*(مضمون|مؤكد|مضمونة|مؤكدة|ثابت)",
     "وعد ربح مضمون", "استبدله بـ«عائد متوقع حسب العقد» أو احذف النسبة."),
    ("B1b", "hard", r"\d{1,3}\s*%", "نسبة مئوية بدون مصدر", "أي نسبة لازم تكون موثقة ومكتوب مصدرها."),
    ("B2", "hard", r"(بدون|بلا)\s*(مخاطر|خسارة|مشاكل)|آمن\s*(تمام|١٠٠|100)",
     "ادعاء «بدون مخاطر»", "اكتب المخاطرة بصراحة — الصدق بيبيع أكتر."),
    ("B2b", "hard", r"(مضمون|ضمان)\s*(الربح|الأرباح|العائد)", "ضمان ربح", "احذف كلمة ضمان نهائيًا."),
    ("B5", "hard", r"(عائد|ربح)\s*\d", "رقم ربح بدون سياق", "أضف مصدر الرقم أو احذفه."),
    ("B8", "hard", r"(أحسن|افضل|أفضل)\s+من\s+شركة", "مقارنة مباشرة بمنافس", "اتكلم عن نفسك بدون ذكر منافس."),
    # B9 (19/10 — طلب المالك): ممنوع ذكر المدينة صوتًا أو نصًا في أي محتوى للشركة
    ("B9", "hard", r"(الإسكندرية|الاسكندرية|اسكندرية|اسكندريه|Alexandria|ALEXANDRIA)",
     "ذكر المدينة «الإسكندرية» ممنوع في محتوى الشركة",
     "احذف اسم المدينة نهائيًا — استخدم «استثمار حيواني · ثروة حقيقية»."),
    ("S4", "soft", r"[😀-🿿]", "إيموجي", "قلّل الإيموجي لأربعة أو أقل في الكابشن."),
    ("S7", "soft", r"(سحب|استرداد)\s*(فلوس|المبلغ).{0,20}(في أي وقت|فورا|فورًا)",
     "وعد سيولة", "اشرح شروط الخروج بدل الوعد المفتوح."),
    ("S3", "soft", r"(كلمنا|اتصل|ابعت).{0,10}(واتساب|على الواتس)",
     "CTA مباشر — يُفضّل الرد في التعليقات أولًا", "خليه CTA تاني أو ابدأ بالرد في التعليقات."),
]

HASHTAG_OK = {"#TerraNex", "#استثمار_حيواني", "#ثروة_حيوانية", "#تربية_حيوانية"}
PHONE = "01010154221"


CITY_PAT = r"(الإسكندرية|الاسكندرية|اسكندرية|اسكندريه|Alexandria|ALEXANDRIA)"


def lint_city(text: str) -> list:
    """بوابة B9 — أي ظهور للمدينة في نص/كابشن/سكربت يُرفض قبل التسليم."""
    return [m.group(0) for m in re.finditer(CITY_PAT, text or "")]


def check(text: str, platform: str = "facebook", allow_delivery_city: bool = False) -> dict:
    t = text.strip()
    hits = []
    for code, kind, pat, msg, fix in RULES:
        if code == "B9" and allow_delivery_city:
            continue
        for m in re.finditer(pat, t):
            hits.append({"code": code, "kind": kind, "match": m.group(0), "msg": msg, "fix": fix})
            break

    # S2 ذكي: ما يزقّش لو التنويه موجود فعلًا
    if re.search(r"استثمار", t) and not re.search(r"(مخاطر|مخاطرة|مخاطره)", t):
        hits.append({"code": "S2", "kind": "soft", "match": "استثمار", "msg": "ذكر «استثمار» بدون تنويه المخاطرة",
                     "fix": "أضف سطر: «الاستثمار فيه مخاطرة — اقرأ العقد الأول»."})

    # قواعد طول
    first = t.split("\n")[0]
    if len(first) > 60:
        hits.append({"code": "S8", "kind": "soft", "match": first[:40] + "…",
                     "msg": f"السطر الأول {len(first)} حرف (الحد 60)", "fix": "اقصر السطر الأول لـ hook."})
    max_len = 600 if platform.lower() in ("linkedin", "linked_in") else 220
    if len(t) > max_len:
        hits.append({"code": "S5", "kind": "soft", "match": f"{len(t)} حرف",
                     "msg": f"الكابشن أطول من {max_len}", "fix": "اقطع الزيادة أو انقلها لأول تعليق."})

    # CTA مكرر
    cta = len(re.findall(r"(واتساب|ابعت|كلمنا|احجز|اشترك|سجل)", t))
    if cta > 2:
        hits.append({"code": "S9", "kind": "soft", "match": f"{cta} CTA",
                     "msg": "أكتر من CTA واحد", "fix": "خلّي CTA واحد بس."})

    # رقم الهاتف بصيغة غلط
    if re.search(r"\+?20\s*1", t) or re.search(r"01\d{2}\s\d{3}\s\d{3}", t):
        hits.append({"code": "R3", "kind": "soft", "match": "صيغة رقم",
                     "msg": "رقم الواتساب مش بالصيغة الموحدة", "fix": f"اكتبه {PHONE} بدون مسافات."})

    # هاشتاجات
    tags = re.findall(r"#[\w\u0621-\u064A_]+", t)
    if len(tags) < 3:
        hits.append({"code": "R6", "kind": "soft", "match": f"{len(tags)} هاشتاج",
                     "msg": "هاشتاجات أقل من 3", "fix": "أضف 2 ثابتة + 1 للموضوع."})
    if len(tags) > 6:
        hits.append({"code": "R6b", "kind": "soft", "match": f"{len(tags)} هاشتاج",
                     "msg": "هاشتاجات أكتر من 6", "fix": "قلّل لـ6 أقصى."})
    if "#TerraNex" not in t and platform.lower() not in ("whatsapp",):
        hits.append({"code": "R7", "kind": "soft", "match": "—",
                     "msg": "علامة TerraNex ناقصة", "fix": "أضف #TerraNex."})

    hard = [h for h in hits if h["kind"] == "hard"]
    soft = [h for h in hits if h["kind"] == "soft"]
    score = max(0, 100 - 34 * len(hard) - 9 * len(soft))
    text_decision = "ارفض" if hard or score < 70 else ("عدّل" if score < 85 else "انشر")
    # هذا قرار النص فقط. جاهزية النشر تحتاج فيديو/صوت/موافقة مالك ولا تُحسم هنا.
    return {"score": score, "decision": text_decision, "text_decision": text_decision,
            "scope": "text-only", "publication_ready": False,
            "hard": hard, "soft": soft, "chars": len(t), "cta_count": cta, "tags": len(tags)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file")
    ap.add_argument("--text")
    ap.add_argument("--platform", default="facebook")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--allow-delivery-city", action="store_true")
    a = ap.parse_args()

    if a.file:
        text = open(a.file, encoding="utf-8").read()
    elif a.text:
        text = a.text
    else:
        text = sys.stdin.read()

    r = check(text, a.platform, allow_delivery_city=a.allow_delivery_city)
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return
    print(f"\nقرار النص فقط (ليس قرار نشر): {r['text_decision']}   |   الدرجة: {r['score']}/100   |   {r['chars']} حرف")
    print("جاهزية النشر تحتاج فحص الفيديو والصوت وموافقة المالك — لا تُحسم من النص وحده.")
    if r["hard"]:
        print("\n⛔ Hard Ban:")
        for h in r["hard"]:
            print(f"  [{h['code']}] {h['msg']} — «{h['match']}»\n        إصلاح: {h['fix']}")
    if r["soft"]:
        print("\n⚠️  Soft Flag:")
        for h in r["soft"]:
            print(f"  [{h['code']}] {h['msg']}\n        إصلاح: {h['fix']}")
    if not r["hard"] and not r["soft"]:
        print("✅ مفيش مخالفات. جاهز للنشر بعد التأكد من وجود لقطة حقيقية.")


if __name__ == "__main__":
    main()

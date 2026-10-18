# TerraNex Ops

نظام تشغيل محتوى صفحة شركة TerraNex — مهارة واحدة، ٦ أوامر، ٤ ملفات سياق، ومحرّك تنفيذ فعلي.

**مش خطة. كله بيشتغل من غير أي API key.**

---

## التشغيل السريع

```bash
cd terranex-ops

# 1) بوستر
python engine/make_poster.py --headline "الوزن على الطبيعة" --stat 50 --unit "كجم" \
    --sub "الخروف ده قدامك على الميزان — مش كلام في بوست" --out output/poster.png

# 2) ريل (٢٠–٣٥ ثانية) من سكربت JSON
python engine/make_video.py --script output/script-friday.json --out output/reel.mp4

# 3) ريل بصوتكم الحقيقي (ممنوع أي TTS)
python engine/make_video.py --script output/script-friday.json --voice recording.m4a --out output/reel.mp4

# 4) بوابة الالتزام
python engine/critic.py --file output/caption-friday.txt

# 5) تقويم ٣٠ يوم
python engine/gen_calendar.py --days 30 --out output/calendar-30d.md

# 6) تقرير التعلّم من أرقام الأسبوع
python engine/learn.py --csv data/week-01.csv --append
```

### المتطلبات
- Python 3.10+ · Pillow ≥ 9 (مع دعم **raqm** للتشكيل العربي)
- FFmpeg (يُثبَّت تلقائيًا عبر `pip install imageio-ffmpeg`)
- خطوط: `assets/fonts/Tajawal-*.ttf` + `Cairo-VF.ttf` (موجودة)

---

## البنية

```
SKILL.md                 # الراوتر: أي طلب → واحد من 6 أوامر
context/
  product-marketing.md   # الجمهور، الوعد، النبرة، أوقات النشر
  brand-kit.md           # design tokens تنفّذها المحركات فعليًا
  compliance.md          # B1–B8 (رفض) + S1–S9 (مراجعة) + R1–R7 (لازم)
  learnings.md           # حقائق مثبتة + hooks مستهلكة + baseline
commands/                # 6 عقود مخرجات موحّدة
engine/
  brand.py               # tokens + رسم عربي (PIL + libraqm)
  make_poster.py         # 1080×1350 / 1080×1920 / 1:1 × ثيمين
  make_video.py          # 9:16، ffmpeg pipe، بدون صوت مولّد
  critic.py              # 17 قاعدة قابلة للتشغيل
  gen_calendar.py        # 30 يوم بلا تكرار محور أو hook
  learn.py               # CSV أسبوعي → قرارات مكتوبة
output/                  # الأصول + queue.csv
data/                    # أرقام الأسابيع
```

---

## ضمانات مبنية في الكود (مش نصايح)

| الضمان | فين |
|---|---|
| العربي متشكّل صح واتجاهه RTL | `brand.text()` — `direction="rtl", language="ar"` |
| ممنوع صوت مولّد | `make_video.py` بياخد `--voice` فقط، ومفيش أي TTS |
| ممنوع وعود ربح | `critic.py` قواعد B1 / B1b / B2 |
| رقم الواتساب بصيغة موحّدة | `brand.PHONE` + قاعدة R3 |
| مفيش hook متكرر ١٤ يوم | `learnings.md` + `gen_calendar.py` |
| كل يوم ليه مصدر فوتاج | عمود «مصدر الفوتاج» — أو «تصوير مطلوب» صراحة |

---

## الحلقة الأسبوعية

```
/idea → /script → /edit → /caption → /review → queue.csv
                                        ↓
              كل جمعة: learn.py --append → learnings.md
```

---

## نتائج التشغيل الفعلي (18 أكتوبر 2026)

- `poster-weight.png` — 1080×1350، 104KB
- `poster-story-dark.png` / `poster-story-light.png` — 1080×1920
- `reel-friday.mp4` — 20 ثانية، 500 إطار، 400KB، H.264
- `calendar-30d.md` — 30 يوم موزّعين على 5 محاور
- `critic.py` — كابشن سليم: **100/100** · نص مخالف: **0/100** بـ4 Hard Bans
- `learn.py` — 7 بوستات → 5 قرارات مرتبة بالأثر

---

## اللي لسه محتاج بشري

1. **التصوير:** الأيام المكتوب عليها «تصوير مطلوب» لازم تتصور من المزرعة.
2. **الصوت:** تسجيل حقيقي من الفريق يُمرَّر بـ`--voice`.
3. **الموافقة النهائية:** `critic.py` بيوقف المخالف، لكن قرار «انشر» النهائي بشري.

---

## تحديث 18 أكتوبر 2026 — قرارات المالك

1. **الصوت المولّد مسموح الآن** (كان ممنوعًا بقرار سابق). القاعدة الجديدة في `context/compliance.md §3.5`:
   - المفضّل يفضل الصوت الأصلي من ريل المزرعة.
   - الصوت المولّد للتقديم/الشرح/الـCTA أو النسخة الإنجليزية.
   - أي استنساخ لصوت شخص لازم تصريح كتابي.

2. **بناء ريل من فوتاج حقيقي** — أداة جديدة:
```bash
python engine/make_reel_from_footage.py \
  --video ../google_drive/04-الأربعاء-الوزن-على-الطبيعة.mp4 \
  --captions output/captions-04.json \
  --out output/reel-weight-branded.mp4

# بصوت مولّد (اختياري)
python engine/make_reel_from_footage.py --video in.mp4 --captions c.json \
  --voice-over tts.mp3 --out out.mp4
```
- بيعيد بناء الفيديو بإطار-بإطار: بار هوية علوي يغطي النص المحروق في المصدر، ورقم واتساب سفلي، وكابشن محروق بالتشكيل العربي الصحيح، وend card.
- الصوت الأصلي بينتقل بـ`loudnorm` (I=-15) — أو يُستبدل بـ`--voice-over`.

3. **نتيجة التشغيل:** `output/reel-weight-branded.mp4` — 22.1 ثانية، 1080×1920، صوت أصلي، 13.5MB.

# 🛠️ OPS — تشغيل عملية تسويق TerraNex (الدليل الحاكم للوكيل والمستخدم)

> اقرأ `SKILL.md` أولًا (الأوامر التسعة والقواعد)، وهذا الملف لكيفية التشغيل اليومي وسلامة النظام.
> كل أمر هنا مُختبر فعليًا آخر مرة بتاريخ 19 أكتوبر 2026 عبر `engine/selfcheck.py` (15/15).
> القرارات المتخذة حيال الأدوات المفتوحة المصدر (تبني/رفض/حدود): `studio/مخزون-الأدوات-المفتوحة.md`.
> وكيل AI جديد؟ ابدأ أولًا من `../../../وكيل-AI-ابدأ-هنا.md` (دورك/حدودك/انطلاقك الذاتي).

## 0) إعداد جلسة جديدة (30 ثانية)
```bash
cd التسويق-والإدارة/تسويق/مواد-وهوية/terranex-ops
bash setup.sh          # ينتهي بتشغيل selfcheck تلقائيًا
```
التبعيات تُثبّت على مستوى المستخدم فقط (`pip --user`) — لا sudo ولا تعديل للنظام.

## 1) خريطة سير العمل الكاملة

```
[المستخدم: تصوير موبايل] ← الوحيد اليدوي غير النشر
        ↓  يحط اللقطات في تسويق/مواد-خام/وارد/
ingest_footage   ← تنظيم + رفض مكرر + سجل FX
        ↓
/idea → /script → /caption (critic)    ← أفكار وسكريبتات وكابشنات
        ↓
/edit: make_poster | make_video | make_reel_from_footage | make_scenario
        ↓
qa_video (جودة تقنية) + critic (التزام)   ← بوابتان آليّتان
        ↓
package_post ← قيد في output/queue.csv بحالة «بانتظار-موافقة»
        ↓  (+ make_variants عند الحاجة لنسخ المنصات)
[المستخدم: ينشر يدويًا] ← بوابة بشرية دائمة (لا نشر آلي)
        ↓  بعد النشر يحوّل الحالة إلى «منشور»
الجمعة: أرقام الأسبوع في CSV → learn.py ← تحديث learnings.md بموافقة المستخدم
```

## 2) الأدوات التنفيذية (استدعاءات جاهزة)
| المهمة | الأمر |
|---|---|
| فحص النظام بالكامل | `python engine/selfcheck.py` (أو `--quick`) |
| استلام وتنظيم فوتاج | `python engine/ingest_footage.py` / `--dry` |
| بوستر/ستوري بهوية الشعار | `python engine/make_poster.py --headline "…" --stat 50 --unit "كجم" --sub "…" --out output/p.png` |
| ريل موشن 9:16 من سكربت | `python engine/make_video.py --script s.json [--voice حقيقي.mp3] --out output/r.mp4` |
| ريل براند من لقطة حقيقية | `python engine/make_reel_from_footage.py --video fx.mp4 --captions c.json --out output/r.mp4` |
| مونتاج متقاطع (2+ لقطة) | `python engine/make_montage.py --clips a.mp4 b.mp4 --trims "0:4,2:6" --out output/m.mp4` |
| قصّ وقفات فيديو كلام | `python engine/fix_pauses.py --in raw.mp4 --out cut.mp4 [--min-pause 0.6]` |
| تنسيق حملة متكاملة | `python engine/campaign_run.py --brief campaigns/<موجز>.json --register` (جدولة بلا تكرار + قالب قياس تلقائي) |
| قياس أسبوعي وتحسين | `python engine/measure.py --csv data/week-NN.csv --prev data/week-NN-1.csv --append` |
| نسخ المنصات (reels/4:5/1:1) | `python engine/make_variants.py --video m.mp4 --outdir output/variants/x` |
| فحص جودة فيديو | `python engine/qa_video.py --video v.mp4 --profile reels` |
| فحص التزام نص | `python engine/critic.py --file cap.txt` |
| **بناء ريل بالهوية الثابتة** | `python engine/reel_build.py --spec spec.json --voice vo.mp3 --out x.mp4` |
| اختبارات reel_build (قصّ/علامة/تزامن/مسارات/توافق) | `python -m unittest discover -s tests -p 'test_*.py'` (مضمّنة في selfcheck) |
| تجهيز منشور للجدول | `python engine/package_post.py --video v.mp4 --caption cap.txt --platforms "facebook,instagram" --date … --time 20:00 [--variants]` |
| تقويم محتوى | `python engine/gen_calendar.py --days 7 --out output/calendar.md` |
| تحليل أداء أسبوعي | `python engine/learn.py --csv data/week-XX.csv [--append]` |
| لوحة الألوان من الشعار | `python engine/derive_palette.py [--print]` |

ملكية واستدعاء الأوامر النصية (`/idea`…`/scenario`) في `commands/`.

## 3) ملفات الحالة (استمرارية الجلسات)
- `output/queue.csv` — جدول النشر: تاريخ/وقت/منصة/فيديو/هوك/درجات/حالة.
- `../../مواد-خام/سجل-المواد-الخام.csv` — سجل الفوتاج الخام (معرفات FX).
- `context/learnings.md` — حقائق وفرضيات وhooks مستهلكة.
- `../../فيديوهات-جاهزة-للنشر/` — النسخ الرسمية السبع.
- `../../../إدارة/وثائق-المشروع/02-حالة-التشغيل.md` — ملخص الحالة للجلسة القادمة.

## 4) حدود تقنية موثقة (لا تدّعي خلافها)
| البند | الحقيقة | البديل العملي |
|---|---|---|
| libraqm في بيئة Pillow | غير متاح (عجلات PyPI بلا raqm) | `engine/artext.py`: HarfBuzz+FreeType — تشكيل عربي مكافئ |
| ffmpeg النظامي | غير مثبت | `imageio-ffmpeg` (باينري pip) — يستخدمه كل المحركات |
| تفريغ صوتي (whisper) | مكتباته ثقيلة ونماذجه على HF خارج النطاق الشبكي | الكابشنات تُكتب من السكربت/النسخة المعروفة وتُحرق عبر make_video/make_reel |
| قصّ وقفات آلي متخصص (auto-editor) | متعذر التحميل في هذه البيئة (باينري خارج النطاق) | `engine/fix_pauses.py` — نفس النتيجة عمليًا، مُختبر |
| TTS عربي محلي (piper) | الأصوات على HF خارج النطاق | أداة الصوت في جلسة Arena (طلب صريح، وسم §3.5) أو تسجيل الفريق |
| قصاصات صور (rembg) | تعارض pillow (انظر المخزون) | knockout السطوع للشعار؛ venv معزول عند الحاجة الفعلية |
| النشر على المنصات | لا تكاملات مخوّلة في هذه الجلسة | جدولة queue.csv + نشر يدوي من مجلد الجاهز |
| TTS عربي | متاح عبر أدوات الجلسة بطلب صريح فقط (compliance §3.5) | يُوسم «تعليق صوتي» في الوصف دائمًا |
| مونتاج آلي لسلسلة لقطات | غير موجود (OpenMontage وهمي) | CapCut للمستخدم أو make_reel للفيديو الواحد |

## 4.b) الهوية الثابتة — قواعد 19/10 (تفصيلها في `context/compliance.md` §1.b و`brand-kit.md` §8.b)
| القاعدة | الأثر على التشغيل |
|---|---|
| **B9 — لا مدينة** | `critic.py` يرفض أي نص فيه «الإسكندرية»؛ `reel_build` يرفض البناء. الكيكر الرسمي: «استثمار حيواني · ثروة حقيقية» |
| **B10 — المالك لا يظهر تلقائيًا** | `personas.json` مصدر الحقيقة؛ `reel_build.require_consent` يوقف البناء بدون `consent_persons` |
| **B11 — علامة مائية موحّدة** | شعار + TerraNex؛ «TerraNex LLC» ممنوعة ومقصوصة من الفوتاج |
| **B12 — شعار كبير** | قفل الشعار ≥ 0.36×W، ومكان ثابت |
| **الصوت الأساسي** | `voice-00` (مصري هادي واثق) لكل تعليق صوتي؛ صوت المالك يحتاج تسجيلًا حقيقيًا |

## 5) قواعد لا تُكسر (ملخص)
1. لا نشر ولا تواصل مع عملاء ولا إنفاق مال بدون موافقة صريحة.
2. مادة حقيقية فقط في محتوى الصفحة؛ الاستثناءات بموافقة مباشرة موثقة (§3.4/§3.5).
3. مصدر واحد لكل منشور (7 مصادر = 7 منشورات — بعدها تصوير مطلوب).
4. لا وعود أرباح ولا أرقام بلا مصدر.
5. أي عدّاد مؤتمت يتوقف عند «بانتظار-موافقة».

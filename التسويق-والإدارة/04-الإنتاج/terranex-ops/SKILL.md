---
name: terranex-ops
description: "محرك التنفيذ الرسمي الوحيد لتسويق وإدارة TerraNex (استثمار حيواني، الإسكندرية). استخدمه لأي طلب على صفحة الشركة أو على عرض المالك أو على ليدز الواتساب: أفكار محتوى، سكريبت فيديو، كابشن مصري، نسخ إعلانية، تصميم/بوستر، مونتاج، عرض مالك وباقات وتفاوض، تأهيل ومتابعة ليدز حتى الزيارة والعقد، وتقويم نشر، ومراجعة قبل النشر. عبارات التفعيل: «اعمل فيديو»، «اكتب كابشن»، «هنجهز إيه»، «إعلان»، «بوستر»، «عرض للمالك»، «رد على العميل»، «ليد جديد»، «متابعة»، «تقويم محتوى»، «راجع قبل النشر». النظام بيطبّق قواعد الالتزام والهوية الرسمية (المستخرجة من الشعار) قبل أي تسليم."
metadata:
  version: 2.3.0
  owner: TerraNex
  license: MIT (داخلي للمشروع)
  supersedes: [terranex-video-producer, terranex-content-calendar, terranex-owner-pitch, terranex-lead-followup]
---

# TerraNex Ops

نظام واحد رسمي: **10 أوامر** (9 محتوى + discovery للانطلاق الذاتي)، 5 ملفات سياق، ومحرّك تنفيذ. مفيش نظام تاني منافس.
التشغيل اليومي والإعداد والفحص الذاتي وحدود البيئة: **`OPS.md`** (يُقرأ مع هذا الملف). دخول الوكيل الجديد أولًا: `وكيل-AI-ابدأ-هنا.md` بجذر التسويق-والإدارة.

## قبل أي حاجة — اقرأ 5 ملفات (إلزامي)
| الملف | بيحدد |
|---|---|
| `context/product-marketing.md` | الجمهور، الوعد، النبرة، أوقات النشر |
| `context/brand-kit.md` | الألوان (من الشعار)، الخط، المقاسات، الحركة |
| `context/palette.json` | **مصدر الحقيقة الوحيد للألوان** — مولّد آليًا من الشعار |
| `context/compliance.md` | الممنوع والمسموح وبوّابة المراجعة |
| `context/learnings.md` | اللي أثبت نفسه والـhooks المستهلكة |

لو أي ملف ناقص: **قف** واطلبه. متتخمّنش.

## التوجيه (Router) — 10 أوامر
| الطلب | الأمر | المخرج |
|---|---|---|
| «دوّر على الجديد» / «اكتشف التريندات» | `/discovery` | أدوات مُقيّمة (تبنّي/رفض بالسبب) + تحديث المخزون + دمج المُثبت |
| «هنجهز إيه؟» / «أفكار» | `/idea` | 5 أفكار مصنّفة بزوايا + مصدر فوتاج متاح |
| «اكتب سكربت» | `/script` | beat-sheet بتوقيتات + `script.json` |
| «كابشن» | `/caption` | 3 نسخ + hook + هاشتاجات |
| «إعلان ممول» | `/ad` | 4–6 كرييتف بأنجلز مختلفة |
| «صمّم/عدّل» | `/edit` | بوستر أو ريل 9:16 فعلي |
| «راجع قبل النشر» | `/review` | قرار: انشر / عدّل / ارفض |
| **«عرض للمالك» / «باقات» / «تفاوض»** | **`/pitch`** | هيكل 7 خطوات + سعر + رد اعتراضات + رسالة واتساب |
| **«رد على العميل» / «ليد» / «متابعة»** | **`/leads`** | مرحلة + رسالة واحدة + تقرير أسبوعي |
| **«سيناريو تصوري» / «نموذج» / «ماكيت»** | **`/scenario`** | 6 إطارات 9:16 + ستوريبورد + فيلم 25ث + Shot List |

**قاعدة التوجيه:** لو الطلب واقع بين أمرين، اختار اللي بيطلّع **ملف** مش كلام.

## عقود المخرجات
```
{نوع} · {محور} · {جمهور}
HOOK: ≤ 8 كلمات
BODY: الحد حسب النوع
CTA: واحد بس
HASHTAGS: 3–6 (للمحتوى فقط)
SCORE: critic.py
ملاحظات: مفيش / قائمة إصلاح
```
`/pitch` و`/leads` ليهم عقود موسّعة في `commands/pitch.md` و`commands/leads.md`.

## قواعد الإنتاج (مدموجة من video-producer)
1. **الفكرة أولًا** — زاوية جديدة + هوك في أول ثانيتين. ممنوع تبدأ من ريل جاهز.
2. **مادة الشركة الحقيقية فقط.** لا Stock، ولا توليد كبديل (الاستثناءات بقرار المستخدم فقط).
3. **التفريغ** — faster-whisper **غير متاح في هذه البيئة** (نماذجه على HF خارج النطاق الشبكي). البديل المنفّذ: الكابشن يُكتب من السكربت/النسخة المعروفة ويُحرق عبر `make_video.py`/`make_reel_from_footage.py`. لو اتثبّت whisper في بيئة سليمة: فكّ wav بـ`wave`+`numpy` ومرّر float32.
4. **القصّ** — مونتاج متقاطع من أكثر من مصدر، 9:16 للصفحة و16:9 لعروض المالك. لا تزاحم وسم الشركة الموجود أصلًا في اللقطات.
5. **النص العربي** — ارسمه عبر `brand.text()` (يبني على `engine/artext.py`: HarfBuzz + FreeType + bidi — التشكيل الكامل بدون libraqm لأن عجلات Pillow على PyPI لا تحمله). **ممنوع** `arabic_reshaper` كبديل، وممنوع `direction=` على `ImageDraw.text` مباشرة (بيفشل بدون raqm).
6. **الأدوات** — لا ffmpeg على النظام؛ استخدم باينري `imageio-ffmpeg`. الصور الثابتة كإطار مفرد بدون `-loop`. أنشئ مجلد الإخراج قبل التركيب.

## قواعد التقويم (مدموجة من content-calendar)
- 5 ركائز: **ثقة/قيمة · إثبات · تفاعل · قصة · بيع ناعم** — نوّع القالب كل يوم.
- الهوك في أول سطرين: رقم، سؤال موجع، أو مفارقة.
- كابشن: هوك ← قيمة/قصة ← **CTA واحد** ← هاشتاجات قليلة دقيقة. لهجة مصرية محترمة.
- **قبل أي فكرة:** راجع `سجل-المحتوى.csv`. فكرة أو مصدر مستخدم = ارفض واقترح زاوية مختلفة بجد.
- الجمهور النهائي **غير محسوم** — لا تفترض شريحة ولا تعد بنتائج.

## سقف المادة الحقيقية ⚠️
**7 مصادر فريدة = 7 منشورات كحد أقصى.** `gen_calendar.py` بيسلّم المتاح فقط، وأي يوم إضافي يُوسم **«تصوير مطلوب» كمصدر، لا كمنشور**. ممنوع تقديم 30 يوم على أنها محتوى جاهز.

## الهوية الثابتة (محفورة 19/10)
1. **لا ذكر للمدينة** في أي مخرج (B9) — يُرفض آليًا.
2. **المالك لا يظهر بدون طلبه الصريح** (B10) — `context/personas.json` مصدر الحقيقة.
3. **علامة مائية موحّدة** (شعار + TerraNex) بمكان/حجم ثابتين — و«TerraNex LLC» ممنوعة (B11).
4. **الشعار كبير ومتناسق** دائمًا (B12) — لا لوجو صغير طافي.
5. **صوتان معتمدان:** الصوت المصري الهادي (أساسي) + صوت المهندس عبدالله (تسجيل حقيقي فقط).

## الممنوعات (Hard Ban)
- وعد ربح أو نسبة مضمونة · أرقام بلا مصدر · صوت/صورة مولّدة **كبديل** لمادة الشركة
- تكرار hook أو مصدر خلال 14 يوم · نشر أو تواصل مع عميل بدون موافقة صريحة

## الأدوات
| الأمر | الأداة |
|---|---|
| فحص النظام | `python engine/selfcheck.py` (شغّل أول حاجة في الجلسة) |
| الإعداد | `bash setup.sh` (تبعيات + فحص) |
| الألوان | `python engine/derive_palette.py` (من الشعار → `context/palette.json`) |
| بوستر | `python engine/make_poster.py --headline "…" --out نماذج/x.png` |
| موشن | `python engine/make_video.py --script script.json --out نماذج/x.mp4` |
| ريل بلقطة حقيقية | `python engine/make_reel_from_footage.py --video f.mp4 --captions c.json --out x.mp4` |
| مونتاج متقاطع | `python engine/make_montage.py --clips a.mp4 b.mp4 --trims "0:4,2:6" --out x.mp4` (MoviePy/MIT) |
| قصّ وقفات المقدم | `python engine/fix_pauses.py --in raw.mp4 --out cut.mp4` |
| حملة كاملة من موجز | `python engine/campaign_run.py --brief campaigns/<اسم>.json [--register]` |
| قياس وتحسين | `python engine/measure.py --csv data/week-NN.csv [--prev w(N-1).csv --append]` |
| نسخ المنصات | `python engine/make_variants.py --video m.mp4 --outdir output/variants/x` |
| فوتاج جديد | `python engine/ingest_footage.py` (من `03-مكتبة-الوسائط/وارد/`) |
| فحص فيديو | `python engine/qa_video.py --video v.mp4 --profile reels` |
| تجهيز منشور | `python engine/package_post.py --video v.mp4 --caption c.txt --platforms "facebook,instagram" --date … --time …` |
| تقويم | `python engine/gen_calendar.py --days 7 --out calendar.md` |
| سيناريو تصوري | `python engine/make_scenario.py --spec spec.json --outdir frames --video teaser.mp4` |
| فحص | `python engine/critic.py --file copy.txt` |
| بناء ريل بالهوية الثابتة | `python engine/reel_build.py --spec spec.json --voice vo.mp3 --out x.mp4` |
| فهرس المشاهد | `python engine/scene_library.py search "استعلام"` · `storyboard --scenes … --out spec.json` |
| مدير إبداعي v1.1 | `python engine/creative_director.py plan "<طلب عربي>" --project-id …` ← `render …` ← `prove-relocation …` |
| سيناريو إبداعي JSON | اكتب `creative-input.json` داخل مجلد المشروع ثم `python engine/creative_director.py apply-creative <id>` |
| تعديل بالكلام | `python engine/creative_director.py revise <id> "غيّر البداية، قلل لقطة الوزن، وقدم التغذية"` ← `render <id>` |
| رجوع لإصدار سابق | `python engine/creative_director.py rollback <id> <version>` |
| إرفاق صوت معتمد | ضع `voice-input.wav` + `voice-transcript.json` داخل المشروع ثم `attach-voice <id> --approval-note "…"` |
| فحص مسودة بصرية | `python engine/qa_video.py --video v.mp4 --profile reels --visual-draft` (تحذير، ليس إعلانًا نهائيًا) |
| تعلّم | `python engine/learn.py --csv data/week.csv` |

## Creative Director v1.1 (طلب عربي / JSON إبداعي → إنتاج مُتحقَّق منه)
- المدعوم: **متابعة الحيوانات / التغذية / الوزن الحقلي**. أي موضوع آخر يُرفض بصراحة، لا تخمين.
- مساران للتأليف: (1) قالب من طلب عربي؛ (2) **JSON إبداعي** يكتبه وكيل Arena (`creative-input.json`) ويحتفظ بالقوالب كبديل. لا يوجد استدعاء API داخلي لنموذج Arena من Python؛ الوكيل يكتب JSON والمحرك يتحقق.
- يختار من `scene-library/index.json` فقط (مشاهد `usable`، بدون وجوه/ختام). كل توقيت مصدره الفهرس؛ القصّ الطويل = excerpt محسوب داخل حدود المشهد ومُسجّل. مخططات JSON في `engine/schemas/`.
- **التعديل بالكلام:** `revise <id> "…"` يحوّل أمرًا محدودًا إلى عمليات فعلية على plan/spec/storyboard ثم ينشئ إصدارًا جديدًا. `rollback <id> <version>` يرجّع نسخة سابقة. الإصدارات في `versions/vNNNN/`.
- ذاكرة المشروع: `output/creative-projects/<id>/` فيها `brief/plan/spec/storyboard/memory/decisions/render-report/critic-report/relocation-report`. تُستعاد في جلسة جديدة عبر `show <id>`.
- **الصوت:** لا يولّد صوتًا ولا يدّعي TTS مجاني. بدون ملف معتمد = **مسودة بصرية صامتة**. عند توفر صوت: `voice-input.wav` + `voice-transcript.json` بتفريغ بشري مطابق؛ `attach-voice` يرفض اختلاف النص، ثم يقيس حدود الجمل بالطاقة. الطاقة وحدها لا تثبت مطابقة النص المنطوق.
- **بوابات منفصلة:** نجاح النص (`text-only`) ≠ نجاح الفيديو التقني ≠ جاهزية النشر. المسودة الصامتة لا تحصل أبدًا على قرار نشر؛ `publication.ready=false` حتى يوجد صوت مطابق وموافقة مالك صريحة.
- المسارات في الـspec نسبية؛ `prove-relocation` ينسخ شجرة التسويق لمسار مؤقت ويعيد الرندر ويقارن SHA-256. ملفات المشروع عبر `creative_store.py` بأسماء مسموحة فقط (لا مسارات CLI حرة).

## بوابات بشرية دائمة
النشر الفعلي · التواصل مع أي عميل · الدمج في `main` — **كلها بموافقة المستخدم الصريحة فقط.**

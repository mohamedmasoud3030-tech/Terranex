# /edit — التصميم والمونتاج الفعلي

## المدخل
`{بوستر | ريل} {النص} {المقاس}`

## المسارات (اختر واحد — مفيش خلط)
| المسار | الأداة | إمتى |
|---|---|---|
| **بوستر/ستوري** | `engine/make_poster.py` | بوست ثابت، غلاف، إعلان |
| **ريل موشن (بدون فوتاج)** | `engine/make_video.py` | تعريف، أسئلة، عرض، CTA |
| **ريل بلقطات حقيقية + براند** | `engine/make_reel_from_footage.py` | عندنا فوتاج من مواد-خام أو 01–07 |
| **مونتاج متقاطع لعدة لقطات** | `engine/make_montage.py` (MoviePy/MIT) | تركيب 2+ لقطة خام بقصّ وترتيب |
| **قصّ وقفات المقدم** | `engine/fix_pauses.py` | فيديو كلام طويل فيه تلعثم/وقفات |
| **نسخ المنصات** | `engine/make_variants.py` | reels/feed45/square من الماستر |
| **استلام فوتاج جديد** | `engine/ingest_footage.py` | لقطات الموبايل الواردة في 03-مكتبة-الوسائط/وارد |

> لمحتوى المقدم البشري الطبيعي: صوّر ← وارد ← `fix_pauses` ← `make_montage` (لو أكثر من لقطة) ← `make_reel_from_footage` (طبقات الهوية) ← `qa_video`.

## خطوات التنفيذ
1. افتح `context/brand-kit.md` وطبّق الـtokens (الألوان/الخط/المساحات) — المحرّك بيقراها من نفسه.
2. نفّذ الأمر:
```bash
python engine/make_poster.py --headline "…" --sub "…" --stat "50" --unit "كجم" --out output/poster.png
python engine/make_video.py --script output/script.json --out output/reel.mp4
python engine/make_reel_from_footage.py --video "مصدر.mp4" --captions output/captions-x.json --out output/reel-x.mp4
python engine/qa_video.py --video output/reel-x.mp4 --profile reels
```
3. **افحص المخرج بصريًا** قبل التسليم: العربي متشكّل صح؟ النص جوه المساحة الآمنة؟ الأكسنت واحد؟
4. لو فيه فوتاج حقيقي: ما تحطش صوت مولّد — الصوت من تسجيل الفريق فقط.

## المخرج
- ملف فعلي في `output/` + مقاسه + مدته + حجمه.
- `caption.txt` المرافق.
- سطر «افحص يدويًا»: قائمة 3 نقاط لازم العين البشرية تشوفها.

## الفشل المتوقع وحله
| المشكلة | الحل |
|---|---|
| العربي مقطّع | تأكد إن الرسم بـPIL+raqm (المحرّك بيعمل كده)، مش ffmpeg drawtext |
| النص بيتقطع تحت | حرّكه لفوق لحد 72% من الارتفاع |
| الملف تقيل | CRF 23 بدل 20 |

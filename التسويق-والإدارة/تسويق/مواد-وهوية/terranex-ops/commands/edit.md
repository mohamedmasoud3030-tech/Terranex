# /edit — التصميم والمونتاج الفعلي

## المدخل
`{بوستر | ريل} {النص} {المقاس}`

## المسارات (اختر واحد — مفيش خلط)
| المسار | الأداة | إمتى |
|---|---|---|
| **بوستر/ستوري** | `engine/make_poster.py` | بوست ثابت، غلاف، إعلان |
| **ريل موشن (بدون فوتاج)** | `engine/make_video.py` | تعريف، أسئلة، عرض، CTA |
| **ريل بلقطات حقيقية + براند** | `engine/make_reel_from_footage.py` | عندنا فوتاج من مواد-خام أو 01–07 |
| **نسخ المنصات** | `engine/make_variants.py` | reels/feed45/square من الماستر |
| **استلام فوتاج جديد** | `engine/ingest_footage.py` | لقطات الموبايل الواردة في مواد-خام/وارد |

> ملاحظة: مفيش مونتاج متقاطع آلي لسلسلة لقطات (الأداة المشار إليها سابقًا «OpenMontage» ليست موجودة ولن تُبنى);
> المونتاج الفعلي يتم يدويًا في أداة المستخدم (CapCut مثلًا) أو عبر make_reel للفيديو الواحد.

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

# مراجعة أمان PR #195 — ما كان ظاهرًا وما أُصلح فعلًا

**الحالة النهائية:** SonarCloud Code Analysis على PR #195 **PASS** (آخر تحقق على `b5fbd0a`، check-run `127316169001`) مع **0 annotations**. لم تُعطّل أي قاعدة ولم تُستبعد أي ملفات من التحليل؛ `.sonarcloud.properties` كما هو.

## 1) لماذا كان التقييم E؟
كانت هناك ثغرات Security Hotspot/Vulnerability من نوع **Path Traversal via file content**: Engine كان يقرأ مسارات/أسماء من JSON ثم يفتحها أو يمررها إلى FFmpeg بدون حصر كافٍ. لاحقًا ظهرت أيضًا Cognitive Complexity أعلى من الحد في دوال المخرج الإبداعي.

## 2) الإصلاحات الفعلية
- `engine/safe_paths.py`: `confine(path, root)` يعيد بناء المسار داخل الجذر بعد `os.path.basename` لكل مكوّن، ويرفض الخروج/الروابط الهاربة.
- `engine/reel_build.py`: كل مسارات الإدخال تمر عبر `_safe_input_path` ثم `confine` تحت `MARKETING_ROOT`.
- `engine/creative_store.py`: أسماء ملفات المشروع من قائمة مغلقة؛ الكتابة النصية أصبحت `write_caption()` باسم ثابت بدل sink عام يقبل اسم ملف من المتصل.
- `engine/creative_director.py`: التجزئة/الفيديو/الفهرس/الصوت تُحصر داخل جذور معروفة؛ مسارات الإخراج ثابتة تحت مجلد التسويق.
- إعادة هيكلة الدوال المعقدة: waterfill، اختيار اللقطات، تحقق الخطة/creative، إعادة التوازن، وعمليات المراجعة أصبحت دوال مساعدة صغيرة.
- لا يوجد مسار صوت عام: `attach_voice` يقرأ `voice-input.*` و`voice-transcript.json` من مجلد المشروع فقط.

## 3) اختبارات تمنع التكرار
- `tests/test_creative_director.py::TestSecurity`:
  - spec بمسار مطلق يُرفض قبل FFmpeg.
  - `scene-library/index.json` بمشهد خارج الجذر/رابط هارب يُرفض.
  - مسارات إخراج/صوت/فيديو عامّة غير موجودة في توقيعات الدوال.
  - `confine` يرفض traversal وsymlink escape.
- `tests/test_reel_build.py` يغطي symlink/traversal/crop.

## 4) ما تبقى بعد آخر فحص
- 0 failure annotations و0 warning annotations على آخر commit.
- تحذير regex السابق أُزيل بمسح خطي للمدة بدل نمط backtracking، مع اختبارات للأرقام العربية والكلمية.

## 5) Vercel منفصل عن الكود
Vercel **FAIL** لأن مؤلف الـ commit ليس عضوًا في فريق Vercel الذي يملك المشروع. remedies المعروضة: جعل الريبو public أو ترقية Pro؛ كلاهما خارج الصلاحية/القيود (لا أدوات مدفوعة). هذا ليس فشل build في الكود.

# مراجعة أمان PR #195 — SonarCloud Security Rating E

المصدر: تقرير فحص PR #195 كما ظهر في GitHub Check annotations للفحص `SonarCloud Code Analysis`
(check run `127257088061`) وتعليق `sonarqubecloud[bot]`. بوابة الجودة فشلت بسبب
**E Security Rating on New Code**. لم يتم تعطيل الفحص أو استثناء الملفات.

## مشكلات الأمان الجديدة وأرقامها

| Issue ID | المسار | السطر القديم | المشكلة | المعالجة |
|---|---|---:|---|---|
| `AaGrxazM9-BERNRzTYTs` | `engine/creative_director.py` | 717 | Path Traversal via CLI arguments in `render_project()` | إلغاء `--out` الحر؛ الإخراج يتولد من `project_id` slug + رقم إصدار داخل مجلد إنتاج ثابت |
| `AaGrxazM9-BERNRzTYTo` | `engine/creative_director.py` | 703 | Path Traversal via CLI arguments in `render_project()` | نفس المعالجة؛ spec/voice من `ProjectStore` بأسماء مسموحة |
| `AaGrxazM9-BERNRzTYTn` | `engine/creative_director.py` | 613–614 | Command Argument Injection in `measure_phrases()` | تمرير بايتات الصوت إلى ffmpeg عبر `pipe:0`؛ لا مسار ديناميكي في argv |
| `AaGrxazM9-BERNRzTYTl` | `engine/creative_director.py` | 747–749 | Command Argument Injection via file content in `prove_relocation()` | مسارات النسخة المؤقتة مشتقة من جذر ثابت + slug/إصدار؛ لا مسار من ذاكرة المشروع |
| `AaGrxazM9-BERNRzTYTm` | `engine/creative_director.py` | 753 | Filesystem Oracle via file content in `prove_relocation()` | المقارنة تتم مع SHA المخزن للإصدار، لا باستكشاف مسار فيديو من الذاكرة |
| `AaGrxazM9-BERNRzTYTt` | `engine/creative_director.py` | 110 | Path Traversal in `_write_json()` | حذف الكاتب العام؛ الكتابة عبر `ProjectStore.write_json(name)` بقائمة أسماء ثابتة |
| `AaGrxazM9-BERNRzTYTu` | `engine/creative_director.py` | 111 | Path Traversal in `_write_json()` | نفس المعالجة |
| `AaGrxazM9-BERNRzTYTv` | `engine/creative_director.py` | 105 | Path Traversal in `_read_json()` | حذف القارئ العام؛ القراءة عبر `ProjectStore.read_json(name)` |
| `AaGrxazM9-BERNRzTYTr` | `engine/creative_director.py` | 587 | Path Traversal in `_append_event()` | `ProjectStore.append_event()` يكتب `decisions.jsonl` فقط داخل المشروع |
| `AaGrxazM9-BERNRzTYTq` | `engine/creative_director.py` | 660 | Path Traversal in `attach_voice()` | إلغاء وسيط مسار الصوت؛ الأصل يجب أن يكون `voice-input.wav/mp3/…` داخل المشروع |
| `AaGrxazM9-BERNRzTYTk` | `engine/creative_director.py` | 118 | Path Traversal via file content in `_sha256()` | تجزئة أصول ثابتة/مولدة داخليًا؛ لا مسار فيديو حر من الذاكرة |
| `AaGrxazM9-BERNRzTYTp` | `engine/creative_director.py` | 118 | Path Traversal via CLI arguments in `_sha256()` | نفس المعالجة؛ لا `original_video` CLI |

## اختبارات الانحدار المضافة
- `TestSecurity.test_project_id_traversal_rejected`: يرفض `../evil`, `a/b`, `-lead`…
- `TestSecurity.test_store_file_allowlist`: يرفض أسماء ملفات خارج القائمة.
- `TestSecurity.test_measure_phrases_uses_stdin_not_filename_argument`: ملف اسمه `-i.wav` لا يصبح وسيط أمر.
- `TestSecurity.test_render_and_attach_do_not_accept_arbitrary_paths`: توقيع الدوال لا يقبل مسارات حرة.
- اختبارات الصوت ترفض غياب التفريغ البشري أو اختلاف النص، حتى لو عدد مقاطع الطاقة مطابقًا.

## ملاحظات جودة إضافية من نفس التقرير
تم أيضًا تقليل التعقيد/التكرار حيث كان ذلك عمليًا: ثوابت أسماء الملفات، تقسيم `parse_brief` و`validate_index` و`qa_video`، وإصلاح regex المدة. لم تُستخدم استثناءات Sonar لإخفاء النتائج.

# ذاكرة مشاريع Creative Director v1.1

كل مجلد `<project-id>/` مشروع قابل للاستعادة في جلسة Arena جديدة، بإصدارات متعددة:

| الملف | الغرض |
|---|---|
| `brief.json` | الطلب الأصلي + ما استُخرج وما افترض |
| `plan.json` | ترتيب البحث، المشاهد المختارة، الجدول الزمني، نوافذ القراءة/الصوت |
| `spec.json` | spec تنفيذي لـ`reel_build` بمسارات نسبية |
| `storyboard.png` | ستوريبورد بصري بمعاينات حقيقية وتوقيتات |
| `caption.txt` | نص الكابشن/السكربت + هاشتاجات |
| `memory.json` | الحالة، الإصدار الحالي، قائمة الإصدارات، القرارات، روابط المخرجات |
| `decisions.jsonl` | سجل أحداث append-only |
| `render-report.json` | فحص تقني + بوابة نشر منفصلة |
| `critic-report.json` | نجاح النص فقط، وليس قرار نشر |
| `relocation-report.json` | إثبات الرندر من مسار مختلف ومقارنة SHA |
| `versions/vNNNN/` | لقطة محفوظة من كل إصدار للرجوع |
| `creative-input.json` | اختياري: سيناريو إبداعي كتبه وكيل Arena |
| `revision-input.json` | اختياري: patch منظم للتعديل |
| `voice-input.wav/mp3/…` | اختياري: صوت معتمد موضوع داخل المشروع |
| `voice-transcript.json` | إلزامي مع الصوت: تفريغ بشري مطابق للنص المنطوق |

## أوامر
```bash
python3 engine/creative_director.py plan "<طلب عربي>" --project-id <id>
python3 engine/creative_director.py apply-creative <id>     # يقرأ creative-input.json
python3 engine/creative_director.py revise <id> "غيّر البداية، قلل لقطة الوزن، وقدم التغذية"
python3 engine/creative_director.py render <id>
python3 engine/creative_director.py rollback <id> 1
python3 engine/creative_director.py show <id>
python3 engine/creative_director.py prove-relocation <id>
```

## بوابات المراجعة
- `text_success`: النص اجتاز critic (نص فقط).
- `technical_success`: الفيديو اجتاز QA التقني.
- `publication.ready`: **لا يكون true لمسودة صامتة**. يلزم صوت معتمد مطابق + تفريغ بشري + قرار نشر صريح من المالك.

## أمان الملفات
كل القراءة/الكتابة داخل المشروع تتم عبر `engine/creative_store.py` بقائمة أسماء ثابتة و`project_id` slug صارم. لا يقبل المحرك مسارات إخراج/صوت حرة من CLI، ولا يمرر مسار صوت ديناميكي كوسيط ffmpeg.

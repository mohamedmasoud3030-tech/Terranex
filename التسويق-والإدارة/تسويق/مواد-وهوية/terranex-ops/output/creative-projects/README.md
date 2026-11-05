# ذاكرة مشاريع Creative Director

كل مجلد `<project-id>/` مشروع قابل للاستعادة في جلسة Arena جديدة:

| الملف | الغرض |
|---|---|
| `brief.json` | الطلب الأصلي + ما استُخرج وما افترض |
| `plan.json` | ترتيب البحث، المشاهد المختارة، الجدول الزمني، نوافذ القراءة |
| `spec.json` | spec تنفيذي لـ`reel_build` بمسارات نسبية |
| `storyboard.png` | ستوريبورد بصري بمعاينات حقيقية وتوقيتات |
| `caption.txt` | نص الكابشن/السكربت + هاشتاجات |
| `memory.json` | الحالة، القرارات، المراجعات، روابط المخرجات |
| `decisions.jsonl` | سجل أحداث append-only |
| `render-report.json` / `critic-report.json` | نتائج QA والالتزام |
| `relocation-report.json` | إثبات الرندر من مسار مختلف ومقارنة SHA |

استعادة سريعة:
```bash
python3 engine/creative_director.py show <project-id>
python3 engine/creative_director.py render <project-id> --out …
python3 engine/creative_director.py prove-relocation <project-id>
```

**الحالة الافتراضية بدون صوت معتمد = مسودة بصرية صامتة، وليست إعلانًا نهائيًا.**

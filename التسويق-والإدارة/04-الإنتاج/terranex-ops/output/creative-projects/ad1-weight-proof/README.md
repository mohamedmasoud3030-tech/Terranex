# AD-1 «الوزن قدامك» — استعادة وتشغيل من main

- الأصول والهوية موجودتان في `main` بعد PR #202. لا حاجة لاسترجاع فروع الرفع #196–#200 أو تشغيل أدوات intake التجريبية.
- `spec-a.json` و`spec-b.json` يربطان المصدر مباشرةً بـ`التسويق-والإدارة/تسويق/مواد-خام/أرشيف/2026-11/` عبر مسارات نسبية؛ البصمات محفوظة في `media-manifest.json`.
- `engine/reel_build.py` يدعم الصورة الثابتة، `crop: {}`، `sharpen: false`، `scale_flags: lanczos` و`caption_cy`.
- أنشئ المعاينة من جذر `terranex-ops` بالأمر: `python3 engine/reel_build.py --spec output/creative-projects/ad1-weight-proof/spec-a.json --out output/creative-projects/ad1-weight-proof/preview-a-silent.mp4`، وبالمثل للنسخة B.
- يظل مخرج الفيديو **صامتًا وممنوع النشر** إلى أن يتوفر التعليق المعتمد وموافقة المالك. لا تستخدم ملف الصوت القديم.
- تقرير الأرشيف والنتائج: `archive-intake/github-branches/REPORT.md`. كل النتائج النهائية هنا في صورة بيانات وأدلة، دون ضم أدوات استخراج ZIP القديمة إلى مسار الإنتاج.

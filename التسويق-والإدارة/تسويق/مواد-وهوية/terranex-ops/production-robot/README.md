# TerraNex Production Robot — تشغيل آلي بالمادة الحقيقية

الهدف: **روبوت شغال على السيرفر، مش فيديو جديد من المساعد**. يستقبل ملفات خام، يرتب سيناريو مراحل العمل، يختار الأصول التي لها دليل تصوير، يطلب مراجعة نوافذ القص، ويشغّل محركات TerraNex الحالية (reel_build وvoice_identity وqa_video) بعد اكتمال المواد والتعليق المعتمد.

## الخطوة الأولى: شغّله على أرشيف الشركة

من داخل terranex-ops:

    python engine/production_robot.py plan --brief production-robot/briefs/farm-to-delivery.json --out output/production-robot/plan.json

يرجع plan.json وسبب كل مرحلة ناقصة. **النتيجة الحالية متوقعة ومحجوبة، وليست فشلًا تقنيًا:** لا توجد لقطة توصيل أو تصوير حقيقي لعملية التقطيع في الأرشيف. توجد صور لمنتج لحوم معبأة، لكنها ليست تصويرًا لعملية التغليف. الذبح موجود في ملفات ذات محتوى دموي محجور؛ يحتاج مراجعة وقبولًا صريحًا للمعاينة فقط. لا يُنشئ لقطات AI أو Stock أو شرائح وهمية لتعويض نقص التصوير.

## استقبال الفيديوهات الجديدة

بعد تسجيل فيديو حقيقي لعملية التقطيع أو التوصيل:

    python engine/production_robot.py ingest --file /path/to/delivery.mp4 --role delivery

يحفظ الفيديو خارج Git في output/production-robot/uploads ويحسب SHA-256. لا يستخدمه إلا بعد مراجعة بشرية موثقة:

    python engine/production_robot.py review --id up-XXXXXXXXXXXXXXXX --description "لقطة استلام الطلب حقيقية، دون وجوه غير مصرح بها" --duration 12

أعد إنشاء الخطة. كل اختيار لفيديو من الأرشيف القديم يظل **مقترحًا** حتى تراجع نافذته وتضع في brief.choices اختيار asset_id، وتوقيت start، وwindow_reviewed=true. عدم المراجعة = لا رندر.

## تشغيل السيرفر

    TERRANEX_BOT_TOKEN=YOUR_LONG_SECRET_TOKEN python engine/production_robot.py serve --host 127.0.0.1 --port 8765

كل طلب يحتاج Authorization Bearer token. المنافذ الخاصة:

- GET /v1/health
- PUT /v1/assets?role=delivery&filename=delivery.mp4 مع بايتات الفيديو في جسم الطلب، والحد 250MiB.
- POST /v1/assets/{id}/review مع JSON يحتوى human_reviewed=true وdescription وduration.
- POST /v1/jobs يرسل brief JSON ويرجع storyboard وmissing وreview_needed.
- GET /v1/jobs/{id} يعرض الحالة.
- POST /v1/jobs/{id}/render يرسل voice_metadata فقط؛ يسحب الملف الخاص الثابت من output/production-robot/voices/approved-voice-00.mp3 بعد فحص هويته وبصمته، ولا يقبل مسارات صوت من العميل.
- GET /v1/jobs/{id}/video ينزل الملف النهائي بعد نجاح الرندر، وبنفس التوثيق.

يعمل على localhost افتراضيًا. أي فتح خارجي يتطلب TLS reverse proxy موثق. الخادم الحالي **كود على GitHub غير منشور على VPS**.

## التعليق الصوتي والتحرير

- لا يتم توليد صوت ثالث. voice-00 افتراضي، وصوت المهندس عبدالله لا يفعّل دون الأصل والإذن.
- لا إعادة استعمال تسجيل 09b (13.6ث) في فيديو 40ث: بوابة المدة والصمت ترفض المدة غير المناسبة وفجوات الصمت الطويلة.
- لا رندر بلا تعليق معتمد يوافق النص ولا بلا مصادر حقيقية كاملة للسيناريو.
- يستعمل نفس محرك المونتاج والخط والشعار والتوقيع البصري وQA، من دون إضافة محرك منافس.
- لا نشر آلي، ولا ترخيص مدفوع، ولا تعديل لتطبيق الاستثمار.

## تشغيل من GitHub

افتح Actions ثم workflow باسم TerraNex Production Robot، واختر Run workflow. سيولّد جردًا فعليًا للقطات والمراحل الناقصة ويرفع ملف plan.json كأثر، دون إنشاء إعلان مزيف. عملية الرندر تحتاج عاملًا لديه التعليق الصوتي وبيانات اعتماده، ولا تعمل تلقائيًا على GitHub Actions المفتوح.

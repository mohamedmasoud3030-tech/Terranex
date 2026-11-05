# حالة أرشيف Google Drive — عائق موثّق بالأدلة

**آخر فحص:** 2026‑11‑06 (بتوقيت المالك) · **الحساب:** Mohamed Masoud · **الموصّل:** `google_drive` = **enabled**

---

## ١) ما تم اكتشافه والتحقق منه فعليًا ✅

بحث في كل الملفات غير المحذوفة عن أرشيفات مضغوطة أعاد **نتيجتين**:

| الاسم | الحجم | التاريخ | الحكم |
|-------|-------|---------|-------|
| **`Archive.zip`** | **181,196,089 بايت = 172.8 MiB** | أُنشئ ورُفع **2026‑11‑05 22:39 UTC** | ✅ هذا هو أرشيف الوسائط المقصود |
| `rentrix (7).zip` | 418,379 بايت | 2026‑01‑30 | ❌ أرشيف برمجي صغير داخل مجلد Google AI Studio — ليس وسائط، لم يُفتح |

**بيانات `Archive.zip` المؤكدة من Drive:**
- المعرّف: `1oUCCJhnWhtklCk_mJKYofNcGNuXRiPm8`
- النوع: `application/zip` · مملوك لك · غير مشارك · في جذر My Drive
- MD5: `e35aee67957a3f876fa70a6a9f874e7d`
- **SHA‑256: `7a2bd417bb12b1d0eba348509b889d5f6a3f0d1af72d17734c943d3d7feed4d2`**
- الصلاحيات: `canDownload = true`, `canEdit = true`, `canCopy = true`
- الرابط: https://drive.google.com/file/d/1oUCCJhnWhtklCk_mJKYofNcGNuXRiPm8/view

**قابلية القراءة:** البيانات الوصفية مقروءة بالكامل ✅ — لكن **البايتات لم تصل** ❌.

## ٢) العائقان (بالدليل، لا بالادعاء)

### العائق B1 — حد النقل في الموصّل
طلبت `download_file` على المعرّف أعلاه، فردّ الموصّل حرفيًا:
```
code: file_transfer_failed
"Arena did not send this download. File metadata reports 181196089 bytes,
 more than the 100 MiB (104857600 byte) workspace file limit.
 Tell the user that the file is too large. Share its Drive link if available."
```
→ الملف **172.8 MiB** يتجاوز حد النقل **100 MiB**.

### العائق B2 — حجب شبكي لنطاقات Drive
اختبرت الرابط المباشر من داخل البيئة:
```
$ curl -I --max-time 20 "https://drive.google.com/uc?id=1oUCC…&export=download"
curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to drive.google.com:443

$ curl -o /dev/null -w '%{http_code}' https://api.github.com     ← اختبار ضابط
200
```
→ الشبكة تسمح لنطاقات محدودة فقط؛ **نطاقات Google Drive محجوبة**، فلن ينفع رابط عام ولا رابط تنزيل مباشر.

## ٣) النتيجة الصادقة

**عدد البايتات المقروءة من الأرشيف = 0.** لم يُفَكّ، ولم يُجرد، ولا نعرف عدد الصور أو الفيديوهات داخله.
أي أرقام أو صور أو تقييمات في `REPORT.md` تخص **المواد المحلية في المستودع فقط**، وليست من الأرشيف.

## ٤) القرار المنفَّذ: U2 — تقسيم سحابي عبر Google Colab

### أولًا: هل يدعم الموصّل التنزيل الجزئي؟ **لا** (اختبار فعلي)
طلبت `download_file` بمعلمة `range: "bytes=0-62914559"` فردّ النظام:
```
Invalid input … An unsupported property was sent.
Allowed properties: acknowledge_abuse, file_id, supports_all_drives.
```
الرفض عند **التحقق من المخطط** قبل الوصول إلى Drive، فمخطط الأداة مغلق ولا يقبل نطاقات أو ترويسات.
وراجعت باقي الأدوات: `export_file` لمستندات Workspace فقط، `read_file_text` للنصوص،
`initiate_resumable_upload` للرفع لا للقراءة. **إذًا لا يوجد مسار تنزيل جزئي عبر الموصّل.**
الدليل الكامل: `range-support-test.json`.

### ثانيًا: مسار العودة يعمل (اختبار ذاتي موثّق)
رفعت ملفًا صغيرًا (102 بايت) إلى Drive ونزّلته عبر الموصّل:
وصل إلى `google_drive/terranex-transfer-selftest.png` في مساحة العمل **مطابقًا بالبايت** (cmp + SHA‑256)،
ثم حذفت ملف الاختبار من Drive ومن مساحة العمل.
**النتيجة: أي جزء أصغر من 100 MiB سيصل فعلًا كملف.** وأضفت `google_drive/` إلى `.gitignore` حتى لا يُرفع شيء خام إلى Git.

### ثالثًا: Notebook جاهز للتشغيل من المتصفح
- الملف: **`colab/TerraNex-Split-Archive.ipynb`** (في جذر المستودع)
- التعليمات: **`COLAB-INSTRUCTIONS.md`**
- يقسم الأرشيف **سحابيًا** إلى 3 أجزاء ranges مؤكدة، يتحقق من كل جزء بعد رفعه، ويكتب `manifest.json`.
- **الأرشيف الأصلي للقراءة فقط**، والتنفيذ قابل للاستكمال بعد أي انقطاع.

```
Archive.part01-of-03.bin        0 .. 60,398,695       60,398,696 بايت
Archive.part02-of-03.bin   60,398,696 .. 120,797,391  60,398,696 بايت
Archive.part03-of-03.bin  120,797,392 .. 181,196,088  60,398,697 بايت
المجموع 181,196,089 ✔   أكبر جزء 57.6 MiB < 100 MiB ✔
```

**المطلوب من المالك:** تشغيل Notebook من المتصفح ثم قول «الأجزاء جاهزة». لا أوامر على جهازه.

## ٥) ضمانات

- أرشيف Drive الأصلي **لم يُعدَّل ولم يُنقل ولم يُحذف** — كل الاستدعاءات كانت قراءة بيانات وصفية، ومحاولة تنزيل واحدة رفضها النظام.
- لم أنزّل الملفات المتناثرة الأخرى في Drive (`image.png`، `M3.mp4` 2020) لأنها خارج الأرشيف.
- لا نشر، لا دمج، لا تغيير لهوية الصوت، لا تعديل لتطبيق الاستثمار.

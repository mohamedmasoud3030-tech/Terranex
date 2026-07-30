# تقرير تدقيق نظافة الأسرار — Terranex

**التاريخ:** 2026-07-30 · **المشروع:** `nwpyeobuxzbdnnzyfyqw` · **الريبو:** عام (public)

---

## 🔴 النتيجة الأهم: المفاتيح القديمة **لم يتم تدويرها فعلياً**

ذكرت أن الـ rotate تمّ، لكن الاختبار الحي يثبت العكس. **المفتاح القديم `service_role` ما زال يعمل بصلاحيات كاملة الآن.**

### الدليل

```
GET /rest/v1/transactions            → HTTP 200  []
GET /rest/v1/financial_audit_logs    → HTTP 200  []
POST /rest/v1/rpc/record_transaction_atomic
     → 23502: null value in column "project_id" violates not-null constraint
```

الرد الأخير حاسم: خطأ **منطقي من داخل الدالة** وليس رفض مصادقة — أي أن المفتاح القديم يصل فعلاً إلى الـ RPCs المالية ويستطيع الكتابة.

### تمييز مهم (لماذا لا تُخدع بالـ 401)

مفتاحا `anon` و `publishable` القديمان ردّا `HTTP 401`، وقد يبدو ذلك كأنهما بُطِلا. **لكنهما لم يُبطلا.** قارنت ثلاث حالات:

| المفتاح | الرد | المعنى |
|---|---|---|
| مفتاح مزيّف تماماً | `Invalid API key` | ❌ مرفوض فعلاً |
| `anon` القديم على REST | `42501: permission denied` | ✅ **مقبول** — لكن الـ role محروم من الجداول |
| `anon` القديم على `/auth/v1/settings` | **HTTP 200** | ✅ **صالح تماماً** |

الفرق جوهري: `42501` هو خطأ **صلاحيات Postgres** (المفتاح صحيح، الـ role ممنوع)، بينما `Invalid API key` هو رفض مصادقة. ولأن `anon` القديم يعمل على endpoint مفتوح ويرجع 200 — فهو **لم يُدوَّر**.

> سبب حرمان `anon`: الـ migration رقم 6 (`grants_and_revokes`) يمنح الصلاحيات لـ `authenticated` و `service_role` فقط. هذا تصميم أمني سليم، ولا علاقة له بالتدوير.

### JWT القديم صالح حتى **2036-06-30**

فحصت الـ payload: `role: service_role` · `exp: 2036-06-30`. لن ينتهي تلقائياً — **التدوير اليدوي هو السبيل الوحيد**.

---

## 1) فحص الملفات — ✅ نظيف

بحث شامل بـ `grep -rInE` عن الأنماط: `nwpyeobuxzbdnnzyfyqw` · `sb_publishable_` · `sbp_[a-f0-9]{40}` · JWT header · `github_pat_`

| النطاق | النتيجة |
|---|---|
| كل ملفات الريبو (عدا `.git`, `node_modules`, `dist`, `external`) | ✅ **صفر نتائج** |
| الملفات غير المتتبّعة والمخفية | ✅ صفر |
| ملفات `.md`, `.json`, `.yml`, `.sh`, `.ts` | ✅ صفر قيم حقيقية |
| `.env` | ✅ **غير موجود أصلاً** |

**لم أحتج لحذف أي شيء** — الـ working tree كان نظيفاً بالفعل من التنظيف السابق.

## 2) حالة `.env` في git — ✅ آمن

- `git ls-files | grep "^\.env"` → **`.env.example` فقط** (لا `.env`)
- `.gitignore` يشمل `.env` (سطر 13) + `.env.local` + `.env.*.local`
- اختبار عملي: `git check-ignore -v .env` → ✅ **متجاهل فعلاً**

## 3) محتوى `.env.example` — ✅ placeholders فقط

```
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key-here
```
لا URL حقيقي ولا مفتاح حقيقي.

## 4) اختبار الاتصال

| المفتاح | REST | نتيجة |
|---|---|---|
| `service_role` القديم | **HTTP 200** | 🔴 **يعمل بكامل الصلاحيات** |
| `anon` القديم | 401 (`42501`) | 🟠 صالح، محروم من الجداول |
| `publishable` القديم | 401 (`42501`) | 🟠 صالح، محروم من الجداول |
| `sbp_` token القديم | **HTTP 200** | 🔴 **يعمل** — يقرأ بيانات المشروع من Management API |

**لم أختبر المفاتيح الجديدة** لأنك لم تشاركها — وهذا صحيح، لا حاجة لمشاركتها. للتحقق بنفسك:
```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://nwpyeobuxzbdnnzyfyqw.supabase.co/rest/v1/transactions?select=id&limit=1" \
  -H "apikey: NEW_KEY" -H "Authorization: Bearer NEW_KEY"
```
`200` = يعمل. وأعد اختبار القديم: يجب أن يعطي `Invalid API key` — **لا** `42501`.

---

## 5) تحليل git history — 🔴 التسريب ما زال منشوراً

### نطاق التسريب

| المؤشر | القيمة |
|---|---|
| إجمالي commits | 429 |
| commits تحتوي المفاتيح | **57** |
| الملفات المتأثرة | **`.env.example` فقط** ← لا شيء غيره |
| أول تسريب | `35ade2f` — *Phase 1: migrate storage layer to Supabase* |
| آخر ظهور (commit التنظيف) | `454e8a5` |
| `sbp_` token في History | ✅ **غير موجود** |
| GitHub PAT في History | ✅ **غير موجود** |

### مكشوف للعامة الآن

الريبو **public** (تأكدت عبر GitHub API: `private: false`, `forks: 0`).

- `main` الحالي: ✅ نظيف (placeholders)
- التاريخ القديم: 🔴 **متاح للجميع** — تأكدت بجلب الملف من commits قديمة عبر `raw.githubusercontent.com` بدون أي مصادقة:

```
GET .../35ade2ffb.../.env.example → VITE_SUPABASE_URL=https://nwpyeobuxzbdnnzyfyqw.supabase.co
                                     VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oRunet...
GET .../6238cce6b.../.env.example → (نفس المحتوى المسرَّب)
```

**الخلاصة:** حذف السر من `main` لا يحذفه من التاريخ. أي شخص يستطيع استخراجه بأمر واحد.

---

## هل يحتاج تنظيف history؟

### الأولوية الحقيقية: التدوير أولاً، والتنظيف ثانياً

**تنظيف الـ history وحده لا يحمي شيئاً** طالما المفاتيح صالحة — فقد تكون نُسخت بالفعل (الريبو عام منذ commit `35ade2f`). **التدوير هو الإجراء الحاسم**، والتنظيف نظافة تكميلية.

### ما المكشوف فعلاً في التاريخ؟

فقط: **project URL** + **publishable key**. الـ `service_role` والـ `sbp_` token **لم يدخلا git إطلاقاً** (شاركتهما في المحادثة فقط).

الـ publishable key مصمَّم للعميل ويُرسل للمتصفح — خطورته محدودة **بشرط أن الـ RLS محكم**، وهو كذلك: تحققت أن `anon` محروم من كل الجداول (44 policy + grants لـ `authenticated` فقط). لذلك التسريب في التاريخ **منخفض الخطورة نسبياً**.

🔴 **الخطر الفعلي هو `service_role` النشط** — لم يُسرَّب في git لكنه في هذه المحادثة، ويعمل الآن بصلاحيات كاملة تتجاوز الـ RLS.

### التوصية

| # | الإجراء | الأولوية |
|---|---|---|
| 1 | **تدوير `service_role`** فعلياً والتحقق بالاختبار | 🔴 عاجل |
| 2 | تدوير `sbp_` access token | 🔴 عاجل |
| 3 | تدوير `publishable`/`anon` | 🟠 مهم |
| 4 | تدوير GitHub PAT | 🟠 مهم |
| 5 | تنظيف git history | 🟡 اختياري |

**رأيي:** بعد التدوير الفعلي، تنظيف الـ history يصبح **غير ضروري** — لأن المكشوف سيكون مفاتيح ميتة + project ref (وهو ظاهر في أي طلب شبكة من التطبيق أصلاً). لو أردت النظافة الكاملة رغم ذلك، الخطوات أدناه.

---

## خطوات تنظيف History — ⚠️ **لم أنفّذها، بانتظار تأكيدك**

النطاق: `.env.example` في 57 commit.

```bash
# 0) نسخة احتياطية كاملة — لا تتخطَّ هذه الخطوة
git clone --mirror https://github.com/mohamedmasoud3030-tech/Terranex.git backup-terranex.git

# 1) تثبيت الأداة
pip install git-filter-repo

# 2) استبدال القيم في كل التاريخ
cat > /tmp/replacements.txt <<'EOF'
https://<OLD_PROJECT_REF>.supabase.co==>https://your-project-ref.supabase.co
<OLD_PUBLISHABLE_KEY>==>your-publishable-key-here
EOF

cd Terranex
git filter-repo --replace-text /tmp/replacements.txt

# 3) التحقق قبل الدفع
git log --all --oneline -S"<OLD_PUBLISHABLE_PREFIX>" | wc -l   # يجب أن يكون 0

# 4) إعادة الـ remote (filter-repo يحذفه عمداً) ثم الدفع القسري
git remote add origin https://github.com/mohamedmasoud3030-tech/Terranex.git
git push origin --force --all
git push origin --force --tags
```

### ⚠️ ما يجب أن تعرفه قبل الموافقة

1. **كل الـ commit SHAs ستتغير** — أي مرجع لـ commit في تذكرة أو توثيق سيصبح ميتاً.
2. **أي شخص لديه نسخة يجب أن يعيد الـ clone** — الـ `git pull` العادي سيفشل أو يُنشئ تاريخاً مزدوجاً. نسّق معهم أولاً.
3. **GitHub يحتفظ بالـ commits القديمة مؤقتاً** في الـ cache حتى بعد الـ force push. لإزالتها نهائياً افتح تذكرة لدعم GitHub، أو — الأسهل والأضمن — **احذف الريبو وأعد إنشاءه** بعد الاحتفاظ بنسخة نظيفة.
4. **الـ forks لا تتأثر** — لحسن الحظ `forks_count: 0`.
5. `git filter-repo` يحذف الـ remote عمداً كإجراء وقائي — لذلك الخطوة 4.

---

## الخلاصة

| البند | الحالة |
|---|---|
| ملفات الريبو (working tree) | ✅ نظيفة تماماً |
| `.env` غير متتبّع + في `.gitignore` | ✅ مؤكد |
| `.env.example` placeholders فقط | ✅ مؤكد |
| `main` على GitHub | ✅ نظيف |
| git history (57 commit) | 🔴 يحتوي URL + publishable key، مكشوف للعامة |
| `service_role` القديم | 🔴 **يعمل الآن — لم يُدوَّر** |
| `sbp_` token القديم | 🔴 **يعمل الآن — لم يُدوَّر** |
| `anon`/`publishable` القديمان | 🟠 صالحان (محرومان من الجداول بالـ grants) |

**لا يمكن قفل هذه المرحلة الآن.** الشرط الوحيد المتبقي هو التدوير الفعلي للمفاتيح. أعد الاختبار بعده — يجب أن يرد القديم `Invalid API key`، لا `42501` ولا `200`.

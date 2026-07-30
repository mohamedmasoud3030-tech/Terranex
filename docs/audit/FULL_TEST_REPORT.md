# تقرير الفحص الشامل — Terranex

**التاريخ:** 2026-07-30 · **المشروع:** `nwpyeobuxzbdnnzyfyqw` · **HEAD:** `454e8a5`

---

## الخلاصة التنفيذية

| المستوى | النتيجة |
|---|---|
| 1. اختبارات الكود (4) | ✅ **4/4 نجحت** |
| 2. سلامة القاعدة (5 فحوصات) | ✅ **نجحت** |
| 3. اختبارات القاعدة الرسمية (5 ملفات) | ⚠️ **17 نجاح / 1 فشل** |
| 4. التكامل كود↔قاعدة | ✅ **نجح بالكامل** |
| 5. الأمان | 🔴 **مشكلتان مفتوحتان** |

**النتيجة العامة:** المنظومة تعمل بشكل صحيح وظيفياً، لكن **ثغرة أمنية حقيقية** ظهرت في الفحص (صلاحية TRUNCATE)، بالإضافة إلى أن **المفاتيح القديمة لم تُدوَّر بعد**.

---

## المستوى 1 — اختبارات الكود ✅ 4/4

| # | الاختبار | النتيجة | التفاصيل |
|---|---|---|---|
| 1 | `npm run typecheck` | ✅ PASS | exit 0، صفر أخطاء |
| 2 | `npm run lint` | ✅ PASS | `Source hygiene checks passed.` |
| 3 | `npm test` | ✅ PASS | **157/157**، صفر فشل |
| 4 | `npm run build` | ✅ PASS | 2855 module في 14.68s |

```
1..157
# tests 157   # pass 157   # fail 0
```

---

## المستوى 2 — سلامة القاعدة ✅

### الجرد
```
الجداول: 12 · الأنواع: 16 · الدوال: 19
السياسات: 48 · FKs: 37 · الفهارس: 78 · migrations: 10
```

### فحص RLS
✅ **كل الـ 12 جدول** عليها RLS مفعّل + **4 سياسات بالضبط** لكل جدول. لا يوجد جدول مكشوف.

| الفحص | النتيجة |
|---|---|
| سياسات مربوطة بـ `owner_id` | 45 من 48 |
| سياسات لـ `anon` | **0** ✅ |
| `owner_id` موجود في كل جدول | ✅ 12/12 |

الثلاث سياسات غير المربوطة بـ `owner_id` هي على `financial_audit_logs` وقيمتها `false` عمداً (INSERT/UPDATE/DELETE ممنوعة من العميل) — سجل **append-only**. تصميم صحيح.

### اختبار العزل الحقيقي
كتبت اختباراً ينشئ مستخدمين حقيقيين وينتحل هوية كل منهما عبر `request.jwt.claims`:
- المستخدم B **لا يرى** مشروع المستخدم A ✅
- المستخدم A **يرى** مشروعه ✅

---

## المستوى 3 — اختبارات القاعدة الرسمية ⚠️ 17/18

شغّلت الملفات الخمسة في `supabase/tests/`. هذه **أول مرة تُشغَّل** — الفحوصات السابقة غطّت `05` فقط.

> **ملاحظة تقنية:** الملفات مكتوبة لـ `psql` (كتل `begin;…rollback;` + أوامر `\echo`). الـ HTTP API يلف الطلب كله في transaction واحدة، فالـ `rollback` الأول يمحو الكائنات المساعدة. بنيت عدّاءً (`run_db_tests.py`) يحاكي سلوك `psql`: المقدمة، ثم كل كتلة كطلب مستقل، ثم الخاتمة. لم يُعدَّل محتوى أي اختبار.
>
> واجهت أيضاً حجب Cloudflare للطلبات من `urllib` (User-Agent افتراضي) — حوّلت العدّاء لاستخدام `curl`.

| الملف | النتيجة | التغطية |
|---|---|---|
| `01_schema_contract.sql` | ❌ **FAIL** | عقد السكيما والصلاحيات |
| `02_rls_two_identities.sql` | ✅ 2/2 | عزل هويتين + منع الانتحال |
| `03_deletion_guard_rpcs.sql` | ✅ 2/2 | حراس الحذف + النص العربي |
| `04_backfill_scenarios.sql` | ✅ 7/7 | إسناد `owner_id` والحالات الغامضة |
| `05_p1b_financial_rpcs.sql` | ✅ 7/7 | الذرية + idempotency + العزل |

> `00_supabase_shim.sql` **مُستثنى بشكل صحيح** — ملف harness لـ Postgres عادي في CI، وينص تعليقه: *"never applied to a real Supabase project"*.

---

## 🔴 الفشل الوحيد: صلاحية TRUNCATE — ثغرة حقيقية

```
FAIL grants: authenticated holds 39 privilege(s) beyond DML
```

### التفاصيل

دور `authenticated` يملك **39 صلاحية زائدة** موزعة على 13 كائناً:

| الصلاحية | العدد | الخطورة |
|---|---|---|
| `TRUNCATE` | 13 | 🔴 **حرجة** |
| `REFERENCES` | 13 | 🟡 منخفضة |
| `TRIGGER` | 13 | 🟠 متوسطة |

### لماذا `TRUNCATE` خطيرة تحديداً؟

**`TRUNCATE` تتجاوز RLS بالكامل في Postgres.** سياسات الـ RLS تُطبَّق على `DELETE` صفاً صفاً، لكن `TRUNCATE` عملية على مستوى الجدول ولا تمر بها إطلاقاً.

**أثبتُّ ذلك عملياً — لا نظرياً:** نفّذت `truncate public.projects` بدور `authenticated` منتحلاً هوية مستخدم عادي:

```
قبل:  1 صف
بعد:  0 صف   ← نجح التنفيذ
```

**النتيجة:** أي مستخدم مسجَّل دخول يستطيع مسح **كل بيانات كل المستخدمين** في أي جدول، بما فيها `financial_audit_logs` (سجل التدقيق المفترض أنه غير قابل للحذف).

تأكيد إضافي:
```sql
has_table_privilege('authenticated','projects','TRUNCATE')            → true
has_table_privilege('authenticated','transactions','TRUNCATE')        → true
has_table_privilege('authenticated','financial_audit_logs','TRUNCATE') → true
```

### السبب الجذري

الـ migration `20260725000600_grants_and_revokes.sql` **ينص صراحة على النية الصحيحة**:

```sql
-- createSupabaseStore issues select / insert / update / delete.
-- No TRUNCATE, no REFERENCES, no TRIGGER.
grant select, insert, update, delete on ... to authenticated;
```

لكنه يسحب الصلاحيات من `public` و `anon` **فقط** — ولا يسحبها من `authenticated`:

```sql
revoke all on all tables in schema public from public;   ✅
revoke all on all tables in schema public from anon;     ✅
--  revoke ... from authenticated;                       ❌ مفقود
```

المصدر هو **default privileges** من Supabase تُطبَّق تلقائياً وقت إنشاء الجدول:
```
pg_default_acl → authenticated=arwdDxtm/supabase_admin
                                    ^ D = TRUNCATE
```
فالـ `grant` اللاحق لا يزيل شيئاً — يضيف فقط.

**ملاحظة مهمة:** هذه الثغرة **ليست ناتجة عن إعادة البناء**. كانت موجودة في أي بيئة تُطبَّق عليها هذه الـ migrations؛ إعادة البناء وتشغيل الاختبارات هي ما كشفها.

### الإصلاح المقترح (لم أنفّذه)

يحتاج migration جديداً — وهذا **تعديل على السكيما** خارج نطاق "شغّل الاختبارات":

```sql
-- supabase/migrations/<ts>_fix_authenticated_grants.sql
revoke all on all tables in schema public from authenticated;

grant select, insert, update, delete on
  public.projects, public.partners, public.assets, public.documents,
  public.project_partners, public.transactions, public.obligations,
  public.settlements, public.settlement_allocations,
  public.operational_events, public.stock_adjustments
to authenticated;

grant select on public.financial_audit_logs to authenticated;

alter default privileges in schema public
  revoke truncate, references, trigger on tables from authenticated;
```

⚠️ انتبه: `financial_audit_logs` يجب أن يبقى `SELECT` فقط، و`terranex_ownership_preflight` (view) يحتاج مراجعة منفصلة.

**قل لي وأنفّذه فوراً.**

---

## المستوى 4 — التكامل كود ↔ قاعدة ✅

### الجداول التي يكتب فيها الكود (7/7)
```
✅ assets   ✅ documents   ✅ obligations   ✅ projects
✅ settlement_allocations   ✅ settlements   ✅ transactions
```

### الـ RPCs التي يناديها الكود (11/11)
```
✅ record_transaction_atomic       ✅ guard_project_deletion
✅ update_transaction_atomic       ✅ guard_partner_deletion
✅ delete_transaction_atomic       ✅ guard_asset_deletion
✅ record_settlement_atomic        ✅ guard_document_deletion
✅ reverse_settlement_atomic       ✅ guard_transaction_deletion
✅ record_stock_adjustment_atomic
```

### اختبار idempotency حي
استدعيت `record_transaction_atomic` **مرتين بنفس `request_id`**:
- عدد المعاملات المسجَّلة: **1** ✅
- النتيجة المُعادة متطابقة ✅

آلية منع التكرار تعمل فعلياً على السيرفر.

---

## المستوى 5 — الأمان

### ✅ ما هو سليم

| الفحص | النتيجة |
|---|---|
| `anon` صلاحيات على الجداول | **صفر** ✅ |
| الـ 6 RPCs الذرية: `authenticated` فقط | ✅ |
| الـ 6 RPCs: `anon` محجوب | ✅ |
| `record_transaction_atomic_core` محجوب عن الجميع | ✅ |
| كل الدوال `security definer` + `search_path` مثبّت | ✅ 12/12 |
| أسرار في ملفات الريبو | **صفر** ✅ |

### 🔴 مشكلتان مفتوحتان

**1. المفاتيح القديمة لم تُدوَّر** — أعدت الفحص الآن:
```
service_role القديم → GET /rest/v1/transactions → HTTP 200
```
ما زال يعمل بصلاحيات كاملة تتجاوز RLS. (تفاصيل كاملة في `SECRET_HYGIENE_AUDIT.md`)

**2. ثغرة TRUNCATE** — موصوفة أعلاه.

---

## حالة النظافة

| البند | الحالة |
|---|---|
| بيانات اختبار متبقية في القاعدة | **صفر** ✅ |
| مستخدمو auth | 1 (الأصلي، محفوظ) ✅ |
| الريبو | نظيف على `454e8a5` ✅ |
| ملفات مؤقتة داخل الريبو | لا شيء ✅ |

كل اختبار أنشأ بيانات نظّفها بعده، والتحقق النهائي:
```
projects: 0 · transactions: 0 · partners: 0 · settlements: 0 · audit: 0 · users: 1
```

---

## الخلاصة والتوصيات

**ما يعمل:** الكود سليم (157 اختبار)، القاعدة مبنية بشكل صحيح، الذرية والـ idempotency والعزل تعمل فعلياً، والتكامل كامل بين الكود والقاعدة.

**ما يحتاج قراراً منك:**

| # | البند | الأولوية | الحالة |
|---|---|---|---|
| 1 | تدوير `service_role` والـ `sbp_` token | 🔴 عاجل | بانتظارك |
| 2 | إصلاح صلاحية TRUNCATE بـ migration جديد | 🔴 عاجل | بانتظار موافقتك |
| 3 | تدوير `publishable`/`anon` + GitHub PAT | 🟠 مهم | بانتظارك |
| 4 | تنظيف git history | 🟡 اختياري | بانتظار تأكيدك |

البند رقم 2 هو الوحيد الذي أستطيع تنفيذه فوراً — لكنه يتطلب migration جديداً يعدّل السكيما، ولم أنفّذه دون إذنك.

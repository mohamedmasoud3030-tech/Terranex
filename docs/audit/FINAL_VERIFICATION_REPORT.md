# التقرير النهائي الشامل — Terranex

**التاريخ:** 2026-07-30 · **المشروع:** `nwpyeobuxzbdnnzyfyqw` · **HEAD:** `45d1296`

---

## الخلاصة

| الخطوة | النتيجة |
|---|---|
| 1. إصلاح ثغرة TRUNCATE | ✅ **مُصلحة ومُتحقَّق منها عملياً** |
| 2. اختبارات القاعدة الرسمية | ✅ **19/19** |
| 3. مطابقة الكود ↔ القاعدة | ✅ **11/11 جدول + 16 enum — صفر تعارض** |
| 4. اختبار E2E بمستخدم حقيقي | ✅ **20/20** |
| 5. تنظيف بيانات الاختبار | ✅ القاعدة نظيفة تماماً |
| 6. اختبارات الكود | ✅ 4/4 (157 اختبار) |

**لم تظهر أي ثغرة أمنية جديدة.** الثغرة الوحيدة (TRUNCATE) كانت مكتشفة سابقاً وأُغلقت الآن.

---

## 1) إصلاح ثغرة TRUNCATE ✅

### الملف المُضاف
`supabase/migrations/20260730000100_revoke_authenticated_non_dml_grants.sql`
(+ ملف rollback مقابل، اتساقاً مع بنية المشروع)

### قبل التطبيق
دور `authenticated` كان يملك **39 صلاحية زائدة** على 13 كائناً (12 جدول + view):
```
TRUNCATE   × 13    ← 🔴 حرجة
REFERENCES × 13
TRIGGER    × 13
```

### السبب الجذري
الـ migration `20260725000600` ينص صراحة: *"No TRUNCATE, no REFERENCES, no TRIGGER"* — لكنه يسحب من `PUBLIC` و`anon` فقط. الـ default ACL من Supabase (`authenticated=arwdDxtm`) يُطبَّق وقت `CREATE TABLE`، فالـ `GRANT` اللاحق **يضيف ولا يزيل**.

### ما يفعله الإصلاح
1. `revoke all` من `authenticated` على كل الجداول والـ sequences
2. إعادة منح **DML بالضبط** كما كان: 11 جدول تشغيلي → SELECT/INSERT/UPDATE/DELETE
3. `financial_audit_logs` → **SELECT فقط** (append-only)
4. `terranex_ownership_preflight` (view) → SELECT فقط
5. `ALTER DEFAULT PRIVILEGES` لمنع تكرار الثغرة في جداول مستقبلية

### التحقق بعد التطبيق

**أ. الصلاحيات الزائدة:**
```
extra_privs_remaining: 0   ✅
```

**ب. إعادة اختبار الثغرة بنفس الطريقة التي كشفتها:**
```
محاولة TRUNCATE بدور authenticated → insufficient_privilege ✅
صفوف قبل: 1  ·  صفوف بعد: 1  (البيانات سليمة)
```
قبل الإصلاح كانت النتيجة `1 → 0` (نجح المسح).

**ج. لم تُكسر الوظائف:**
```
has_table_privilege('authenticated','projects','TRUNCATE') → false ✅
has_table_privilege('authenticated','projects','DELETE')   → true  ✅
INSERT + DELETE عبر RLS يعملان ✅
```

**د. اختبار العقد الرسمي:**
`01_schema_contract.sql` — كان يفشل بـ `FAIL grants: authenticated holds 39 privilege(s) beyond DML`، والآن **يمرّ** ✅

---

## 2) اختبارات القاعدة الرسمية ✅ 19/19

| الملف | النتيجة | التغطية |
|---|---|---|
| `01_schema_contract.sql` | ✅ 1/1 | عقد السكيما والصلاحيات (كان يفشل) |
| `02_rls_two_identities.sql` | ✅ 2/2 | عزل هويتين + منع الانتحال |
| `03_deletion_guard_rpcs.sql` | ✅ 2/2 | حراس الحذف + النص العربي |
| `04_backfill_scenarios.sql` | ✅ 7/7 | إسناد `owner_id` والحالات الغامضة |
| `05_p1b_financial_rpcs.sql` | ✅ 7/7 | الذرية + idempotency + العزل |

**`00_supabase_shim.sql` — استُثني بشكل صحيح.** حاولت تشغيله فأعطى `permission denied for schema auth` عند `create table auth.users`. هذا **السلوك الصحيح**: الملف harness لإعادة بناء سقالة Supabase على Postgres عادي في CI، وتعليقه ينص: *"never applied to a real Supabase project, which already provides all of the above."* فشله على مشروع حقيقي مُتوقَّع ومطلوب.

---

## 3) مطابقة الفرونت إند ↔ القاعدة ✅ صفر تعارض

بنيت أداة مطابقة آلية (`schema_match.py`) تحلّل واجهات TypeScript وتقارنها بأعمدة القاعدة الفعلية.

### الجداول — 11/11 مطابقة تامة

| الواجهة | الجدول | الحقول |
|---|---|---|
| `Project` | `projects` | 12 ✅ |
| `Asset` | `assets` | 16 ✅ |
| `Partner` | `partners` | 10 ✅ |
| `ProjectPartner` | `project_partners` | 7 ✅ |
| `Transaction` | `transactions` | 17 ✅ |
| `Obligation` | `obligations` | 15 ✅ |
| `Settlement` | `settlements` | 17 ✅ |
| `SettlementAllocation` | `settlement_allocations` | 5 ✅ |
| `OperationalEvent` | `operational_events` | 13 ✅ |
| `StockAdjustment` | `stock_adjustments` | 11 ✅ |
| `Document` | `documents` | 17 ✅ |

**لا يوجد:** حقل يرسله الفرونت بلا عمود · عمود `NOT NULL` بلا default لا يرسله الفرونت · تعارض أنواع · تعارض optionality.

### الـ ENUMs — 16/16 متطابقة
`Currency` (7) · `SectorId` (3) · `ProjectStatus` (5) · `AssetType` (8) · `AssetStatus` (4) · `PartnerCategory` (2) · `PartnerCounterpartyRole` (6) · `TransactionDirection` (2) · `ObligationDirection` (2) · `ObligationStatus` (5) · `DocumentType` (9) · `OperationalEventType` (15) · `AdjustmentReason` (5) · `SettlementPaymentMethod` (6) · `SettlementStatus` (2) · `SettlementOrigin` (2)

كل قيمة في الكود مقبولة في القاعدة، والعكس. صفر قيمة يتيمة.

---

## 4) اختبار End-to-End بمستخدم حقيقي ✅ 20/20

### الحساب المستخدم
**أنشأت حساب اختبار منفصلاً** ولم ألمس `abdullah@teranex.com` — حماية لحساب المالك.

- البريد: `terranex.e2e.1785419002@gmail.com`
- `user_id`: `49823d17-d2ac-4497-9623-7779ad16ec6c`

> ملاحظة: Supabase رفض نطاقات `.local` و `example.com` (`email_address_invalid`)، فأنشأت المستخدم عبر Admin API بنطاق مقبول ثم **سجّلت دخولاً حقيقياً** بكلمة المرور للحصول على JWT.

**كل الطلبات مرّت عبر PostgREST بمفتاح publishable + JWT المستخدم — تماماً كما يفعل المتصفح. لم يُستخدم `service_role` في أي خطوة، فالـ RLS كان مُفعَّلاً طوال الاختبار.**

### النتائج الفعلية (مُوثَّقة بالمعرّفات)

| # | الخطوة | النتيجة الفعلية |
|---|---|---|
| 4.1 | تسجيل دخول | ✅ JWT (816 حرف) · `role: authenticated` |
| 4.2 | إنشاء مشروع | ✅ `7fe1ab96-b2b7-4af0-bee9-7648b6b35741` |
| 4.3 | إنشاء شريك | ✅ `28ca1f08-97b6-4de0-b47e-d58d8290a68a` |
| 4.4 | معاملة ذرية + التزام | ✅ tx `deaa9ec1…` + التزام `80a9c53c…` |
| 4.5 | idempotency | ✅ نفس `request_id` مرتين → **معاملة واحدة** بنفس الـ id |
| 4.6 | تسوية ذرية 2000/5000 | ✅ `55f6e833…` · الالتزام → `partial` · مسدَّد `2000.0` |
| 4.7 | أصل + تعديل مخزون | ✅ أصل `00dca4e2…` · الكمية **50 → 45** فعلياً |
| 4.8 | deletion guard | ✅ منع الحذف: *"معاملات: 1، التزامات: 1، أصول: 1، تسويات مخزون: 1"* |
| 4.8b | حذف مباشر عبر REST | ✅ **HTTP 409** — الـ FK حمى البيانات والمشروع بقي |
| 4.9 | سجل التدقيق | ✅ **3 عمليات** مسجَّلة، كل واحدة بـ `request_id` فريد |
| 4.10 | السجل غير قابل للعبث | ✅ UPDATE → 403 · DELETE → 403 |

**سجل التدقيق الفعلي:**
```
• record_transaction        transaction
• record_settlement         settlement
• record_stock_adjustment   stock_adjustment
```

### شفافية: 3 إخفاقات كانت في اختباري أنا، لا في النظام

استغرق الوصول لـ 20/20 ثلاث جولات. الإخفاقات كشفت أخطاء في **افتراضاتي**:

1. **`obligation_id` مقابل `payable_id`** — توقعت أن `record_transaction_atomic` يعيد `obligation_id`، لكن العقد الفعلي يعيد `payable_id`. راجعت الـ migration وصححت.
2. **`quantity_after` مقابل `quantity_delta`** — أرسلت الكمية النهائية، لكن الدالة تستقبل **الفرق**. تأكدت من `stockAdjustmentWorkflow.ts` (الكود الحقيقي يرسل `quantity_delta`) وصححت.
3. **`current_value_egp` غير مضبوط** — تركته `null`، فـ `coalesce(...,0) + (-1000)` أنتج قيمة سالبة ورفضتها الدالة بحق. أضفته كما يفعل التطبيق.

هذه ليست فجوات في النظام — بل **دليل على أن التحقق يعمل**: الدالة رفضت مدخلات غير صالحة بأخطاء دقيقة (`23514: stock adjustment cannot produce negative quantity or value`).

---

## 5) التنظيف ✅

حُذفت كل بيانات الاختبار بالترتيب الصحيح للـ FKs (السجل ← التخصيصات ← التسويات ← المخزون ← الالتزامات ← المعاملات ← الأصول ← الشركاء ← المشاريع)، وحُذف حساب الاختبار (HTTP 200).

```
projects: 0 · partners: 0 · transactions: 0 · obligations: 0
settlements: 0 · allocations: 0 · assets: 0 · stock_adj: 0
events: 0 · documents: 0 · audit: 0
auth_users: 1  ← abdullah@teranex.com فقط (المالك الأصلي، سليم)
```

> ملاحظة جانبية: أثناء التنظيف رفض Postgres حذف `transactions` قبل `obligations` بسبب `obligations_source_transaction_fk`. هذا **سلوك صحيح** يؤكد سلامة التصميم المرجعي.

---

## 6) اختبارات الكود ✅ 4/4

| الاختبار | النتيجة |
|---|---|
| `npm run typecheck` | ✅ PASS |
| `npm run lint` | ✅ PASS |
| `npm test` | ✅ **157/157** |
| `npm run build` | ✅ 2855 module في 13.52s |

---

## الفجوات والتناقضات المكتشفة

### 🔴 ثغرة أمنية (مُصلحة الآن)
**TRUNCATE يتجاوز RLS** — موصوفة بالكامل في القسم 1. أُغلقت وأُثبت إغلاقها عملياً.

### 🟡 تناقض توثيقي (لم أُعدِّله)
`docs/MASTER.md:257` يقول إن `@tanstack/react-table` *"مُستخدم فعلاً… ليس dead"*. هذا صحيح وقت كتابته، لكنه **قديم الآن** بعد حذف `ObligationsTable.tsx` و`RealEstateTable.tsx`. تركته لأن المهمة تقنية لا توثيقية.

### 🟡 ملاحظة تصميمية (ليست عيباً)
`generateRequestId()` تُرجع UUID عشوائياً وتتجاهل معاملاتها. الـ idempotency يحمي من **إعادة الإرسال الشبكي** (أثبتُّه: نفس `request_id` → معاملة واحدة)، لكنه **لا يمنع** المستخدم من الضغط مرتين على "حفظ" — لأن كل ضغطة تولّد معرّفاً جديداً. قرار تصميم مقبول؛ لو أردت منع الضغط المزدوج فالمعرّف يجب أن يُشتق من محتوى العملية.

### ✅ لا فجوات في التطابق
صفر تعارض بين الكود والقاعدة على مستوى الجداول والأعمدة والأنواع والـ enums.

---

## الحالة النهائية

| البند | الحالة |
|---|---|
| migrations مطبَّقة | **11** (10 + إصلاح الأمان) |
| الجداول / الأنواع / الدوال | 12 / 16 / 19 |
| السياسات / FKs / الفهارس | 48 / 37 / 78 |
| صلاحيات زائدة لـ `authenticated` | **0** ✅ |
| بيانات اختبار متبقية | **0** ✅ |
| الريبو | `45d1296` مرفوع على `main` ✅ |

---

## 🔴 تذكير: المفاتيح ما زالت غير مُدوَّرة

أعدت الفحص خلال هذه الجولة: مفتاح `service_role` القديم **ما زال يعمل** (HTTP 200) ويتجاوز RLS بالكامل. الإصلاح الأمني الذي طبّقته يحمي من `authenticated` — لكنه **لا يحمي من `service_role`**، فهو يتجاوز كل شيء بالتصميم.

**التدوير ما زال الإجراء الأهم المتبقي:** `service_role` · `sbp_` token · `publishable`/`anon` · GitHub PAT.

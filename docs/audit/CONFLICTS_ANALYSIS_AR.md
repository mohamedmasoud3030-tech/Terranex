# تحليل التعارضات — الوثائق vs الكود الفعلي
**Terranex — Audit Conflicts Analysis**  
**التاريخ:** 2026-06-28

---

## ملخص تنفيذي

- **Tests:** 61/61 pass ✅
- **Typecheck:** 0 errors ✅
- **Build:** success (608KB, gzip 180KB) ✅
- **Lint:** pass ✅
- **التعارضات الحرجة المكتشفة:** 14 تعارض
- **فجوات تنفيذية:** 9 فجوات
- **كود ميت / dependencies غير مستخدمة:** 5

---

## A. تعارضات حرجة (تؤثر على صحة البيانات أو البنية)

### C1 — عملة OMR مفقودة في الكود
- **الوثائق:** ADR-001 + `docs/reference/*` تذكر: `EGP | USD | OMR | SAR | AED | EUR | GBP` (7 عملات)
- **الكود:** `src/core/types/domain.ts:15` → `Currency = 'EGP' | 'USD' | 'SAR' | 'AED' | 'EUR' | 'GBP'` (6 عملات، OMR مفقود)
- **الخطورة:** عالية — إذا الشركة تتعامل بالريال العماني (المشروع يذكر OMR في أدوات ERPNext)، ستفشل المعاملات.
- **الإصلاح:** أضف `'OMR'` إلى union type، حدث `src/core/i18n/ar.ts` (أضف `currency_OMR`)، وحدث validation.

### C2 — صيغة الربحية متضاربة بين الوثائق
- **docs/domain-model.md:** `Profit = total income - total expense - open provisions`
- **IMPLEMENTATION_GUIDE.md:** `Accounting profit = income - expenses` + `Open receivables/payables displayed separately`
- **الكود (`profitability.ts`):** `net_profit_egp = gross_profit_egp` (يطابق IMPLEMENTATION_GUIDE)
- **الخطورة:** متوسطة — تضارب توثيقي قد يضلل مطورين جدد.
- **الإصلاح:** حدّث `docs/domain-model.md` ليتطابق مع IMPLEMENTATION_GUIDE.

### C3 — مسارات الـ Routing لا تطابق ADR-004
- **ADR-004 يحدد:**
  ```
  /real-estate/$id → project detail
  /agriculture/$id → ...
  /livestock/$id → ...
  ```
- **الكود الفعلي (`src/router.tsx`):**
  ```
  /projects
  /projects/$id   ← موحد لكل القطاعات
  /real-estate    ← قائمة فقط، بلا $id
  /agriculture    ← قائمة فقط
  /livestock      ← قائمة فقط
  ```
- **الخطورة:** متوسطة — كسر عقد معماري موثق.
- **التوصية:** إما تحديث ADR-004 ليعكس الواقع (المسار الموحد أنظف)، أو إضافة sector-scoped detail routes كـ redirect.

### C4 — نموذج Partner — تسمية الحقول مختلفة
- **ADR-002:** `Partner` يحمل `role` discriminated union: `equity_partner | counterparty`
- **الكود:** `category: PartnerCategory` (`'equity_partner' | 'counterparty'`) + `counterparty_role?: PartnerCounterpartyRole`
- **الفرق:** الاسم `role` vs `category` + `counterparty_role` — وظيفياً متطابق تقريباً، لكن يخالف العقد اللفظي.
- **الخطورة:** منخفضة.
- **الإصلاح:** توحيد التسمية في الوثائق أو عمل type alias.

### C5 — i18n Strategy مُخالفة بالكامل
- **ADR-006:** "Custom lightweight i18n using React Context + typed translation keys ... Translation files: `src/i18n/ar.ts`"
- **الكود:** الملفات موجودة في `src/core/i18n/ar.ts` (وليس `src/i18n/`) — فرق مسار.
- **الأخطر:** `useI18n()` **غير مستخدم إطلاقاً في أي صفحة features**. كل الصفحات hard-coded عربي:
  - `DashboardPage.tsx` — 0 استدعاء لـ `t()`
  - `AgriculturePage.tsx` — 0
  - `LivestockPage.tsx` — 0
  - `RealEstatePage.tsx` — 0
  - ...
- **الخطورة:** عالية معمارياً — النظام ثنائي اللغة موجود لكنه dead code. أي تغيير لغة في المستقبل يتطلب إعادة كتابة كل الصفحات.
- **الإصلاح:** تدريجياً — ابدأ بتحويل DashboardPage لاستخدام `t()`، ثم باقي الصفحات.

---

## B. فجوات تنفيذية (Features موثقة لكن غير منفذة UI)

### G1 — OperationalEvent UI غائب بالكامل
- **الوثائق:** ADR-003 — "Event Sourcing track" هو حجر أساس للقطاع الحيواني/الزراعي
- **الكود:** 
  - Types ✅ كاملة
  - Storage (`eventsStore`, `stockAdjustmentsStore`) ✅ موجود
  - Deletion guards ✅ تتحقق من events
  - **UI ❌ صفر — لا فورم، لا صفحة، لا قائمة**
- **الأثر:** القطاع الحيواني والزراعي حالياً مجرد مشاريع مالية بلا تتبع تشغيلي (ولادات، نفوق، حصاد...). هذا يُفرغ جوهر المنتج.
- **الأولوية:** P0

### G2 — StockAdjustment UI غائب
- نفس G1 — موازٍ لـ OperationalEvent.
- **الأولوية:** P1

### G3 — Charts / Recharts غير مستخدم
- **ADR-007 + ADR-010:** Recharts جزء أساسي، مجلد `src/components/charts/` مخطط
- **الواقع:** لا مجلد charts، 0 import من 'recharts'
- **الأثر:** Dashboard بلا رسوم بيانية زمنية — مخالف لـ design-system MASTER.md
- **الأولوية:** P1

### G4 — React Hook Form + Zod غير مستخدم
- **ADR-005 + ADR-008:** "Form state: React Hook Form + Zod"
- **الواقع:**
  - `react-hook-form` في package.json لكن 0 استخدام
  - `zod` مستخدم في سطر واحد فقط (`finitePositiveNumberSchema`)
  - كل الفورمات يدوية (`useState` + validation يدوي)
- **الأثر:** كود فورمات أطول، validation غير موحد، خطر inconsistency
- **الأولوية:** P2

### G5 — ExchangeRate master غير منفذ
- **Type موجود:** `ExchangeRate` في domain.ts
- **Storage/UI:** غير موجود
- **الحالي:** fx_rate يُدخل يدوياً في كل معاملة — لا جدول أسعار مركزي
- **الأولوية:** P2

### G6 — Asset Balances View غير محسوب
- **الوثائق:** `asset_balances` materialized view تُحسب من events + adjustments
- **الكود:** لا يوجد حساب derived balance — الكمية تُقرأ مباشرة من `asset.quantity`
- **الأولوية:** P2

### G7 — ProjectPartner equity validation غير مكتمل
- لا يوجد UI لإضافة شركاء لمشروع مع التحقق أن مجموع `equity_pct ≤ 100`
- `ProjectDetailPage` تعرض الشركاء؟ تحقق:
  - `ProjectDetailPage.tsx` — لا، تعرض معاملات ومستندات فقط
- **الأولوية:** P1

### G8 — Sector detail routes ($id) مفقودة
- مغطى في C3

### G9 — تقارير PDF/Excel Export غير موجودة
- موثقة في `Terranex-Architecture-English.md` فصل 6.5
- غير منفذة
- **الأولوية:** P3

---

## C. كود ميت / Dependencies زائدة

| Package | في package.json؟ | مستخدم؟ | الحكم |
|---|---|---|---|
| `recharts` | نعم 3.8.1 | لا — 0 import | **احذف أو نفّذ charts** |
| `react-hook-form` | نعم 7.76.1 | لا — 0 useForm | **احذف أو حوّل الفورمات** |
| `zod` | نعم 4.4.3 | نعم جزئي (~5%) | **وسّع الاستخدام أو قلّص الاعتماد** |
| `@tanstack/react-table` | نعم 8.21.3 | ؟ | تحقق — يبدو غير مستخدم أيضاً |
| `@radix-ui/react-dialog` etc | نعم | نعم جزئي | OK |
| `useI18n / t()` | موجود | 0 استخدام | **Dead code معماري خطير** |
| `OperationalEvent` types+storage | نعم | 0 UI | **نصف منفذ** |
| `ExchangeRate` type | نعم | 0 استخدام | **Dead type** |

تحقق سريع من react-table:
```bash
grep -r "useReactTable\|@tanstack/react-table" src
# → لا نتائج
```
→ **react-table أيضاً غير مستخدم — dependency ميتة.**

---

## D. تعارضات توثيقية (Docs قديمة vs جديدة)

| الوثيقة | الحالة | الملاحظة |
|---|---|---|
| `README.md` | قديم مختصر | يصف "طبقة العمل داخل الريبو" — مرحلة تأسيسية، لا يعكس المنتج الحالي |
| `AGENTS.md` | حديث — كنسي | ممتاز، محدّث |
| `IMPLEMENTATION_GUIDE.md` | **المصدر الكنسي للـ runtime** | دقيق ويطابق الكود |
| `docs/product-vision.md` | حديث، مختصر | سليم |
| `docs/domain-model.md` | **قديم جزئياً** | صيغة الربحية قديمة، لا يذكر settlement allocation |
| `docs/architecture-decisions.md` | **مختلط** | ADR-001..010 ممتازة لكن بعضها لم يُنفذ (charts, RHF, i18n usage, sector $id routes) |
| `docs/reference/Terranex-Architecture-English.md` | نسخة إنجليزية قديمة | تذكر Supabase كـ primary DB — يتعارض مع local-first الحالي |
| `docs/plans/terranex-native-engine-extraction-plan.md` | حديث جداً | يصف بدقة settlement allocation engine — **هذا هو الواقع الفعلي** |
| `docs/generated/*.docx` | غير مقروء هنا | يبدو تقارير مولدة — قد تكون قديمة |
| `CLAUDE.md` | stub يشير لـ AGENTS.md | سليم |

**الخلاصة:** الوثائق الأحدث هي:
1. `IMPLEMENTATION_GUIDE.md`
2. `docs/plans/terranex-native-engine-extraction-plan.md`
3. `AGENTS.md`
4. `src/core/types/domain.ts` (source of truth)

الوثائق الأقدم التي تحتاج تحديث:
- `docs/domain-model.md`
- `docs/architecture-decisions.md` (أضف ADR-011.. يوثق الانحرافات الفعلية)
- `README.md`
- `docs/reference/Terranex-Architecture-English.md`

---

## E. مشاكل جودة كود مكتشفة (Debug / Static Analysis)

بعد `npm run typecheck` + `test` + مراجعة يدوية:

### ✅ إيجابيات قوية
- **0 TypeScript errors**
- **61/61 tests pass** — تغطية ممتازة للـ settlement / obligation / profitability core
- **Deletion guards شاملة** — تمنع حذف project/asset/partner/document إذا مربوط بمعاملات
- **Migrations versioned** — `migrations.ts` نظيف
- **Backup ZIP deterministic** — مع CRC32 وvalidation
- **Document file validation** — SHA256 + MIME + size checks
- **Obligation settlement boundaries** — تمنع over-settlement، negative، Infinity
- **RTL / Accessibility** — `dir="rtl"`، focus-visible، 44px touch targets، prefers-reduced-motion
- **Arabic typography** — Noto Kufi Arabic مُحمّل صح

### ⚠️ مشاكل متوسطة

**M1 — Currency OMR ناقص (مكرر C1)**
```ts
// src/core/types/domain.ts:15
export type Currency = 'EGP' | 'USD' | 'SAR' | 'AED' | 'EUR' | 'GBP';
// Missing: 'OMR'
```

**M2 — Profitability partner_splits قد تُنتج مجموع ≠ 100%**
- `computeProjectProfitability` يحسب `share_egp = gross_profit * equity_pct / 100`
- لا يوجد validation أن مجموع equity_pct = 100
- لا يوجد residual handling
- **مخاطرة:** توزيع أرباح غير مكتمل/زائد

**M3 — Hard-coded Arabic يمنع EN toggle**
- `useI18n` موجود لكن 0 استخدام
- لو غيّر المستخدم locale إلى 'en'، الواجهة تبقى عربي — **تجربة مكسورة**

**M4 — Bundle size كبير**
- `dist/assets/index-BH6iuUD1.js 608.60 kB │ gzip: 180.85 kB`
- Warning: "Some chunks are larger than 500 kB"
- السبب: كل شيء في chunk واحد، dependencies ثقيلة غير مستخدمة (recharts ~150KB، react-table، RHF، zod)
- **توصية:** code-splitting + tree-shaking للـ dead deps

**M5 — No ErrorBoundary في التطبيق**
- ADR-008 يطلب `ErrorBoundary` على مستوى الـ feature
- **الواقع:** لا يوجد ErrorBoundary — أي crash React يبيّض الشاشة
- تحقق: `grep -r "ErrorBoundary" src` → 0 نتائج

**M6 — Optimistic updates غير منفذة**
- ADR-008: "Optimistic updates: mutations use TanStack Query's onMutate / onError rollback"
- **الواقع:** لا يوجد useMutation أصلاً — كل الـ stores synchronous localStorage
- ليس خطأ فعلياً (local-first لا يحتاج optimistic) لكن يخالف الوثيقة

**M7 — Form validation غير موحد**
- بعض الحقول تتحقق يدوياً، بعضها لا
- مثال `TransactionForm.tsx`: يتحقق amount > 0، fx_rate > 0 — جيد
- لكن لا Zod schema موحد
- رسائل خطأ عربي يدوي — ليست من `t('validation_...')`

**M8 — open_obligations_egp حسابه مشكوك**
```ts
// profitability.ts:52
const open_obligations_egp = open_receivables_egp + open_payables_egp;
```
جمع مدينة + دائنة معاً؟ هذا رقم غير منطقي محاسبياً — التعرض النقدي هو الفرق، ليس المجموع. الحقل موجود في الـ type لكن استخدامه غير واضح في UI. **قد يكون bug توثيقي — أو حقل زائد.**

**M9 — Asset quantity يعتمد على إدخال يدوي**
- لا يوجد replay لـ OperationalEvent لحساب الرصيد الحي
- يعني رصيد القطيع قد يصبح غير متسق مع أحداث الولادة/النفوق (لو كانت الأحداث منفذة)

**M10 — Security: localStorage بلا تشفير**
- بيانات مالية حساسة في localStorage plaintext
- مقبول لـ Phase 1 local-first، لكن يجب توثيق المخاطرة — **موثق فعلاً في data-safety.md ✅**

### 🔍 Bugs محتملة تحتاج اختبار يدوي

- **B1:** `obligationQueries.ts` — aging buckets تعتمد `new Date()` — قد تختلف بالـ timezone
- **B2:** `documentFileValidation.ts` — يقبل أي MIME؟ تحقق القائمة البيضاء
- **B3:** Settlement reversal — الاختبارات تغطيه جيداً، لكن هل UI يعرض الحركات الملغاة بوضوح؟
- **B4:** Project delete guard — يمنع الحذف إذا وُجدت معاملات — ✅ ممتاز
- **B5:** Transaction update — "move the reverse document link atomically" — الاختبار `updates normalize values and move the reverse document link atomically` ينجح ✅

---

## F. تقييم جودة الكود (Scorecard)

| المحور | الدرجة /10 | الملاحظة |
|---|---|---|
| **Type Safety** | 9.5 | TypeScript strict، 0 errors، domain types ممتازة |
| **Test Coverage (Core)** | 9.0 | 61 اختبار، financial engine مغطى ممتاز |
| **Test Coverage (UI)** | 2.0 | 0 اختبار UI / E2E |
| **Architecture Adherence** | 6.5 | بنية المجلدات ممتازة، لكن i18n/charts/RHF/event UI غير منفذ |
| **Documentation Accuracy** | 5.5 | وثائق كثيرة متضاربة — القديم لم يُحذف |
| **Security / Data Safety** | 8.0 | Deletion guards، migrations، backup — ممتاز local-first |
| **Accessibility / RTL** | 8.5 | RTL أصيل، focus-visible، 44px targets |
| **Performance** | 6.0 | Bundle 608KB، لا code-split، dependencies ميتة |
| **Maintainability** | 7.5 | كود نظيف، SOLID، لكن فورمات يدوية و i18n ميت |
| **Business Logic Correctness** | 8.5 | Profitability صحيح، settlement engine قوي جداً |

**المتوسط المرجح: 7.3 / 10 — جيد جداً مع فجوات معمارية واضحة**

---

## التوصيات العاجلة (Priority Order)

**P0 — خلال أسبوع:**
1. أضف `OMR` للـ Currency union + i18n
2. فعّل OperationalEvent UI — على الأقل CRUD أساسي للـ livestock (birth/death/feed)
3. أضف ErrorBoundary root

**P1 — خلال أسبوعين:**
4. حوّل DashboardPage لاستخدام `useI18n()` — Proof of concept للـ i18n الحي
5. احذف dependencies الميتة: `recharts`, `@tanstack/react-table`, `react-hook-form` **أو** نفّذها فعلياً
6. نفّذ ProjectPartner equity UI مع validation مجموع ≤100%
7. Code-split: `vite.config.ts` → manualChunks

**P2 — خلال شهر:**
8. وحّد الوثائق — احذف/أرشف القديم، اجعل `IMPLEMENTATION_GUIDE.md` + `UNIFIED_PROJECT_DEFINITION_AR.md` هما الكنسيان
9. أضف Charts أساسية (Recharts) — revenue/expense time series
10. وسّع Zod validation لكل الفورمات
11. أضف `open_obligations_egp` توضيح — هل هو مجموع أم يجب حذفه؟

**P3 — لاحق:**
12. PDF/Excel export
13. Supabase migration
14. E2E tests (Playwright)

---

*End of Conflicts Analysis — 2026-06-28*

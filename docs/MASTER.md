# Terranex — وثيقة المشروع الموحدة
**الإصدار:** v1.7  
**التاريخ:** 2026-07-25  
**المرجع الكنسي:** يسبق جميع وثائق `docs/` ما عدا ما في `docs/audit/`

> هذه الوثيقة تجمع الحالة الفعلية للمشروع بعد تدقيق 28 يونيو 2026.  
> للقرارات المعمارية التفصيلية: `docs/architecture-decisions.md`  
> للتعارضات المعروفة: `docs/audit/CONFLICTS_ANALYSIS_AR.md`

---

## 1. هوية المشروع

**Terranex** هو **نظام تشغيل استثماري عربي-أول** (Arabic-first RTL) مع دعم EN ثنائي لإدارة أصول ومشاريع شركة استثمارية عبر ثلاثة قطاعات.

**الشعار:** لا نبني واجهات لعرض البيانات — نبني العقل الرقمي للشركة الذي يجيب بدقة على سؤال الربحية والالتزامات.

**الحالة:** `v0.3.0-p2` — **NO-GO للإطلاق** ⛔

التخزين الحالي **Supabase (Postgres)** و**Supabase Auth مستخدم**. البوابات الخمس خضراء
(96/96 اختبار)، لكن الإطلاق محجوب بـ: غياب migrations مُدارة بالإصدار، غياب RLS/RPC على
الخادم، كتابات مالية غير ذرية، ونسخ احتياطي لا يغطي Supabase. التفاصيل في §7.

---

## 2. الأسئلة الجوهرية — North Star

| السؤال | مُنفَّذ؟ | المصدر في الكود |
|---|---|---|
| ماذا نملك / نشغل؟ | ✅ | Assets + Projects + Partners + Events |
| كم كلّف كل مشروع؟ وكم كسب؟ | ✅ | Transactions → `profitability.ts` |
| هل ربح أم خسر؟ | ✅ | `computeProjectProfitability()` |
| من له فلوس؟ ومن عليه فلوس؟ | ✅ | Obligations + Settlements |
| ما الدليل؟ (audit trail) | ✅ | Documents + reversal logs |

---

## 3. القطاعات الثلاثة

| القطاع | الأصول | العمليات المالية | العمليات التشغيلية |
|---|---|---|---|
| **العقاري** | أراضي، مباني | شراء، تطوير، بيع | — |
| **الزراعي** | مزارع، محاصيل | مواسم، مبيعات | planting, irrigation, fertilization, pest_control, harvest, crop_loss |
| **الحيواني** | قطعان | أعلاف، علاج، بيع | birth, death, vaccination, treatment, feed_consumption, weighing, transfer |

---

## 4. النموذج النطاقي — مستخرج من `src/core/types/domain.ts`

> **المصدر الوحيد للحقيقة:** `src/core/types/domain.ts`
> أي تعارض مع هذا الملف → الملف يسبق الوثيقة.

### الكيانات الأساسية

**Sector** — `'real-estate' | 'agriculture' | 'livestock'`

**Project**
- `id, sector_id, name_ar, name_en, status, start_date, end_date`
- `base_currency: Currency`
- `status: 'planning' | 'active' | 'on_hold' | 'completed' | 'cancelled'`

**Asset**
- `type: 'land' | 'building' | 'farm' | 'equipment' | 'herd' | 'animal_group' | 'crop' | 'other'`
- `acquisition_cost, acquisition_currency, acquisition_cost_egp`
- `quantity?, unit?` ← للماشية والمحاصيل

**Partner** (Hybrid)
- `category: 'equity_partner' | 'counterparty'`
- `counterparty_role: 'supplier' | 'client' | 'service_provider' | 'lender' | 'government' | 'other'`

**ProjectPartner** — join table
- `equity_pct: number` — 0–100، مجموع ≤ 100% لكل مشروع

**Transaction**
- `direction: 'income' | 'expense'`
- `currency: Currency, fx_rate, amount_egp` ← كل قيم بـ EGP بعد FX
- `operational_event_id?` ← ربط بحدث تشغيلي

**Obligation**
- `direction: 'receivable' | 'payable'`
- `status: 'open' | 'partial' | 'settled' | 'disputed' | 'written_off'`
- `amount_settled_egp` ← running total

**OperationalEvent**
- 15 نوع: birth, death, vaccination, treatment, feed_consumption, weighing, transfer, planting, irrigation, fertilization, pest_control, harvest, crop_loss, purchase, sale
- `quantity_delta?` ← يؤثر على رصيد الأصل الحي

**Settlement / SettlementAllocation**
- تسوية جزئية + كاملة
- Multi-obligation allocation
- Reversal مع audit trail

**Document** — مرتبط بـ project, asset, partner, transaction

**StockAdjustment** — escape hatch للأرصدة الافتتاحية والتصحيحات

### العملات المعتمدة
```typescript
type Currency = 'EGP' | 'USD' | 'OMR' | 'SAR' | 'AED' | 'EUR' | 'GBP';
```
**7 عملات** — FX rate يُدخل وقت المعاملة — كل القيم تُخزن بـ EGP أيضاً.

---

## 5. محرك الربحية — `src/core/lib/profitability.ts`

```
الربح المحاسبي = الإيرادات − المصروفات
التعرض النقدي = ذمم مدينة − ذمم دائنة
صافي الربح = الربح المحاسبي  (لا مخصصات حالياً — مطابق IMPLEMENTATION_GUIDE)
```

**الدوال الرئيسية:**
- `computeProjectProfitability()` — ربحية مشروع واحد + حصص الشركاء
- `computeSectorSummary()` — ملخص قطاع
- `computeGlobalSummary()` — ملخص كلي بالـ by_sector breakdown

**ملاحظة موثقة:** `open_obligations_egp = receivables + payables` (جمع، ليس طرح) — هذا قرار مقصود موثق في CONFLICTS_ANALYSIS_AR.md § C8.

---

## 6. البنية التقنية

### Stack

| الطبقة | التقنية |
|---|---|
| Framework | React 19 + TypeScript 5.8 + Vite 7 |
| Routing | TanStack Router v1 (manual tree) |
| Data | TanStack Query v5 |
| Forms | React Hook Form 7.76 + Zod 4.4 + @hookform/resolvers |
| UI | Tailwind CSS + Radix UI |
| Charts | Recharts 3.8 (lazy-loaded) |
| i18n | `useI18n()` hook — AR/EN toggle حي |
| Storage | **Supabase (Postgres) + Realtime** — بيانات النطاق كاملة |
| Auth | **Supabase Auth** — جلسة مُستمرة + auto-refresh |
| Local storage | تفضيلات الواجهة فقط (locale, theme, fx) + IndexedDB للملفات + ZIP backup |
| PWA | Service Worker + manifest |
| PDF | @react-pdf/renderer |

### Routes

```
/dashboard             ← DashboardPage — KPIs + Charts
/projects              ← ProjectsPage
/projects/$id          ← ProjectDetailPage + Equity UI
/real-estate           ← RealEstatePage
/agriculture           ← AgriculturePage
/livestock             ← LivestockPage
/events                ← EventsPage ✅ منفذ — CRUD + live quantity
/transactions          ← TransactionsPage (RHF+Zod ✅)
/assets                ← AssetsPage
/documents             ← DocumentsPage
/partners              ← PartnersPage
/partners/$id          ← PartnerDetailPage
/finance/obligations   ← ObligationsPage (default)
/finance/allocations   ← SettlementAllocationPage
/finance/profitability ← ProfitabilityPage
/settings              ← SettingsPage
```

### جداول Supabase — مصدر البيانات الحالي
```
projects              partners            project_partners
assets                documents           transactions
obligations           settlements         settlement_allocations
operational_events    stock_adjustments
```
> ✅ **P1A:** هذه الجداول الـ11 صارت مُعرّفة بالكامل في `supabase/migrations/` مع RLS
> (44 سياسة) ودوال `guard_*_deletion` الخمس، ومُثبتة على Postgres حقيقي عبر
> `scripts/db-test.sh`. **لكنها لم تُطبَّق على مشروع Supabase إنتاجي بعد.**
> التفاصيل: `docs/supabase/INVENTORY.md`.

### مفاتيح localStorage المتبقية — ليست مخزن بيانات
```
terranex.locale / theme / exchangeRates          ← تفضيلات واجهة
terranex.migrations.v1                            ← حالة ترحيل البيانات القديمة
terranex.financialRecords.v1                      ← بيانات ما قبل Supabase (تُصرَّف فقط)
terranex.settlements.legacy-balance-migration.v1  ← مفتاح ترحيل قديم
terranex.settlementAllocations.*                  ← مفاتيح ترحيل قديمة
```
> مفاتيح `terranex.projects.v1` … `terranex.stockAdjustments.v1` **لم تعد تُكتب**.
> كانت مخزن البيانات قبل الانتقال إلى Supabase.

### Bundle Size (بعد code-split)
```
index.js       : 441 KB │ gzip 126 KB   (initial)
charts-*.js    : 377 KB │ gzip 112 KB   (lazy — عند فتح Dashboard)
tanstack-*.js  : 120 KB │ gzip  38 KB
forms-*.js     :  97 KB │ gzip  28 KB
radix-*.js     :  33 KB │ gzip  11 KB
```

---

## 7. حالة الجودة — 25 يوليو 2026

```
npm ci            ✅
typecheck         ✅ 0 errors
lint              ✅ pass
tests             ✅ 96 / 96
build             ✅ success
```

كل ملف اختبار يمر أيضاً منفرداً في عملية Node مستقلة — لا اعتماد على ترتيب أو state مشترك.

> **ملاحظة على الأرقام القديمة:** وثائق سابقة ذكرت «61/61». ذلك الرقم يسبق الانتقال إلى
> Supabase. القياس الفعلي على `main` عند بدء هذا العمل كان **46 ناجح / 67** (21 فاشل)،
> وبعد الإصلاح **96/96**.

### ⛔ حالة الإطلاق: NO-GO

| البند المحجوب | الحالة |
|---|---|
| Supabase migrations مُدارة بالإصدار | ✅ مُنجز (P1A) — 7 migrations + rollback |
| RLS policies + `guard_*_deletion` RPC | ✅ مكتوبة ومُختبَرة (P1A) على Postgres حقيقي |
| **نشر المخطط على Supabase الإنتاجي** | ❌ لم يُطبَّق — الحُرّاس ما زالت تفشل مغلقة في الإنتاج |
| كتابات مالية ذرية | ❌ تسوية/توزيعات/التزام كتابات منفصلة — نطاق P1B |
| نسخ احتياطي يغطي Supabase | ❌ النسخ الحالي يقرأ localStorage فقط |

البوابات الخضراء تثبت **عقد العميل** فقط — لا تثبت أن الإنتاج يعمل.

| البُعد | التقييم |
|---|---|
| Type Safety | 9.7 |
| Test Coverage (Core) | 9.0 |
| Test Coverage (UI) | 4.0 |
| Architecture Adherence | 8.5 |
| Documentation Accuracy | 8.0 |
| Security / ErrorBoundary | 8.8 |
| Accessibility / RTL | 9.0 |
| Performance / Bundle | 7.5 |
| Maintainability (RHF+Zod) | 8.5 |
| Business Logic | 9.0 |

---

## 8. التعارضات والفجوات المعروفة (مُحدَّثة)

### مغلقة ✅ (10/14 تعارض، 6/9 فجوات)
- C1: OMR currency ✅
- C5: i18n — 40% مُفعّل ✅
- G1: OperationalEvent UI ✅
- G3: Charts / Recharts ✅
- G4: React Hook Form + Zod ✅
- C8: open_obligations ✅ (قرار موثق)

### مفتوحة ⚠️ (P2)
- **C3:** routing `/projects/$id` موحد — ADR-004 لم يُحدَّث — low priority
- **C4:** Partner `role` vs `category` — تسمية فقط — low priority
- **G2:** StockAdjustment UI — types+storage موجودة — UI قادم
- **G5:** ExchangeRate master UI — FX يُدخل يدوياً حالياً
- **i18n:** باقي الصفحات (Agriculture, Livestock, etc.) ما زالت hard-coded

### Dead Dependency متبقي
- `@tanstack/react-table` — مُستخدم فعلاً في `ObligationsTable.tsx` + `RealEstateTable.tsx` ← **ليس dead**، توثيق الـ audit خاطئ

---

## 9. خارطة الطريق — الأسابيع القادمة

### P2 — جارٍ التنفيذ
- [x] StockAdjustment UI (`/assets` → panel للأصول الحية) ✅
- [x] PartnerForm + ObligationForm → RHF+Zod ✅ (كان مكتملاً)
- [x] i18n: AgriculturePage + LivestockPage ✅

### P3 — مخطط
- [ ] PDF Export (ProfitabilityPage) — `@react-pdf/renderer` مُثبت
- [ ] Excel Export — `xlsx.ts` موجود
- [ ] Lighthouse audit → هدف > 90
- [ ] E2E tests (Playwright)
- [ ] ExchangeRate master storage + UI

### P4 — Scale
- [ ] Supabase migration (schema موجود في domain.ts)
- [ ] Multi-user / auth
- [ ] Cloud sync

---

## 10. القرارات المعمارية النافذة

مكانها الكامل: `docs/architecture-decisions.md` + `docs/decisions/README.md`

| ADR | القرار |
|---|---|
| ADR-001 | العملات — 7 عملات — FX وقت المعاملة — كل قيم بـ EGP |
| ADR-002 | Partner Hybrid — equity + counterparty في نفس النموذج |
| ADR-003 | Event Sourcing — OperationalEvent + StockAdjustment |
| ADR-004 | Routing — `/projects/$id` موحد (تباين مع الوثيقة، مقبول) |
| ADR-005 | لا ERP runtime dependencies — كل المنطق Terranex-native TypeScript |
| ADR-006 | i18n — تفعيل AR/EN ثنائي — `useI18n()` |
| ADR-007 | بنية المجلدات `src/features/` + `src/core/` |
| ADR-008 | ~~Local-first — localStorage~~ → **متجاوَز**: Supabase Postgres + Auth مصدر البيانات؛ IndexedDB للملفات؛ لا demo data في production |
| ADR-009 | Migrations آمنة — تحفظ السجلات غير القابلة للترحيل للمراجعة |
| ADR-010 | Settlement Engine — partial + full + reversal + audit trail |

---

## 11. إرشادات للوكلاء والمطورين

### قبل أي تعديل في الكود
1. اقرأ `AGENTS.md` كاملاً.
2. تأكد من التعارضات المعروفة في `docs/audit/CONFLICTS_ANALYSIS_AR.md`.
3. إذا تغيير يمس `domain.ts` → موافقة مالك المشروع.

### قبل أي تعديل في الوثائق
1. لا تعدّل الملفات في `docs/_archive/`.
2. إذا وجدت تعارضاً جديداً، أضفه في `CONFLICTS_ANALYSIS_AR.md` أولاً.
3. التعريف الموحد `docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md` هو المرجع الأعلى للوثائق.

### أوامر التحقق
```bash
npm ci
npm run typecheck   # 0 errors مطلوب قبل أي commit
npm run lint        # source hygiene
npm run test        # 96/96 pass
npm run build       # success
```

---

*Terranex MASTER.md — v1.7 — 2026-07-25 (P1A: versioned schema)*

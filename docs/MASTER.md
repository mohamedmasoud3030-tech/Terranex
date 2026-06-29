# Terranex — وثيقة المشروع الموحدة
**الإصدار:** v1.5  
**التاريخ:** 2026-06-29  
**المرجع الكنسي:** يسبق جميع وثائق `docs/` ما عدا ما في `docs/audit/`

> هذه الوثيقة تجمع الحالة الفعلية للمشروع بعد تدقيق 28 يونيو 2026.  
> للقرارات المعمارية التفصيلية: `docs/architecture-decisions.md`  
> للتعارضات المعروفة: `docs/audit/CONFLICTS_ANALYSIS_AR.md`

---

## 1. هوية المشروع

**Terranex** هو **نظام تشغيل استثماري عربي-أول** (Arabic-first RTL) مع دعم EN ثنائي لإدارة أصول ومشاريع شركة استثمارية عبر ثلاثة قطاعات.

**الشعار:** لا نبني واجهات لعرض البيانات — نبني العقل الرقمي للشركة الذي يجيب بدقة على سؤال الربحية والالتزامات.

**الحالة:** `v0.3.0-p2` — Production-Ready داخلياً ✅

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
| Storage | localStorage + IndexedDB (files) + ZIP backup |
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

### Storage Keys (localStorage)
```
terranex.projects.v1
terranex.assets.v1
terranex.partners.v1
terranex.transactions.v2       ← v2 بعد migration
terranex.obligations.v1
terranex.documents.v1
terranex.settlements.v1
terranex.settlementAllocations.v1
terranex.operationalEvents.v1
terranex.stockAdjustments.v1
terranex.projectPartners.v1
terranex.migrations.v1         ← حالة الـ migrations المُنفذة
```

### Bundle Size (بعد code-split)
```
index.js       : 441 KB │ gzip 126 KB   (initial)
charts-*.js    : 377 KB │ gzip 112 KB   (lazy — عند فتح Dashboard)
tanstack-*.js  : 120 KB │ gzip  38 KB
forms-*.js     :  97 KB │ gzip  28 KB
radix-*.js     :  33 KB │ gzip  11 KB
```

---

## 7. حالة الجودة — 29 يونيو 2026

```
typecheck : 0 errors    ✅
tests     : 61 / 61     ✅
lint      : pass        ✅
build     : success     ✅
```

**التقييم: 8.4 / 10**

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
- [ ] StockAdjustment UI (`/assets` → تبويب التسويات)
- [ ] PartnerForm + ObligationForm → RHF+Zod
- [ ] i18n: AgriculturePage + LivestockPage

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
| ADR-008 | Local-first — localStorage + IndexedDB — لا demo data في production |
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
npm run typecheck   # 0 errors مطلوب قبل أي commit
npm run test        # 61/61 pass
npm run lint        # source hygiene
npm run build       # success
```

---

*Terranex MASTER.md — v1.5 — 2026-06-29*

# Terranex — التعريف الموحد للمشروع
**تاريخ التوحيد:** 2026-06-28  
**المراجع:** جميع الوثائق في `docs/` + `AGENTS.md` + `IMPLEMENTATION_GUIDE.md` + الكود الفعلي

---

## 1. هوية المشروع

**Terranex** هو **نظام تشغيل استثماري عربي-أول (Arabic-first RTL)** لإدارة أصول ومشاريع شركة استثمارية عبر ثلاثة قطاعات متكاملة، بهدف أن يكون **العقل الرقمي للشركة** – ليس مجرد واجهات عرض.

**الشعار التشغيلي:**  
> لا نبني واجهات لعرض البيانات؛ نبني عقل الشركة الرقمي الذي يجيب بدقة على سؤال الربحية والالتزامات.

---

## 2. الأسئلة الجوهرية الأربعة (North Star)

النظام يجب أن يجيب خلال 10 ثوانٍ وبتتبع كامل:

1. **ماذا نملك / نشغل؟** — أصول ومشاريع وشركاء.
2. **كم كلف كل مشروع؟ وكم كسب؟**
3. **هل ربح أم خسر؟** — لكل مشروع / موسم / قطيع / أصل / قطاع / شريك.
4. **من له فلوس؟ ومن عليه فلوس؟** — ذمم مدينة ودائنة مربوطة بمستندات.

> سؤال خامس دائم: **ما الدليل؟** — كل رقم مربوط بمعاملة ومستند وقرار.

---

## 3. القطاعات الثلاثة

| القطاع | الأصول | العمليات الرئيسية | مؤشر الربحية |
|---|---|---|---|
| **الاستثمار العقاري** | أراضي، مباني، وحدات | شراء، تطوير، بيع، تأجير | مبيعات − تكاليف تطوير |
| **الاستثمار الزراعي** | مزارع، محاصيل، معدات | مواسم، زراعة، حصاد، بيع | مبيعات الموسم − تكاليف الموسم |
| **الاستثمار الحيواني** | قطعان، مجموعات حيوانية | شراء، أعلاف، علاج، ولادات، نفوق، بيع | مبيعات − رعاية وتغذية |

---

## 4. النموذج النطاقي الموحد (Domain Model v1.3)

الكيانات الأساسية — مطابقة للكود في `src/core/types/domain.ts`:

- **Sector**: `real-estate | agriculture | livestock`
- **Project**: حاوية الأعمال — يربط تكاليف، إيرادات، مستندات، أصول.
- **Asset**: مورد اقتصادي — type: `land | building | farm | equipment | herd | animal_group | crop | other`
- **Partner** (Hybrid ADR-002):
  - `equity_partner` → يملك نسبة via `ProjectPartner.equity_pct`
  - `counterparty` → مورد / عميل / ممول — بدون ملكية
- **Transaction**: حركة مالية
  - `direction: income | expense`
  - `amount`, `currency`, `fx_rate`, `amount_egp` (مُخزّن وقت الإنشاء)
  - `project_id` إجباري — لا معاملة بدون مشروع
- **Obligation**: ذمة مدينة/دائنة
  - `direction: receivable | payable`
  - `status: open | partial | settled | disputed | written_off`
  - `amount_settled_egp` تتبعي
- **Document**: دليل إثبات — `contract | invoice | receipt | ownership_deed | veterinary_record | sales_agreement | permit | court_document | other`
  - ملفات فعلية في IndexedDB + SHA256
- **OperationalEvent** (Event Sourcing – ADR-003): `birth | death | vaccination | treatment | feed_consumption | weighing | planting | harvest | ...` — **موجود في الـ types + storage لكن بدون UI حالياً**
- **StockAdjustment** (Direct track – ADR-003): تعديل يدوي للكميات والقيم — **موجود في الـ types + storage بدون UI**
- **Settlement / SettlementAllocation**: نظام تسوية متقدم جداً — تسوية واحدة عبر عدة التزامات، reversal مع audit trail، aging buckets — **منفذ بالكامل + 61 اختبار**

---

## 5. محرك الربحية — الصيغة المعتمدة (IMPLEMENTATION_GUIDE.md هو المصدر الكنسي)

```
إجمالي الإيرادات_egp = Σ income.amount_egp
إجمالي المصروفات_egp = Σ expense.amount_egp
الربح المحاسبي_egp = الإيرادات − المصروفات

الذمم المدينة المفتوحة = Σ receivable.open_balance
الذمم الدائنة المفتوحة = Σ payable.open_balance
التعرض النقدي = مدينة − دائنة

صافي الربح = الربح المحاسبي
(الالتزامات تُعرض منفصلة — لا تُخصم من الربح)
```

> **ملاحظة توحيد:** وثيقة `docs/domain-model.md` القديمة تذكر:  
> `Profit = total income - total expense - open provisions`  
> هذا **يتعارض** مع `IMPLEMENTATION_GUIDE.md` والكود الفعلي. **المعتمد هو IMPLEMENTATION_GUIDE.**

توزيع أرباح الشركاء:
```
share_egp = gross_profit_egp * equity_pct / 100
```

---

## 6. البنية التقنية المعتمدة (من الكود الفعلي — يونيو 2026)

**Frontend:**
- React 19 + TypeScript 5.8 + Vite 7
- TanStack Router v1 (manual route tree — لا file-based codegen)
- TanStack Query v5
- Tailwind CSS 3 + Radix UI primitives
- RTL عربي أصيل، Noto Kufi Arabic
- PWA: Service Worker + manifest

**State:**
- Server state: TanStack Query
- URL state: TanStack Router
- Form state: **يدوي حالياً** — react-hook-form مُثبت لكن غير مستخدم
- Local UI: useState

**Persistence (Phase 1 Local-first):**
- `localStorage` typed stores — `terranex.*.v1`
- IndexedDB للملفات الثنائية
- Migrations versioned في `migrations.ts`
- ZIP backup/restore كامل deterministc
- لا demo seeding في production runtime

**Validation:**
- Zod مُثبت — مستخدم جزئياً فقط (`finitePositiveNumberSchema`)
- Validation يدوي في storage layers

**i18n:**
- نظام `I18nProvider` + `t(key)` موجود كامل في `src/core/i18n/`
- ملفات `ar.ts` (250 مفتاح) و `en.ts` مطابقة
- **لكن غير مستخدم في صفحات الـ features — كل الصفحات hard-coded عربي**

**Charts:**
- `recharts` مُثبت في package.json
- **لا يوجد استخدام فعلي — لا مجلد `src/components/charts/`**

---

## 7. خارطة الطرق المُحدثة الموحدة

**Phase 1 — Foundation — ✅ منجز 95%**
- DB schema (types) ✅
- Auth — مؤجل (local-first)
- Projects / Assets / Partners / Transactions / Documents / Obligations ✅
- Dashboard + Sector pages ✅

**Phase 2 — Financial Layer — ✅ منجز 110% (تجاوز المخطط)**
- Profitability Engine ✅
- Obligation Management ✅
- Settlement Allocation Engine — **متقدم جداً، غير موثق في الرؤية الأصلية**
- Aging Query + Party Statement ✅
- Document-Transaction integrity guards ✅

**Phase 3 — Operational Events — ⚠️ 30%**
- Types + Storage ✅
- UI ❌ غائب تماماً
- Event → Transaction auto-link ❌

**Phase 4 — Reporting & Charts — ⚠️ 10%**
- ProfitabilityPage موجودة أساسية
- Recharts غير مستخدم
- Export PDF/Excel — غير موجود

**Phase 5 — Supabase / Multi-user — ⏳ مخطط**
- Schema جاهز في ADR-009
- RLS مخطط
- لم يبدأ التنفيذ

---

## 8. مبادئ المنتج الموحدة

1. **التتبع المالي قبل الجمال** — كل KPI قابل للـ drill-down
2. **عربي أول RTL أصيل** — ليس ترجمة لاحقة
3. **كثيف لكن مقروء** — dashboard تشغيلي
4. **وضوح قطاعي** — 3 قطاعات مميزة بصرياً ضمن نظام مالي واحد
5. **لا ذكاء زخرفي** — لا AI gradients، لا charts بلا أرقام
6. **لا أرقام بلا دليل** — كل رقم = معاملة + مستند + شريك
7. **Audit trail إلزامي** — reversal يحفظ التاريخ، لا حذف صامت
8. **Local-first آمن** — migrations، backup ZIP، deletion guards

---

## 9. تعريفات العملات المعتمدة

**في ADR-001:** `EGP | USD | OMR | SAR | AED | EUR | GBP`  
**في الكود (`domain.ts`):** `EGP | USD | SAR | AED | EUR | GBP`  
→ **OMR مفقود في الكود — يجب إضافته.**

العملة الأساسية للتقارير الموحدة: **EGP** دائماً.  
كل معاملة تُخزن: `amount` + `currency` + `fx_rate` + `amount_egp`.

---

## 10. مؤشرات النجاح

النظام ناجح عندما يستطيع مستخدم الإجابة:
> "كم ربح مشروع X؟"
خلال 10 ثوانٍ، مع تتبع كامل حتى المعاملة والمستند الأصلي.

حالياً: **نعم — Dashboard + ProjectDetailPage تحقق ذلك.**

---

*تم توحيد هذا التعريف من 23 وثيقة متفرقة + مراجعة الكود الفعلي — 28 يونيو 2026*

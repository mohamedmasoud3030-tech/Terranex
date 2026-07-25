# Terranex

نظام تشغيل استثماري لإدارة أصول ومشاريع الشركة عبر القطاعات العقارية والزراعية والحيوانية.

## الهدف

تحويل بيانات الشركة التشغيلية والمالية إلى نظام واحد يعرف:

- الأصول والمشاريع والشركاء.
- المصروفات والإيرادات.
- الأرباح والخسائر.
- الذمم المدينة والدائنة: من له فلوس؟ ومن عليه فلوس؟
- المستندات والقرارات والسجل التشغيلي.

## نطاق البداية

هذه المرحلة تؤسس طبقة العمل داخل الريبو:

- `AGENTS.md` لتوجيه الوكلاء البرمجيين.
- `.ai/agents/` لتعريف أدوار الوكلاء.
- `.ai/skills/` لتعريف المهارات القابلة لإعادة الاستخدام.
- `docs/` لتوثيق الخطة، الأهداف، النموذج النطاقي، وخارطة الطريق.

## القطاعات الأساسية

1. الاستثمار العقاري: أراضي، أصول، شراء، تطوير، بيع، تكاليف، أرباح.
2. الاستثمار الزراعي: مزارع، محاصيل، مواسم، إنتاج، مصاريف، مبيعات، ربحية الموسم.
3. الاستثمار الحيواني: قطعان، أعلاف، علاج، تحصينات، ولادات، نفوق، بيع، ربحية القطيع.

## مبدأ المنتج

لا نبني مجرد واجهات لعرض البيانات؛ نبني عقل الشركة الرقمي الذي يجيب بدقة على سؤال الربحية والالتزامات لكل مشروع وقطاع وشريك.

---

## 🚦 حالة الإطلاق — 25 يوليو 2026

> **الحالة: NO-GO.** البوابات الخمس خضراء، لكن الإطلاق محجوب ببنود مذكورة أدناه.

### طبقة التخزين والمصادقة — الحالة الفعلية

- **التخزين:** Supabase (Postgres) عبر `createSupabaseStore` — **مستخدم حالياً** في كل مخازن الميزات
  (projects, partners, assets, documents, transactions, obligations, settlements,
  settlement_allocations, operational_events, stock_adjustments).
- **Auth:** Supabase Auth — **مستخدم حالياً** (`src/core/auth/AuthProvider.tsx`, `supabaseClient.ts` بجلسة مُستمرة).
- **localStorage:** لم يعد مخزن بيانات. يقتصر استخدامه على تفضيلات الواجهة (locale, theme, exchange rates)،
  وملفات IndexedDB للمستندات، وترحيلات البيانات القديمة قبل الانتقال إلى Supabase.

### بوابات الجودة — مقاسة على الفرع الحالي

```
npm ci          ✅
npm run typecheck   ✅ 0 errors
npm run lint        ✅ pass
npm run test        ✅ 96 / 96 pass
npm run build       ✅ success
```

كل ملف اختبار يمر أيضاً في عملية Node مستقلة (لا اعتماد على ترتيب التشغيل أو state مشترك).

### لماذا الإطلاق ما زال NO-GO

| البند | الحالة |
|---|---|
| Supabase migrations مُصدّرة ومُدارة بالإصدار | ❌ غير موجودة — المخطط غير مُعرّف في الريبو |
| RLS policies + `guard_*_deletion` RPC على الخادم | ❌ غير مُنشأة — حُرّاس الحذف تفشل مغلقة في الإنتاج |
| كتابات مالية ذرية (تسوية + توزيعات + التزام) | ❌ كتابات متعددة غير ذرية — انقطاع جزئي يترك بيانات غير متسقة |
| نسخ احتياطي/استرجاع من Supabase | ❌ النسخ الاحتياطي الحالي يقرأ localStorage فقط ولا يغطي بيانات Postgres |

هذه البنود نطاق **المرحلة الثانية** ولم تُلمس في هذا الفرع.

---

## 📋 تدقيق 28 يونيو 2026 — أرشيف تاريخي

> ⚠️ ما يلي **لقطة تاريخية** من تدقيق 28 يونيو 2026، **قبل** الانتقال من localStorage إلى Supabase.
> أرقامه (61/61 اختبار، تقييم 7.3/10، «Production-Ready داخلياً») **لم تعد تصف الحالة الحالية**.
> اعتمد على قسم «حالة الإطلاق» أعلاه.

**التقارير الكاملة:**
- [`docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md`](docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md) — التعريف الموحد الكنسي للمشروع
- [`docs/audit/CONFLICTS_ANALYSIS_AR.md`](docs/audit/CONFLICTS_ANALYSIS_AR.md) — 14 تعارض حرج + 9 فجوات
- [`docs/audit/CODE_REVIEW_REPORT_AR.md`](docs/audit/CODE_REVIEW_REPORT_AR.md) — مراجعة كود شاملة — تقييم **7.3/10**
- [`docs/audit/RECOMMENDATIONS_AND_ROADMAP_AR.md`](docs/audit/RECOMMENDATIONS_AND_ROADMAP_AR.md) — خارطة طريق مصححة 12 أسبوع

**أهم النتائج:**
- المحرك المالي (profitability + settlement allocation) **بمستوى ERP احترافي**
- **3 فجوات P0** تحتاج سد فوري: OMR currency، OperationalEvent UI، ErrorBoundary
- i18n system موجود لكن **0% استخدام** — يحتاج قرار: Arabic-only أو تفعيل كامل
- 3 dependencies ميتة: `recharts`, `@tanstack/react-table`, `react-hook-form` — ~200KB dead weight

> **توصية التدقيق آنذاك** كانت «Production-Ready داخلياً بعد سد P0 gaps».
> **هذه التوصية متجاوَزة.** الانتقال إلى Supabase أدخل فجوات جديدة (migrations، RLS/RPC،
> ذرّية الكتابات المالية، النسخ الاحتياطي) والحالة الحالية **NO-GO** — راجع الجدول أعلاه.

---

## الوثائق الكنسية (مُحدّثة يونيو 2026)

1. **[UNIFIED_PROJECT_DEFINITION_AR.md](docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md)** — التعريف الموحد — ابدأ هنا
2. **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** — دليل التنفيذ الـ runtime — المصدر الكنسي التقني
3. **[AGENTS.md](AGENTS.md)** — سياسة الريبو للوكلاء
4. **[docs/architecture-decisions.md](docs/architecture-decisions.md)** — ADR‑001 … ADR‑010 (مع ملاحظات الانحراف في تقرير التعارضات)
5. **[docs/plans/terranex-native-engine-extraction-plan.md](docs/plans/terranex-native-engine-extraction-plan.md)** — يصف Settlement Allocation Engine الفعلي بدقة

> ⚠️ **تحذير:** وثائق `docs/domain-model.md` و `docs/reference/Terranex-Architecture-English.md` تحتوي معلومات قديمة متضاربة — استخدم التعريف الموحد أعلاه.

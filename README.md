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

## 📋 التدقيق الشامل — يونيو 2026

تم إجراء **مراجعة شاملة كاملة** للمستودع بتاريخ **28 يونيو 2026**:

- ✅ **Typecheck:** 0 errors
- ✅ **Tests:** 61/61 pass
- ✅ **Build:** success (608KB / 180KB gzip)
- ✅ **Lint:** pass

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

> **التوصية:** المشروع **Production-Ready داخلياً بعد سد P0 gaps (2–4 أيام عمل).**  
> راجع `docs/audit/README.md` للبداية السريعة.

---

## الوثائق الكنسية (مُحدّثة يونيو 2026)

1. **[UNIFIED_PROJECT_DEFINITION_AR.md](docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md)** — التعريف الموحد — ابدأ هنا
2. **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** — دليل التنفيذ الـ runtime — المصدر الكنسي التقني
3. **[AGENTS.md](AGENTS.md)** — سياسة الريبو للوكلاء
4. **[docs/architecture-decisions.md](docs/architecture-decisions.md)** — ADR‑001 … ADR‑010 (مع ملاحظات الانحراف في تقرير التعارضات)
5. **[docs/plans/terranex-native-engine-extraction-plan.md](docs/plans/terranex-native-engine-extraction-plan.md)** — يصف Settlement Allocation Engine الفعلي بدقة

> ⚠️ **تحذير:** وثائق `docs/domain-model.md` و `docs/reference/Terranex-Architecture-English.md` تحتوي معلومات قديمة متضاربة — استخدم التعريف الموحد أعلاه.

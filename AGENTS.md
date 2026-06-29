# Terranex — Agent Policy
**آخر تحديث:** 2026-06-29  
**الحالة:** كنسي — يسبق جميع الوثائق الأخرى

---

## ⚠️ قراءة إلزامية قبل أي تعديل

اقرأ بالترتيب:

1. **هذا الملف** — السياسة الكاملة
2. [`IMPLEMENTATION_GUIDE.md`](IMPLEMENTATION_GUIDE.md) — خريطة الـ runtime الفعلية
3. [`docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md`](docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md) — التعريف الموحد للمشروع (v1.4)
4. [`docs/audit/CONFLICTS_ANALYSIS_AR.md`](docs/audit/CONFLICTS_ANALYSIS_AR.md) — تعارضات معروفة + حالتها
5. [`docs/decisions/README.md`](docs/decisions/README.md) — قرارات معمارية نافذة

---

## حدود المشروع

- Terranex مشروع **مستقل تماماً** عن Rentrix أو أي تطبيق آخر.
- كل scope، domain model، وثائق، وأصول automation تخص Terranex فقط.
- لا تستورد منطق أو كود من مشاريع خارجية.

---

## المصادر الكنسية — الأولوية بالترتيب

| الأولوية | المصدر | يغطي |
|---|---|---|
| **1** | `src/core/types/domain.ts` | نموذج البيانات الفعلي — source of truth مطلق |
| **2** | `IMPLEMENTATION_GUIDE.md` | runtime، storage، features، profitability |
| **3** | `docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md` | تعريف المشروع الموحد — v1.4 |
| **4** | `docs/decisions/README.md` + `docs/architecture-decisions.md` | ADR‑001 → ADR‑010 |
| **5** | `docs/audit/CONFLICTS_ANALYSIS_AR.md` | تعارضات معروفة + حالتها |
| **6** | `docs/plans/terranex-native-engine-extraction-plan.md` | Settlement Engine — الخطة الفعلية |

---

## وثائق مؤرشفة — لا تستخدمها مرجعاً

الملفات التالية نُقلت إلى `docs/_archive/` وتحتوي معلومات قديمة أو متضاربة:

- `docs/_archive/domain-model.STALE.md` — نموذج قديم — استخدم `domain.ts`
- `docs/_archive/Terranex-Architecture-English.STALE.md` — معمارية مايو 2026 قديمة
- `docs/_archive/product-vision.STALE.md` — رؤية قديمة — استخدم UNIFIED_PROJECT_DEFINITION_AR.md
- `docs/reference/Terranex-Architecture-English.md` — **غير موجود** (أُرشف)

**إذا وجد تعارض بين وثيقة وبين `domain.ts` أو `IMPLEMENTATION_GUIDE.md`، فالكود يسبق الوثيقة.**

---

## North Star — الأسئلة الأربعة

1. ماذا نملك / نشغل؟ ← Assets + Projects + Partners + Events
2. كم كلّف كل مشروع؟ وكم كسب؟ ← Transactions
3. هل ربح أم خسر؟ ← ProfitabilityEngine (`profitability.ts`)
4. من له فلوس؟ ومن عليه فلوس؟ ← Obligations + Settlements

---

## حالة الكود — 29 يونيو 2026

```
typecheck : 0 errors ✅
tests     : 61 / 61 pass ✅
build     : success ✅
bundle    : 441 KB initial / 126 KB gzip ✅
```

**التقييم الحالي: 8.4 / 10**

---

## ما يجوز تغييره بدون موافقة مسبقة

- إصلاح bug موثق في `docs/audit/CONFLICTS_ANALYSIS_AR.md`
- إضافة i18n key في `ar.ts` / `en.ts`
- إضافة test في `tests/`
- تحديث توثيق في `docs/`

## ما يحتاج موافقة مسبقة (قرار مالك)

- تغيير نموذج البيانات في `domain.ts`
- إضافة dependency جديدة
- تغيير routing scheme
- حذف feature
- تغيير منطق الربحية (`profitability.ts`)

---

## تفضيلات هندسية

- وثّق قبل أن تنفذ.
- المنطق المالي يجب أن يكون auditable وقابلاً للتتبع.
- استخدم Zod schemas من `validation.ts` — لا تكتب validation يدوي جديد.
- استخدم `rg` / `rg --files` للبحث في الريبو.
- لا تُضف migrations مدمرة — صمّم migrations بحفظ السجلات القديمة.
- كل PR محصور في مرحلة واحدة معتمدة.
- لا تُفعّل demo data أو fixtures تلقائياً في production runtime.

---

## بنية المجلدات

```
src/
  core/types/domain.ts     ← source of truth للـ types
  core/lib/profitability.ts ← محرك الربحية
  core/storage/migrations.ts← migrations آمنة
  features/                 ← features مستقلة
docs/
  audit/                    ← تقارير التدقيق 28 يونيو 2026
  decisions/                ← ADRs
  plans/                    ← خطط التنفيذ
  ai/                       ← توجيهات الوكلاء
  _archive/                 ← وثائق مؤرشفة — لا تُعدّل
tests/                      ← 16 ملف اختبار — 61 اختبار
```

---

## في حالة تعارض الوثائق

**الأولوية المطلقة:** `src/core/types/domain.ts` → `IMPLEMENTATION_GUIDE.md` → `UNIFIED_PROJECT_DEFINITION_AR.md` → باقي الوثائق

إذا وجدت تعارضاً غير موثق في `CONFLICTS_ANALYSIS_AR.md`، أضفه فوراً هناك قبل أن تعالجه.

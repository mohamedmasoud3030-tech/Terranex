# Terranex — Product

> Product definition. The full market/charter contract is
> `greenfield/01_PRODUCT_CHARTER_AND_MARKET.md`; sector models are
> `greenfield/04_SECTOR_MODELS.md`; standing decisions are in `decisions/`.

## Product

An Arabic Investment Operations OS for private investment companies. It
connects daily operations to money and control: assets and operating
cycles, suppliers and procurement, obligations and payments, bank
statements and reconciliation, revenue and collection, double-entry
financial postings, period closing, evidence, risk, and decisions.

## Customer

Private investment companies running projects across up to three sectors —
Real Estate first, Agriculture second, Livestock third (sector expansion
sequence, ADR-0012 in `decisions/`) — that need portfolio-level truth
without giving up project-level operational detail.

## Model

`Organization → Investment Portfolio → Investment Project → sector facts /
finance facts / evidence`. One project belongs to exactly one primary
sector. Financial facts are posted through the finance core with
period-close and correction controls (S6), never as free-form edits.

## Boundaries

- Implementation, deployment and customer evidence are separate claims;
  a synthetic demo is never customer evidence (see `GREENFIELD_EXECUTION.md`).
- Pending owner/business choices live only in `OPEN_BUSINESS_DECISIONS.md`.
---


## 📖 دليل المزايا والشاشات — تفصيلي (مزامنة مركز القيادة 2026-10-23)


### ما هو النظام؟

منصة استثمار المالك: محافظ ← مشاريع (عقار / زراعة / مواشي / توريد)، محاسبة دقيقة بالعملات، وقرارات مالك موثقة (34 ADR).

### المزايا الرئيسية

- إدارة محافظ ومشاريع متعددة الأنواع
- استقبال أصول (intake) وتوثيقها
- محاسبة بالعملات بدقة عالية
- قرارات مالك مسجلة وقابلة للتدقيق
- أدلة تشغيل كاملة (runbooks)
- هوية وحملة تسويق مدمجة (أسبوع 1 جارية الآن)

### رحلات المستخدم النموذجية

1. تسجيل مشروع جديد في محفظة ← توثيق الأصول والتكاليف ← متابعة مالية دورية ← قرار مالك ← تسجيل ADR ← تقرير أداء المحفظة

### الشاشات / الصفحات (من شجرة الكود الفعلية)

**مسارات التطبيق (Next.js app router)** (29):
- `‎/assets‎` · `‎/intake‎` · `‎/onboarding‎` · `‎/portfolios‎`
- `‎/portfolios/[portfolioId]‎` · `‎/portfolios/new‎` · `‎/projects‎` · `‎/projects/[projectId]‎`
- `‎/projects/[projectId]/agriculture‎` · `‎/projects/[projectId]/budget‎` · `‎/projects/[projectId]/cash‎` · `‎/projects/[projectId]/close‎`
- `‎/projects/[projectId]/controls‎` · `‎/projects/[projectId]/costs‎` · `‎/projects/[projectId]/funding‎` · `‎/projects/[projectId]/governance‎`
- `‎/projects/[projectId]/intake‎` · `‎/projects/[projectId]/integrity‎` · `‎/projects/[projectId]/investors‎` · `‎/projects/[projectId]/livestock‎`
- `‎/projects/[projectId]/livestock/operations‎` · `‎/projects/[projectId]/operations‎` · `‎/projects/[projectId]/overview‎` · `‎/projects/[projectId]/pilot‎`
- `‎/projects/[projectId]/procurement‎` · `‎/projects/[projectId]/revenue‎` · `‎/projects/[projectId]/statements‎` · `‎/projects/[projectId]/terms‎`
- `‎/projects/new‎`

### الحالة والمرجعية

**Pre-Pilot** — خارطة R0→R17 وحزمة جاهزية تجريبية من 13 وثيقة. `.env.production` أُزيل ✅

> هذا القسم وصفي تفصيلي؛ لا يغني عن `docs/STATUS.md` للحالة، ولا يُكرر محتواه — يحدّثه مدير المحفظة عند أي تغيير جوهري في المنتج.

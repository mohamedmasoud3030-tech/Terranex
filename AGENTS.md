# Terranex — Agent Policy

**آخر تحديث:** 2026-08-04  
**الحالة:** كنسي — يسبق جميع الوثائق الأخرى

---

## قراءة إلزامية قبل أي تعديل

اقرأ بالترتيب:

1. **هذا الملف** — السياسة والحالة الحالية.
2. [`IMPLEMENTATION_GUIDE.md`](IMPLEMENTATION_GUIDE.md) — خريطة الـruntime الفعلية.
3. [`docs/release/LAUNCH_READINESS_2026-08-04.md`](docs/release/LAUNCH_READINESS_2026-08-04.md) — قرار جاهزية الإطلاق وأدلته.
4. [`docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md`](docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md) — حدود RPC المرتفعة المسموح بها.
5. [`docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md`](docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md) — تعريف المشروع الموحد.
6. [`docs/decisions/README.md`](docs/decisions/README.md) — القرارات المعمارية النافذة.

---

## حدود المشروع

- Terranex مشروع مستقل تمامًا عن Malik أو LENA أو أي تطبيق آخر.
- مصر هي سوق الإطلاق الأول، والعملة الأساسية لأول تشغيل هي EGP.
- Terranex يملك التشغيل والمشروعات والمستثمرين والملكية ورأس المال والتوزيعات.
- Odoo يملك الدفتر المحاسبي الرسمي والتوطين المصري والإقفال والتقارير القانونية.
- لا يوجد دفتران رسميان متنافسان؛ جداول Terranex المالية subledgers تشغيلية قابلة للتدقيق.

---

## المصادر الكنسية — الأولوية

| الأولوية | المصدر | يغطي |
|---:|---|---|
| 1 | `src/core/types/domain.ts` | نموذج البيانات الفعلي |
| 2 | `supabase/migrations/` + `supabase/tests/` | مخطط الإنتاج، RLS، RPCs، والعقود المثبتة |
| 3 | `IMPLEMENTATION_GUIDE.md` | runtime والتخزين والتدفقات |
| 4 | `docs/release/LAUNCH_READINESS_2026-08-04.md` | حالة الإطلاق الحالية |
| 5 | `docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md` | حدود الصلاحيات المرتفعة |
| 6 | `docs/audit/UNIFIED_PROJECT_DEFINITION_AR.md` | التعريف الوظيفي الموحد |
| 7 | `docs/decisions/README.md` + `docs/architecture-decisions.md` | القرارات المعمارية |

إذا تعارضت وثيقة قديمة مع الكود أو migrations أو تقرير الإطلاق الحالي، فالكود والمخطط الفعلي يسبقانها.

---

## North Star

1. ماذا نملك أو نشغّل؟ ← Projects + Assets + Partners + Inventory + Events.
2. كم كلّف كل مشروع وكم كسب؟ ← Transactions + Sales/Purchase Invoices + Obligations.
3. هل ربح أم خسر؟ ← Profitability Engine + Journals + Odoo accounting bridge.
4. من له فلوس ومن عليه فلوس؟ ← Settlements + Bank Accounts + Partner Ledger + Distributions.

---

## الحالة الفعلية — 4 أغسطس 2026

### الكود والنشر

- `main`: `41b12db824356458216021eadeff483549717499` قبل PR جاهزية الإطلاق الحالي.
- Typecheck: ناجح.
- Lint: ناجح.
- Node tests: 282/282 على `main`، ويضيف PR جاهزية الإطلاق اختبارات قائمة السماح.
- Build: ناجح.
- Vercel Production: `READY`.
- `https://terranex.vercel.app`: HTTP 200.
- Vercel runtime errors خلال آخر 24 ساعة: صفر وقت آخر تحقق.

### قاعدة البيانات والتكامل

- Supabase Postgres وSupabase Auth هما runtime الإنتاجي الفعلي.
- مخطط الإنتاج منشور؛ 45 migration مطبقة وقت آخر تحقق.
- المخطط القابل لإعادة البناء يحتوي نطاق التشغيل والمالية والبنوك والفواتير والمخزون والقيود والملكية والتوزيعات وOdoo outbox.
- RLS مفعل ومُجبر على الجداول التشغيلية مع عزل مالك مركب.
- anonymous-executable `SECURITY DEFINER`: صفر.
- externally executable trigger functions: صفر.
- حدود `authenticated SECURITY DEFINER` ثابتة في قائمة سماح من 25 RPC ومختبرة على PostgreSQL حقيقي.
- Edge Functions النشطة: `odoo-sync` و`odoo-investor-sync`.

### قرار الإطلاق

- **عرض الديمو وجولة العميل: GO.**
- **تشغيل أموال حقيقية: CONDITIONAL NO-GO** حتى إغلاق الأدلة اليدوية الثلاثة:
  1. تفعيل Supabase leaked-password protection.
  2. إثبات backup/restore أو PITR باختبار استرجاع.
  3. التحقق من Odoo الحقيقي والتوطين المصري وأكواد الحسابات والدورات المحاسبية.

لا يجوز وصف التطبيق بأنه Live-money GO قبل توثيق هذه الأدلة في تقرير إطلاق مؤرخ جديد.

---

## قواعد قاعدة البيانات والأمان

- لا تعدّل migration مدمجة؛ أضف migration تالية idempotent وrollback مناسبًا.
- كل كتابة مالية مادية يجب أن تمر عبر RPC ذرّي بخاصية idempotency وأثر تدقيقي.
- العكس append-only؛ لا تمسح التاريخ المالي لتصحيح خطأ.
- `PUBLIC` و`anon` ممنوعان من تنفيذ أي `SECURITY DEFINER`.
- أي RPC مرتفع جديد يتطلب تحديث قائمة السماح واختبارات anonymous-deny وowner isolation.
- trigger functions والـlocking/audit helpers ليست PostgREST endpoints.
- أسرار Odoo لا تدخل Vite أو Git أو جداول المتصفح؛ تبقى في Supabase Edge Function secrets.
- لا ترسل بيانات الديمو إلى Odoo حقيقي.

---

## قواعد تجربة المستخدم والبيانات

- العربية وRTL هما المسار الأول، مع دعم الإنجليزية.
- لا تُنشئ fixtures تلقائيًا لكل مستخدم إنتاجي.
- حساب الديمو المخصص قد يحتوي بيانات موسومة بوضوح «ديمو / DEMO».
- لا تدّعِ أن bank-statement reconciliation أو Odoo reverse sync أو ETA مكتملة ما لم توجد دورة تنفيذ واختبارات فعلية.
- أي شاشة تعتمد على Supabase يجب أن تعرض loading/error/empty states بصدق، ولا تحوّل خطأ تحميل إلى «لا توجد بيانات».

---

## ما يجوز تغييره بدون موافقة مسبقة

- إصلاح bug مثبت أو production drift.
- إضافة regression test أو release/security gate.
- تحديث توثيق يزيل معلومات قديمة.
- إضافة i18n key بدون تغيير منطق النطاق.
- hardening غير مدمّر يحافظ على التدفقات الحالية.

## ما يحتاج قرار مالك صريح

- تغيير نموذج الملكية أو تعريف الربحية.
- حذف feature أو تغيير routing scheme جذريًا.
- إضافة dependency كبيرة أو مزود خارجي جديد.
- تغيير الفصل بين Terranex وOdoo كمصادر حقيقة.
- فتح صلاحيات RPC جديدة أو تخفيف RLS.

---

## بوابات التحقق الإلزامية

قبل الدمج:

```bash
npm ci
npm run typecheck
npm run lint
npm run test
npm run build
```

وعند لمس قاعدة البيانات:

```bash
scripts/db-test.sh
```

اختبار PostgreSQL يجب أن يثبت replay، schema contract، RLS لهويتين، RPC atomicity، الملكية، البنوك والفواتير والمخزون، Odoo، investor lifecycle، قائمة السماح، rollback/reapply، وidempotent replay.

---

## بنية المجلدات

```text
src/                 runtime والواجهات والخدمات
tests/               اختبارات Node وUI/source contracts
supabase/migrations/ مخطط قاعدة البيانات المُدار بالإصدار
supabase/rollback/   rollback مطابق
supabase/tests/      اختبارات PostgreSQL الحقيقية
supabase/functions/  Odoo Edge Functions server-side
docs/release/        قرارات وأدلة الإطلاق
docs/security/       عقود الصلاحيات والأمان
docs/audit/          تقارير التدقيق
docs/decisions/      ADRs
docs/_archive/       وثائق قديمة لا تُستخدم مرجعًا
```

---

## قاعدة عدم التضليل

لا تستخدم تقريرًا قديمًا لإعلان حالة حالية. كل claim عن النشر أو الأمان أو عدد الاختبارات أو جاهزية الإطلاق يجب أن يكون مرتبطًا بـSHA وبيئة وتاريخ تحقق واضحين.
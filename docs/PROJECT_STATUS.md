# الحالة الواقعية لمشروع Terranex

**تاريخ baseline:** 2026-08-17
**Commit:** `9488588f0c6fd1984a1c09769af480f85905c661`
**مهم:** هذا تقرير اكتشاف، وليس شهادة production readiness أو مراجعة محاسبية/قانونية.

## 1. Git وحالة المستودع

### مؤكد

- checkout shallow: `git rev-parse --is-shallow-repository` أعاد `true`؛ لذلك التاريخ المحلي الكامل غير متاح.
- worktree واحد فقط: `/home/user/Terranex`.
- الفرع العامل: `arena/01a00fc0-terranex`.
- local `main` و`origin/main` كانا على نفس commit وقت البداية.
- `git rev-list --left-right --count origin/main...HEAD` أعاد `0 0`.
- لم تكن هناك تغييرات محلية قبل الاكتشاف.
- الملفات الجديدة الوحيدة المقصودة من هذا العمل هي وثائق الاكتشاف الأربع.
- package manager: npm، lockfile v3، وليس monorepo.
- Open GitHub PR واحد وقت الفحص: `#164 fix: make S6 close commands replay-safe end to end` من فرع آخر؛ ليس جزءًا من commit الحالي.
- Open issues: `#155` لإغلاق قرارات R14، و`#34` دراسة مرجعية قديمة/مستقبلية.

## 2. ما تم التحقق أنه يعمل

### فحوص التطبيق المحلية على نفس HEAD

| الأمر | النتيجة |
|---|---|
| `npm ci --no-audit --no-fund` | PASS؛ 493 packages، مع warning واحد عن dependency deprecated (`whatwg-encoding`). |
| `npm run lint` | PASS. |
| `npm run typecheck` | PASS. |
| `npm test` | PASS: **52/52 files، 714/714 tests**. |
| production build مع placeholder Supabase env | PASS؛ Next.js أنشأ **30 route**. |
| `npm audit --omit=dev --audit-level=low` | PASS: 0 vulnerabilities. |
| `npm audit --audit-level=low` | PASS: 0 vulnerabilities. |
| readiness inventory | PASS: 45 artifacts موجودة، 0 missing. |
| readiness pack validator | PASS. |
| `git diff --check` قبل التوثيق | PASS. |

### smoke آمن

شُغل production server محليًا على placeholder Supabase endpoint، دون الاتصال ببيئة Terranex الحقيقية:

- server بدأ على `0.0.0.0:3000`.
- `GET /login` أعاد `200` وHTML عربي بعنوان `تيرانكس`.
- `GET /` بدون session أعاد `307 → /login`.
- `GET /projects` بدون session أعاد `307 → /login`؛ هذا لا يثبت وجود الصفحة بعد الدخول. build يثبت أن route نفسه غير موجود.

لم تُفحص الرحلات authenticated بصريًا لعدم وجود test tenant آمن محلي، ولأن تعليمات المستودع تمنع لمس production/shared Supabase دون تفويض.

### قاعدة البيانات

- `npm run db:test` **لم يعمل محليًا**: لا `psql` ولا Docker في البيئة؛ خرج code 2. هذا unresolved local gate، وليس PASS محليًا.
- يوجد دليل مستقل على نفس commit: GitHub Actions run `32030212661` على SHA نفسه انتهى `success`، وjob `database` وjob `app` كلاهما `success` بتاريخ 2026-08-17.
- workflow database يشغل PostgreSQL 16 و`bash ./scripts/db-test.sh`، الذي يعيد تشغيل كل 97 migrations ثم 105 suites بعد bootstrap (SQL + shell، تشمل concurrency/upgrade/backup/RLS/full scenario).
- لم يمكن تنزيل log archive الكامل من GitHub في جلسة الفحص بسبب EOF، لكن GitHub job metadata نفسها مؤكدة ومرتبطة بالـ SHA.

### قدرات مدعومة باختبارات قوية

- tenant isolation/RLS وحماية Security Definer.
- exact money وbalanced journal.
- idempotency/concurrency لكثير من الأوامر المالية والقطاعية.
- reversal، period lock، opening import، reconciliation.
- Real Estate، Agriculture، Livestock invariants والـ closeout.
- Procurement financial chain/evidence.
- Portfolio/project roll-ups وfull synthetic company scenario.
- policy block قبل R15.

## 3. فشل متوقع وليس bug

`npm run r15:admission` أعاد exit 1 و`R15 admission: BLOCKED` لأن كل القرارات `BD-001`…`BD-012` ما زالت `OPEN`.

هذا **سلوك أمان صحيح** حاليًا. يتحول إلى PASS فقط بعد قرارات مالك موثقة كاملة، وليس بإصلاح تقني أو default مخمّن.

## 4. عيوب حالية مؤكدة

### P1 — خمسة أوامر S6 ليست replay-safe بالكامل عند ضياع response

الكود الحالي لا يمرر idempotency key إلى DB في خمسة أوامر:

- create accounting period.
- prepare close run (الـ form لديه key، لكن RPC الحالي لا يخزن receipt حقيقيًا).
- request close-run exception.
- reopen period.
- request correction.

النتيجة: retry بعد نجاح DB وضياع response قد يعيد constraint/domain error بدل أن يعيد نفس النتيجة. هذا مثبت أيضًا بوجود PR `#164` المفتوح، لكن المصدر الأساسي هنا هو signatures الحالية في `src/features/close/actions.ts`, `src/features/close/schema.ts`, وmigrations الحالية. **الإصلاح ليس ضمن هذا discovery.**

### P1 — رابط `/projects` مكسور بعد الدخول

- `next build` لا يسجل route `/projects`.
- Home يربط KPI و“كل المشاريع” إليه.
- المستخدم المسجل سيصل إلى 404.
- global nav يستخدم `/` بدلًا منه، لذلك ليس كل دخول للمشاريع مكسورًا.

### P1 — demo seed القديم غير متوافق مع policy-safety على fresh DB

`scripts/demo/seed_real_estate_showcase.sql` يشغل `attach_contribution_cash` وS5 allocation/distribution، لكنه لا ينشئ `policy_authority`. migration الحالية تجعل هذه الأوامر fail-closed عندما registry فارغة. لذلك الوثيقة التي تصف seed بأنه قابلًا لإعادة التشغيل لا تنطبق على fresh current schema دون سياسة معتمدة. لم يُمس أي demo/shared database للتحقق الحي.

### P2 — Organization متعددة غير مكتملة في UI

Home، Intake، إنشاء Project، وقوائم أخرى تستخدم `organizations[0]`. لا يوجد Organization switcher أو active-org preference. RLS يدعم عضويات متعددة، لكن تجربة الاستخدام لا تمنح اختيارًا واضحًا.

### P2 — Project lifecycle أقل كثيرًا من الوثائق

Database العامة تسمح فعليًا بـ `DRAFT | FUNDING` للمشروع، والانتقال يحدث عند تفعيل agreement. لا يوجد command عام لحالات `DUE_DILIGENCE | ACTIVE | EXITING | CLOSED | CANCELLED` المذكورة في operating model. sector objects لها lifecycles أوسع، لكن هذا لا يكمل lifecycle الـ Project نفسه.

### P2 — unknown currency scale يفترض 2 decimals

`currencyDecimals()` يعيد 2 لأي currency غير موجودة في map، رغم أن التعليق يقول إن العملة غير المعروفة لا ينبغي معاملتها بصمت كـ2 decimals. Projects الحالية EGP، لكن FX/tax/reporting surfaces تقبل ISO code أوسع. هذا خطر دقة عند توسيع العملات.

### P2 — لا توجد صفحة Projects مستقلة رغم ادعاء Management UX complete

لا توجد `/projects`، كما لا توجد صفحات top-level لـ Documents، Approvals، Reports، Settings المذكورة في roadmap R9. بعض هذه القدرات موجود داخل Project pages، لكنها ليست navigation surfaces مستقلة كما تصف الوثائق.

## 5. مناطق ناقصة بوضوح

### المنتج والحسابات

- لا sign-up/invite/password reset/MFA/user profile/device sessions.
- roles الفعلية `OWNER | MEMBER` فقط؛ لا Finance/Operator/Reviewer/Auditor/Investor permissions مستقلة.
- لا project-scoped memberships ولا investor self-scope.
- لا Organization switcher.
- لا Project edit/general lifecycle/archive/cancel UI واضح.
- investor economics/distributions محجوبة حتى R14، وهو مقصود.

### frontend

- العربية فقط؛ English/LTR غير منفذ.
- لا PWA/offline/install/update/cache.
- لا automated accessibility gate أو browser E2E.
- responsive CSS موجود، لكن لم يُختبر على أجهزة/متصفحات حقيقية في هذا الفحص.
- لا generic error boundary لكل route؛ توجد فقط لبعض المجموعات.

### backend/integrations

- لا jobs/queues/webhooks/scheduled tasks.
- لا notifications/email/SMS/WhatsApp.
- لا payment/bank API، analytics، AI، maps، ETA، أو external accounting adapter.
- لا general document center؛ evidence storage الحالي خاص بـ Procurement.
- لا data export UI رغم إشارات roadmap إلى export.

### operations

- لا health endpoint، structured logger، tracing، metrics، APM، alerting.
- لا app deployment pipeline داخل Git؛ Vercel integration الخارجية غير معروفة.
- لا production backup schedule/retention مثبت.
- لا production restore أو customer UAT أو paid pilot مثبت.
- لا automated rollback. توجد runbooks فقط، والم migrations forward-only.

## 6. الاختبارات: ما تغطيه وما لا تغطيه

### الموجود

- 52 Vitest files / 714 tests.
- Zod/exact money unit tests.
- React component/idempotency/hydration tests باستخدام Testing Library/jsdom في ملفات محددة.
- كثير من “contract tests” يقرأ نص source/migration ويتأكد من وجود guards/surfaces.
- 105 DB suites بعد bootstrap: SQL behavior، two-tenant RLS، concurrency، forward upgrades، backup/restore rehearsal، full synthetic company scenario.
- lint، typecheck، production build في CI.
- npm dependency audit شُغل يدويًا في هذا الاكتشاف ونجح.

### غير الموجود

- لا Playwright/Cypress browser E2E.
- لا authenticated route smoke test في CI.
- لا automated accessibility test.
- لا visual regression.
- لا code coverage threshold/report.
- لا performance/load test.
- لا production/post-deploy smoke.
- لا `npm audit` داخل workflow الحالي.
- `npm run r15:admission` ليس step مباشرًا في CI؛ توجد unit tests للـ admission script.

## 7. التوثيق المتناقض أو القديم

عند التعارض، الكود/build/migrations/latest executable tests هي الحقيقة الحالية.

| الوثيقة/الادعاء | التعارض الحالي |
|---|---|
| `README.md` يقول إن pricing/invoice/payment في Procurement هي الخطوة التالية | الكود وmigrations الحالية نفذتها بالفعل؛ `docs/ROADMAP_R0_R17.md` الأحدث يقول R4 complete. |
| `README.md` و`GREENFIELD_EXECUTION.md` يقولان إن R4/R2/R3/R13 ما زالت خطوات تالية | أصبحت قديمة بعد addenda وlatest migrations/tests. |
| `FINAL_DELIVERY_REPORT.md` يقول Budget، FX، Executive Home، Portfolio roll-up، full simulation غير مكتملة | هذه snapshot تاريخية؛ الكود الحالي يحتويها. |
| القسم الأول من `docs/CURRENT_DELIVERY_STATUS.md` يسجل مراحل PARTIAL/NOT DELIVERED | addenda في نفس الملف supersede ذلك لاحقًا. |
| canonical UX يقول English/LTR supported وoffline drafts/PWA | runtime الحالي عربي/RTL فقط ولا PWA/offline. |
| canonical role model يسرد 7 أدوار وproject-scoped permission | runtime membership يطبق `OWNER | MEMBER` فقط على Organization. |
| roadmap R1 يذكر notifications foundation | لا notification tables/code. |
| roadmap R9 “complete” يذكر Projects/Documents/Approvals/Reports/Settings | لا top-level routes لهذه الأسطح؛ `/projects` نفسه مفقود. |
| roadmap R10 safe scope يوحي secure investor login/read model framework | لا investor login/self-scope؛ الصفحة الحالية لأعضاء المنظمة فقط. |
| roadmap R12 “complete” يذكر observability/export/production config | لا observability أو export UI أو proof لبيئة production. الصحيح: database hardening قوي، real-world operations غير مثبتة. |
| `docs/demo/REAL_ESTATE_SHOWCASE.md` يقول seed idempotent/re-runnable | policy-safety migration الحالية توقف S5/contribution posting بدون policy authority. |
| `.env.production` tracked بينما الإرشادات تقول secrets لا تدخل Git | الملف يحتوي فقط names عامة من نوع URL/publishable key حسب الفحص، ولم نعرض القيم؛ لكنه يربط build افتراضيًا ببيئة محددة ويضعف فصل البيئات. |

## 8. TODO/dead/duplicated systems

لا توجد TODO/FIXME كثيرة داخل production code، لكن توجد علامات تراكم تقني:

- `src/features/{finance,close,real-estate,revenue,agriculture}/command-actions.ts` wrappers فوق `actions.ts`، مع انتقال غير موحد؛ بعض forms تستخدم القديم وبعضها الجديد.
- `src/app/(app)/projects/[projectId]/investors/forms.tsx` و`src/features/allocation/*` تحتفظ بواجهة/أوامر S5 لكن الصفحة الحالية لا تستورد forms. DB هي التي تقفلها أيضًا.
- `src/shared/supabase/browser.ts` لا يوجد له importer حالي.
- dependencies بلا direct import في source/tests: `tailwindcss`, `@testing-library/user-event`, و`@supabase/supabase-js` كاعتماد مباشر؛ قد يكون الأخير مطلوبًا transitively من Supabase SSR، لكن لا يستخدم مباشرة.
- `close/schema.ts` يحتوي `_moneyGuard` غير مستخدم وظيفيًا فقط لإبقاء import reachable.
- migration timestamp رقمي `20260814001200` مستخدم لملفين مختلفين. runner الداخلي يرتب full filenames ويتعامل معهما، لكن أدوات Supabase التقليدية التي تفترض version prefix فريد قد تتعارض.
- status reports/history documents كثيرة ومتراكبة، ما يجعل معرفة “الحالة الحالية” صعبة.

## 9. unknowns لا يمكن حسمها من المستودع

1. هل `terranex.vercel.app` هو production فعلي، وما commit المنشور؟
2. هل Supabase المشار إليه في ملفات البيئة production/staging/demo، وهل كل 97 migrations مطبقة عليه؟
3. هل synthetic demo الحالي ما زال موجودًا ويعمل بعد policy-safety changes؟
4. من يملك تشغيل Vercel/Supabase، التنبيهات، النسخ الاحتياطية، الحوادث، والدعم؟
5. ما RPO/RTO والاحتفاظ الفعلي للنسخ الاحتياطية؟
6. أداء queries/views على بيانات حقيقية كبيرة.
7. سلوك الواجهة authenticated في المتصفحات والأجهزة وقارئات الشاشة.
8. قرارات `BD-001`…`BD-012` القانونية والاقتصادية.
9. اعتماد محاسب/محامٍ للمعالجات والضرائب/IFRS/العقود.
10. وجود عميل حقيقي، paid pilot، four-week reconciliation، UAT، أو buyer acceptance. المستودع نفسه ينفي اكتمالها.
11. إعداد SonarCloud/Vercel الخارجي؛ ملفات config وحدها لا تثبت quality gate أو deploy policy.

## 10. تقييم المخاطر

| المستوى | الخطر |
|---|---|
| حرج قبل investor work | R15 يجب أن يبقى مقفولًا حتى توثيق كل قرارات المالك والأدلة؛ لا يجوز تخطي `r15:admission`. |
| عالٍ قبل استخدام close عملي | S6 response-loss replay defect في 5 أوامر؛ PR #164 غير مدمج في النسخة الحالية. |
| عالٍ قبل pilot | لا يوجد proof لبيئة live، backup schedule، restore، monitoring، support ownership، أو authenticated E2E/UAT. |
| عالٍ في الصلاحيات | نموذج `OWNER/MEMBER` واسع؛ لا يطابق أدوار finance/operator/reviewer/investor المقترحة. |
| متوسط | broken `/projects` links وغياب Organization switcher. |
| متوسط | docs status متضاربة وقد تقود لقرارات خاطئة. |
| متوسط | tracked `.env.production` قد يجعل developer build يتصل ببيئة غير مقصودة. |
| متوسط عند توسعة العملات | unknown currencies تفترض 2 decimals. |
| متوسط تشغيلي | لا observability/health/alerts أو post-deploy smoke. |
| منخفض/صيانة | action wrappers/dead UI/dependencies وتكرار status docs. |

## 11. ما لا يجب ادعاؤه

- لا نقول إن النظام production-ready بسبب نجاح CI فقط.
- لا نقول إن backup rehearsal = production restore.
- لا نقول إن synthetic R13 = customer UAT.
- لا نقول إن contribution = ownership أو entitlement.
- لا نقول إن tax registry = tax compliance.
- لا نقول إن responsive CSS = WCAG/mobile acceptance.

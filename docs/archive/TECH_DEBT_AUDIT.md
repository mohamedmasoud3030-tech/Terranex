# تدقيق الديون التقنية والاعتمادات — Terranex

**تاريخ الفحص:** 2026-08-17  
**الفرع / نقطة الفحص:** `arena/01a00fc0-terranex` عند `a531d64e870c1e0aeaed806c5e0a2482e6d20362`  
**نوع العمل:** مراجعة read-only. هذا الملف هو التغيير الوحيد المقصود. لم تُحدّث package، ولم يتغير `package-lock.json` أو runtime أو config أو source أو database.

---

## 1. الخلاصة للمالك

الوضع ليس مشروعًا يحتاج «تحديث كل شيء» أو إعادة كتابة. الأساس الحالي جيد: `npm audit` لم يجد advisory معروفة، شجرة npm بلا peer conflict، Next.js 16 ما زال Active LTS، PostgreSQL 16 مدعوم، لا توجد circular imports، ولا توجد `TODO/FIXME` أو type/lint suppressions في production source.

لكن توجد أولويات صيانة واضحة:

1. **مؤكد وعاجل نسبيًا:** CI ما زال يعمل على Node 20، وهو End-of-Life منذ 2026-04-30. كما أن `engines.node >=20.9.0` ما زال يسمح به.
2. **مؤكد:** ESLint 9 أصبح End-of-Life في 2026-08-06. هذا خطر دعم لأداة الفحص، وليس ثغرة runtime مثبتة.
3. **موثوقية:** types هي `@types/node@26` بينما CI هو Node 20 وبيئة الفحص Node 22؛ هذا قد يسمح باستعمال API غير موجودة في runtime الحقيقي.
4. **أثر مستخدم قابل للقياس:** بعض Client Components تستورد constants من ملفات Zod، فدخل Zod كاملًا في ستة مسارات. chunk واحدة حجمها نحو **64 KB gzip**.
5. **اختبارات:** 38 من 52 ملف Vitest تقرأ نصوص source/migrations، ولا يوجد browser E2E. PostgreSQL tests قوية، لكن رحلة auth/navigation/form الحقيقية لا تُختبر من طرف إلى طرف.
6. **قابلية النمو:** أغلب read queries بلا pagination؛ صفحة Agriculture ترسل 26 read request متوازيًا وصفحة Livestock ترسل 22. هذا مقبول في pilot صغير، لكنه خطر تكلفة/زمن عند نمو البيانات.
7. **سرعة التسليم:** توجد modules كبيرة جدًا، وتكرار في validation/error mapping، ووثائق تاريخية تخالف التنفيذ الحالي.

**القرار المقترح:** لا نبدأ major-upgrade جماعيًا. نبدأ بعد الموافقة بحزمة صغيرة: Node 24 LTS + types مطابقة + ESLint 10 + patch متطابقة لـNext/`eslint-config-next`. ثم نفصل تحديثات Supabase وVitest/Jsdom وTypeScript في مراحل مستقلة لها tests وrollback واضحان.

---

## 2. ما تم فحصه وكيف

### 2.1 نطاق المستودع

- `package.json`, `package-lock.json`, npm tree، scripts، engines، peer dependencies، install hooks، deprecations، updates.
- Next/React/Supabase/Zod وTypeScript/ESLint/Vitest/jsdom/Tailwind.
- `.github/workflows/*`, `next.config.ts`, `tsconfig.json`, `eslint.config.mjs`, `vitest.config.ts`, Sonar config.
- كل `src/app`, `src/features`, `src/shared`, وعددها 159 ملف TS/TSX في فحص dependency graph.
- 97 migration، 52 ملف Vitest، و106 ملفات تحت `supabase/tests`.
- TODO/FIXME، disabled tests/checks، suppressions، dead candidates، generated/vendor files، oversized modules، duplication، boundaries، docs drift.

### 2.2 تشخيصات نُفذت بلا تعديل

| الفحص | النتيجة |
|---|---|
| `node --version` / `npm --version` | محليًا Node `22.22.3` وnpm `10.9.8`. |
| lockfile parse | lockfile v3؛ 594 package entries بعد root. |
| `npm ls --all --json` | لا peer/version conflict. ظهر فقط packageان optional/orphan كـ`extraneous`: `@emnapi/runtime@1.11.3` و`@img/sharp-wasm32@0.35.3`. |
| `npm audit --json` | **0** info/low/moderate/high/critical؛ 594 dependency classifications. هذه نتيجة registry الحالية وليست ضمانًا أبديًا. |
| `npm outdated --json` | updates متاحة؛ جرى التعامل معها كإشارات لا كعيوب تلقائية. |
| lock deprecation scan | transitive واحدة deprecated: `whatwg-encoding@3.1.1`، dev-only عبر `jsdom@26.1.0`. |
| lifecycle scan | لا root `preinstall/install/postinstall/prepare`. الموجود فعليًا: `esbuild` و`unrs-resolver` postinstall؛ كلاهما dev transitive ومثبت integrity في lock. |
| `madge --circular ... src` | 159 ملفًا؛ **لا circular dependency**. |
| `knip` diagnostic | 5 file candidates، 2 devDependency candidates، 42 exported-value و147 exported-type signals. النتائج تحتاج تحقق؛ ليست أمر حذف. |
| build bundle stats | 31 route entry في stats؛ Zod chunk `283,405` bytes raw / `64,055` gzip. |
| TODO/suppressions scan | لا production TODO/FIXME، لا `@ts-ignore`, `eslint-disable`, skipped/focused tests. |
| tracked generated/vendor scan | لا `dist/build/.next/node_modules/vendor`, minified files، sourcemaps، أو tracked file أكبر من 500 KB. |
| local Markdown links | 76 local links؛ **0 broken**. |
| npm registry signature audit | **غير محسوم**: `npm audit signatures` فشل بسبب `ECONNRESET` إلى Sigstore TUF، لا بسبب signature سيئة مثبتة. |

### 2.3 حدود هذا الفحص

- لم يُشغل أي shared/production Supabase أو migration أو seed.
- PostgreSQL غير متوفر محليًا هنا؛ database CI على نفس commit نجح سابقًا.
- لم تُقَس Core Web Vitals من مستخدم حقيقي، ولا latency حقيقية من Supabase. أرقام bundle/query fan-out أدلة تقنية، أما أثر الشبكة النهائي فيحتاج قياسًا.
- official support status موثق أدناه، لكن update متاحة وحدها لا تعني وجود defect.

---

## 3. ترتيب سجل الديون

المقياس من 1 إلى 5:

- **Risk Reduction:** 5 يعني أن الإصلاح يخفض خطرًا مهمًا ومؤكدًا.
- **User Value:** 5 يعني أثرًا مباشرًا واضحًا على المستخدم/استمرارية الخدمة.
- **Effort:** 1 صغير، 5 كبير. الجهد العالي يخفض أولوية التنفيذ ما لم يكن الخطر عاليًا.

| الترتيب | ID | الفئة | الحالة | Risk Reduction | User Value | Effort | القرار المختصر |
|---:|---|---|---|---:|---:|---:|---|
| 1 | TD-01 | Security/Support | خطر دعم مؤكد | 5 | 5 | 2 | انقل CI/runtime contract إلى Node 24 LTS patched. |
| 2 | TD-05 | Correctness | mismatch مؤكد؛ defect محتمل | 4 | 3 | 1 | طابق `@types/node` مع Node المختار. |
| 3 | TD-02 | Security/Support | خطر دعم مؤكد | 4 | 2 | 2 | ESLint 10 في PR مستقل بعد Node. |
| 4 | TD-13 | Performance/Cost | تكلفة bundle مؤكدة | 3 | 4 | 2 | افصل UI constants عن Zod schemas. |
| 5 | TD-03 | Security/Support | فجوة كشف مؤكدة | 4 | 3 | 2 | advisory/update automation بلا auto-merge. |
| 6 | TD-06 | Correctness | فجوة verification مؤكدة | 4 | 4 | 4 | أضف E2E صغيرًا للرحلات الحرجة، لا coverage شكليًا. |
| 7 | TD-14 | Performance/Cost | خطر نمو محتمل قوي | 3 | 4 | 4 | قِس ثم paginate/جمّع أبطأ read models فقط. |
| 8 | TD-07 | Correctness | drift محتمل | 3 | 3 | 3 | وحّد primitives المشتركة تدريجيًا مع characterization tests. |
| 9 | TD-11 | Delivery Speed | reproducibility debt مؤكد | 3 | 2 | 2 | ثبّت Node/npm contract مع lockfile. |
| 10 | TD-08 | Correctness/Delivery | compatibility risk محتمل | 3 | 2 | 3 | لا تعدّل history؛ وثّق duplicate migration version واختبر CLI. |
| 11 | TD-09 | Delivery Speed | maintainability debt مؤكد | 2 | 2 | 4 | قسّم modules عند التغيير فقط، لا refactor شامل. |
| 12 | TD-04 | Security Hardening | توصية، لا compromise مثبت | 3 | 1 | 1 | pin GitHub Actions إلى verified SHAs وأضف least permissions. |
| 13 | TD-12 | Delivery Speed | docs contradiction مؤكد | 2 | 2 | 2 | صحح docs authoritative فقط في PR docs. |
| 14 | TD-10 | Delivery Speed | unused/dormant signals | 1 | 1 | 2 | تحقق ثم أزل فقط ما لا تحميه سياسة أو operator flow. |
| 15 | TD-15 | Cosmetic/Low value | cleanup منخفض القيمة | 1 | 1 | 1 | لا تعمل dedupe/lock churn وحده الآن. |

---

## 4. مخاطر الأمن والدعم المؤكدة

### TD-01 — Node 20 في CI أصبح End-of-Life

- **الدليل:** `.github/workflows/greenfield-ci.yml:19` يستخدم `node-version: 20`. `package.json` وlock root يسمحان `node >=20.9.0`. صفحة Node الرسمية تسجل v20 كـEOL؛ الموعد المخطط كان 2026-04-30. Node 24 دخل LTS ويستمر تحديثه حتى نهاية أبريل 2028.
- **الأثر الفعلي:** CI يثبت ويختبر على runtime لم يعد يحصل على إصلاحات Node الرسمية. كما أن engine contract يسمح بنشر/تشغيل Node 20. runtime الحقيقي لدى Vercel غير مثبت داخل repo، لذلك لا أدعي أنه يعمل حاليًا على 20؛ المؤكد هو CI والـcontract.
- **الاحتمال:** عالٍ بمرور الوقت؛ أي CVE/bug جديد في Node لن يُصلح في v20. لا توجد هنا exploit مثبتة ضد Terranex.
- **أصغر إصلاح:** اختيار patched Node 24 LTS واحد، تحديث CI و`engines` وملف version (`.nvmrc` أو `.node-version`) معًا. لا نحتاج تغيير framework.
- **خطر dependency/migration:** متوسط؛ Node 20→24 major jump، لكن app يستعمل Node APIs بسيطة. لا database migration. يلزم فحص native/optional packages وSupabase/Next behavior.
- **اختبارات قبل الدمج:** fresh `npm ci`; lint; typecheck; 714 Vitest tests؛ production build؛ PostgreSQL CI؛ smoke start/login/anonymous redirect؛ مراجعة install hooks.
- **Rollback:** revert commit وإعادة CI إلى آخر Node 22 patched لفترة قصيرة، لا العودة إلى Node 20 كحل دائم. lockfile لا يتغير إلا إذا جرى اختيار npm جديد صراحة.
- **هل التأجيل معقول؟** أيام قليلة لترتيب PR معقول؛ تأجيل دورة كاملة أو pilot جديد غير معقول.

### TD-02 — ESLint 9 خارج الدعم الرسمي

- **الدليل:** installed `eslint@9.39.5`. صفحة ESLint الرسمية تقول إن v9 وصل EOL في 2026-08-06؛ الحالي `eslint@10.8.1`. `eslint-config-next@16.3.1` يقبل `eslint >=9.0.0` بحسب npm metadata.
- **الأثر الفعلي:** lint ما زال ينجح، ولا ثغرة مثبتة. لكن v9 لن يتلقى bug/security/compatibility fixes جديدة.
- **الاحتمال:** متوسط؛ الخطر يظهر مع Node/editor/plugin updates أو advisory مستقبلية، وليس كتعطل حالي.
- **أصغر إصلاح:** بعد Node 24، تحديث ESLint وحده إلى v10 مع patch متطابقة من `eslint-config-next`, ومراجعة migration guide. config الحالي Flat Config صغير ولا يستعمل legacy `.eslintrc`.
- **خطر dependency/migration:** منخفض إلى متوسط؛ ESLint 10 يزيل APIs/flags قديمة، لكن repo لا يعرّف custom rules. لا DB migration ولا runtime change.
- **اختبارات قبل الدمج:** `npm ci`, `npm run lint`, `npm run typecheck`, tests/build؛ مقارنة عدد الملفات والقواعد المفحوصة قبل/بعد وعدم إخفاء warnings.
- **Rollback:** revert `package.json` وlockfile معًا إلى آخر commit؛ لا rollback بيانات.
- **هل التأجيل معقول؟** تأجيل قصير حتى اكتمال Node PR معقول؛ إبقاؤه عدة أشهر غير مفضل.

### TD-03 — لا gate آلية للـadvisories أو dependency updates

- **الدليل:** CI يشغل `npm ci --no-audit --no-fund` ثم lint/test/build/typecheck. لا `.github/dependabot.yml`, Renovate, OSV, Snyk أو `npm audit` step. يوجد audit يدوي موثق فقط. نتيجة اليوم 0 advisories.
- **الأثر الفعلي:** لا خطر معروف اليوم، لكن ظهور advisory جديدة لا يفشل PR ولا ينشئ update proposal تلقائيًا؛ وقت الاكتشاف يعتمد على فحص بشري.
- **الاحتمال:** متوسط/عالٍ مع الزمن لأي web dependency tree.
- **أصغر إصلاح:** Dependabot أسبوعي محدود لـnpm وGitHub Actions، وCI check لـ`npm audit --omit=dev --audit-level=high` مع full audit كreport. لا auto-merge ولا upgrade جماعي.
- **خطر dependency/migration:** منخفض. خطر false positive/registry outage موجود؛ اجعل production-high gate blocking، والباقي visible لا يكسر التسليم بلا triage.
- **اختبارات قبل الدمج:** افتح أول update PR تجريبي، تأكد أن lockfile فقط يتغير وأن full app/DB gates مطلوبة.
- **Rollback:** تعطيل schedule أو تحويل audit إلى non-blocking مؤقتًا مع issue موثق؛ لا أثر بيانات.
- **هل التأجيل معقول؟** معقول حتى Node/ESLint PR، لكنه quick win قبل pilot عام.

### TD-04 — GitHub Actions مربوطة tags لا immutable SHAs

- **الدليل:** `actions/checkout@v7` و`actions/setup-node@v7` في workflows. `pilot-activation.yml` يحدد `permissions: contents: read` جيدًا، لكن `greenfield-ci.yml` لا يحدد permissions صراحة. GitHub يوضح أن full commit SHA هي الطريقة الوحيدة لجعل action release immutable.
- **الأثر الفعلي:** لا compromise معروف، والـactions first-party. لكن mutable tag يزيد supply-chain trust، وdefault token permissions في app CI تعتمد على repository/org setting غير الموجود في source.
- **الاحتمال:** منخفض، والأثر المحتمل عالٍ إذا حدث compromise upstream.
- **أصغر إصلاح:** pin كل action إلى verified full SHA مع تعليق tag، وأضف top-level `permissions: contents: read` للـCI. فعّل Dependabot لـ`github-actions` لتحديث SHAs.
- **خطر dependency/migration:** منخفض؛ لا runtime أو DB migration. يجب التحقق أن SHA من repository الأصلي.
- **اختبارات قبل الدمج:** workflow dispatch/PR تجريبي؛ App وDatabase jobs يمران؛ pilot workflow inspection-only فقط، بلا apply.
- **Rollback:** revert workflow commit إلى tag السابق مؤقتًا.
- **هل التأجيل معقول؟** نعم؛ hardening منخفض الجهد، لكنه ليس مانع release وحده.

---

## 5. ديون الصحة والموثوقية

### TD-05 — `@types/node@26` لا يطابق runtime الذي يُختبر

- **الدليل:** installed/direct `@types/node@26.2.0`; CI Node 20؛ البيئة المحلية Node 22. app يستخدم `node:crypto`، والاختبارات/scripts تستخدم `fs/path/child_process/os/url`.
- **الأثر الفعلي:** typecheck قد يسمح API أو signature متاحة في Node 26 وغير متاحة في Node 20/22/24. لم يُشاهد استعمال API غير متوافق حاليًا، لذلك mismatch مؤكد والـdefect غير مثبت.
- **الاحتمال:** متوسط كلما أضيف كود Node جديد.
- **أصغر إصلاح:** بعد قرار TD-01، ثبت `@types/node` على major المطابقة لـNode 24، ولا تستخدم latest Current Node types تلقائيًا.
- **خطر dependency/migration:** منخفض؛ قد تظهر type errors تكشف اعتمادًا خفيًا. لا DB migration.
- **اختبارات قبل الدمج:** typecheck على Node 24، lint/test/build، وتشغيل scripts الأساسية.
- **Rollback:** revert types فقط إذا كان runtime ما زال مثبتًا ومتوافقًا؛ لا تخفِ errors بـ`skipLibCheck` إضافي.
- **هل التأجيل معقول؟** فقط ليُدمج مع Node PR؛ لا يفضل ترك mismatch بعده.

### TD-06 — الاختبارات قوية في DB لكنها تعتمد كثيرًا على نص المصدر ولا يوجد E2E

- **الدليل:** 52 ملف Vitest / 714 test ناجحة في آخر full gate. 38 ملفًا تستعمل `readFileSync/readdirSync` لفحص source/migration text، 8 فقط تستعمل `@testing-library/react`, و9 تستخدم jsdom directive. لا Playwright/Cypress/E2E config. PostgreSQL suite مستقلة وكبيرة، وهذا تعويض مهم لكنه لا يختبر browser journey.
- **الأثر الفعلي:** contract tests تحمي وجود guards وpolicy boundaries، لكنها قد تنجح مع behavior خاطئ أو تفشل عند refactor آمن. لا proof آلي كامل لـlogin/session refresh/navigation/form submit/error/retry في browser.
- **الاحتمال:** متوسط إلى عالٍ عند dependency upgrades أو تقسيم modules.
- **أصغر إصلاح:** لا تحذف contract tests. أضف 3–5 E2E journeys فقط: anonymous redirect/login، create/open project، command retry/idempotency، authorization denial، ومسار sector حرج. استخدم test Supabase/PostgreSQL مع fixtures غير حقيقية. لا تضع coverage percentage اعتباطية.
- **خطر dependency/migration:** متوسط؛ E2E يحتاج test environment وAuth fixture. ممنوع توصيله بproduction أو تخزين secrets.
- **اختبارات قبل الدمج:** E2E نفسه + unit + DB gate؛ ثبت data reset/tenant isolation. قبل تحديث Supabase SSR يجب أن يوجد auth/session E2E.
- **Rollback:** إزالة E2E workflow/config فقط؛ لا تغيير runtime. احتفظ بالtests المفيدة حتى تثبت البدائل.
- **هل التأجيل معقول؟** للـpilot الداخلي القصير نعم؛ قبل auth/framework major أو public release لا.

### TD-07 — تكرار validation وdomain-error mapping قابل للانحراف

- **الدليل:** `idempotencyKey` معرف محليًا في 14 schema files، و`uuid` في 12، و`domainError` في 11 action files. الرسائل والشروط (`forbidden`, `authentication required`, payload mismatch) متشابهة لكن ليست متطابقة. توجد أيضًا optional date/text/decimal preprocessors متعددة.
- **الأثر الفعلي:** إصلاح قاعدة مشتركة قد يصل إلى feature ويُنسى آخر. لا يوجد الآن proof أن القيم المختلفة كلها bugs؛ بعضها domain-specific ومقصود.
- **الاحتمال:** متوسط، خاصة في idempotency/auth errors والحدود المالية.
- **أصغر إصلاح:** استخرج فقط primitives المتطابقة فعليًا: UUID/idempotency schemas وcommon auth/idempotency error translator. اترك domain errors الخاصة داخل feature. نفذ feature واحدة في كل مرة.
- **خطر dependency/migration:** متوسط؛ توحيد زائد قد يمحو معنى domain مختلف أو يغير Arabic messages. لا DB migration ما لم تتغير contract، وهذا غير مطلوب.
- **اختبارات قبل الدمج:** characterization tests لكل schema/error branch الحالي؛ unit + form interaction + DB error-contract tests.
- **Rollback:** revert feature-by-feature؛ لا big-bang adapter.
- **هل التأجيل معقول؟** نعم حتى يلمس العمل نفس المناطق؛ لا يستحق refactor مستقل شامل.

### TD-08 — migration history طويلة، function redefinitions كثيرة، وversion prefix مكرر

- **الدليل:** 97 migration. scan وجد 439 `CREATE OR REPLACE FUNCTION` definitions تخص 379 اسمًا؛ 42 اسم function أُعيد تعريفه عبر history، وهذا متوقع جزئيًا مع forward-only fixes. لكن prefix `20260814001200` موجود في ملفين: `..._agriculture_input_application.sql` و`..._gf015_manufacture_date_guard.sql`. custom runner يرتب full filenames وCI replay ناجح.
- **الأثر الفعلي:** clean replay يعمل. الخطر هو استخدام tool يفترض uniqueness للـtimestamp version مثل standard migration ledger؛ قد يرفض/يتجاوز أحد الملفين. كثرة redefinitions تزيد وقت فهم authoritative final function.
- **الاحتمال:** منخفض في runner الحالي، متوسط عند تبني Supabase CLI قياسي أو incident repair يدوي.
- **أصغر إصلاح:** **لا تعِد تسمية applied migration ولا تعدلها الآن.** أولًا نفذ dry-run/ledger inspection على disposable database باستخدام CLI المقصود، ووثّق أن custom activation هي authority. عالج compatibility بخطة baseline/forward mechanism مع backup، لا history rewrite عشوائي.
- **خطر dependency/migration:** عالٍ إذا عولج خطأ؛ rename قد يسبب duplicate apply أو ledger drift. لا إجراء production بلا موافقة ونسخة احتياطية.
- **اختبارات قبل الدمج:** empty replay، forward upgrade، Supabase CLI dry-run على disposable project، مقارنة checksums/ledger، كامل 106 DB fixtures.
- **Rollback:** لأن migrations forward-only، rollback هو استعادة disposable test أو revert docs/tooling قبل production؛ لا يوجد down migration آمن تلقائيًا.
- **هل التأجيل معقول؟** نعم مع custom runner الموثق وCI الأخضر؛ يجب حسمه قبل تغيير deployment tooling.

---

## 6. ديون سرعة التسليم والحدود

### TD-09 — modules كبيرة جدًا تزيد تكلفة التغيير

- **الدليل:** `agriculture/forms.tsx` 1,495 سطرًا/نحو 125 function-or-arrow، `livestock/forms.tsx` 1,386، Agriculture page 1,200، Livestock page 876، `intake/readiness.ts` 778، Intake page 768، Agriculture queries 683/actions 651. لا circular imports، وfeature-to-feature runtime coupling منخفض؛ معظم cross-feature imports الظاهرة هي type `ActionState` من auth.
- **الأثر الفعلي:** review أصعب، merge conflicts واحتمال لمس form غير مقصود أعلى، وtests النصية تربط التقسيم بأسماء/مسارات حالية. الحجم وحده ليس correctness bug.
- **الاحتمال:** عالٍ كتكلفة delivery، متوسط كسبب defect.
- **أصغر إصلاح:** عند إضافة feature جديدة فقط، انقل subsection واحدًا مع tests إلى module باسم domain واضح. shared form shell فقط إذا ثبت تطابق behavior. lazy-load section إذا كان الهدف bundle، لأن تقسيم الملف وحده لا يقلل bytes تلقائيًا.
- **خطر dependency/migration:** متوسط؛ Server Action references وsource-contract tests قد تتأثر. لا DB migration.
- **اختبارات قبل الدمج:** interaction tests لكل forms المنقولة، build/server action manifest، idempotency tests، route smoke.
- **Rollback:** revert subsection commit؛ أبقِ exports compatibility مؤقتًا إن لزم.
- **هل التأجيل معقول؟** نعم؛ لا ننفذ style-only split. عالجه opportunistically أو مع TD-13.

### TD-10 — dead/unused signals موجودة لكن بعضها مقصود أو تشغيلي

- **الدليل:** Knip أشار إلى 5 files: `scripts/demo/provision_presentation_user.mjs`, `features/allocation/{actions,queries}.ts`, `shared/supabase/browser.ts`, و`investors/forms.tsx`. كما أشار إلى `@testing-library/user-event` و`tailwindcss`. لكن:
  - provision script مستخدم في `PROJECT_COMMANDS.md` و`docs/demo/PRESENTATION_ACCESS.md`.
  - Allocation/investors code policy-inert عمدًا وتحميه `tests/r10-policy-block.test.ts` ووثائق R14.
  - browser client لا importer له، لكن runbook يشير إليه وقد يكون future auth boundary.
  - Tailwind لا config/directives/classes له؛ CSS الحالي يدوي.
  - user-event لا import له.
- **الأثر الفعلي:** install/cognitive surface زائد قليلًا. الحذف غير المدروس قد يكسر operator flow أو policy evidence.
- **الاحتمال:** عالٍ أن Tailwind/user-event غير مستخدمين؛ منخفض أن كل file candidates قابلة للحذف الآن.
- **أصغر إصلاح:** بعد الموافقة: remove devDependency واحدة في كل PR مع clean install/tests/build. صنّف provision script كoperator entry بدل حذفه. لا تحذف S5 dormant code قبل owner policy decision. قرر browser client بعد auth E2E/roadmap.
- **خطر dependency/migration:** منخفض للحزمتين؛ عالٍ سياسيًا/وظيفيًا لـS5؛ لا DB migration لمجرد cleanup.
- **اختبارات قبل الدمج:** fresh `npm ci`; all app/DB gates؛ policy-block tests؛ demo docs command check؛ bundle diff.
- **Rollback:** restore package/file وlock من commit السابق؛ لا data change.
- **هل التأجيل معقول؟** نعم، وقيمته أقل من support/bundle work.

### TD-11 — Node/npm contract غير قابل للتكرار بالكامل

- **الدليل:** `package.json` لا يحتوي `packageManager` أو Volta، ولا `.nvmrc/.node-version/.npmrc` لتثبيت toolchain. engine واسع `>=20.9.0`. lockfile يجعل package resolution حتميًا مع `npm ci`، لكنه لا يثبت npm behavior/version.
- **الأثر الفعلي:** local وCI قد يستخدمان npm majors مختلفة؛ lockfile v3 متوافق الآن لكن warnings/optional install/layout قد تختلف. ظهور optional orphan packages يوضح أن platform/tool behavior يحتاج ضبطًا.
- **الاحتمال:** متوسط عند نقل CI إلى Node 24 أو onboarding developer جديد.
- **أصغر إصلاح:** مع TD-01 اختر Node 24 patch policy وnpm major/minor معتمدًا، أضف `packageManager` وversion file، ووثّق update cadence. لا تضف package manager جديدًا.
- **خطر dependency/migration:** منخفض إلى متوسط؛ Node 24 يأتي عادةً مع npm مختلف، وقد ينتج lock diff. لا تقبل lock churn قبل تفسيره.
- **اختبارات قبل الدمج:** clean clone + chosen npm + `npm ci`; hash/status clean؛ full gates على Linux؛ optional package review.
- **Rollback:** revert metadata/toolchain commit وlock معًا.
- **هل التأجيل معقول؟** ادمجه مع Node؛ PR مستقل بعده يكرر الجهد بلا فائدة.

### TD-12 — وثائق تاريخية تخالف التنفيذ الحالي

- **الدليل:** `README.md:9,15` يقول إن procurement pricing/invoicing/payment وR4 خطوات تالية رغم تنفيذها. `FINAL_DELIVERY_REPORT.md:34-45,123-127` يقول إن budget/roll-up/FX/executive home لم تبدأ أو جزئية، بينما migrations/pages/docs الأحدث نفذتها. `PROJECT_STATUS.md:180-190` يسجل هذه التناقضات بوضوح. في المقابل local Markdown links كلها سليمة.
- **الأثر الفعلي:** owner/developer قد يخطط لعمل منجز أو يثق بتقرير تسليم قديم بدل current source. لا runtime defect.
- **الاحتمال:** عالٍ للالتباس؛ منخفض للأثر التقني المباشر.
- **أصغر إصلاح:** حدد document واحدة current index، أضف banner «historical snapshot» للتقارير القديمة، وصحح README current/next فقط. لا تعِد كتابة 96 doc دفعة واحدة.
- **خطر dependency/migration:** منخفض؛ docs-only. الخطر هو تغيير policy wording، لذلك راجع AGENTS/roadmap authority.
- **اختبارات قبل الدمج:** local link checker، grep للphase contradictions، owner review للstatus wording.
- **Rollback:** revert docs commit.
- **هل التأجيل معقول؟** نعم بعد support fixes، لكن قبل handoff/pilot خارجي يجب تصحيحه.

---

## 7. ديون الأداء والتكلفة

### TD-13 — Zod موجود في client bundles بسبب خلط constants مع schemas

- **الدليل:** build أنتج chunk `.next/static/chunks/3szwarg70504l.js` بحجم `283,405` raw و`64,055` gzip، وفيه مئات إشارات Zod. يظهر في أول load لستة مسارات: Intake (`220,502` gzip total)، Agriculture (`217,687`)، Livestock (`214,736`)، Livestock Operations (`209,564`)، Pilot (`207,789`)، وNew Project (`203,233`). baseline login نحو `134,540` gzip. مثال مباشر: `project-form.tsx` Client Component يستورد `SECTORS` من `features/projects/schema.ts` الذي يستورد Zod؛ Agriculture/Livestock/Pilot لها pattern مشابه.
- **الأثر الفعلي:** نحو 64 KB gzip إضافية تُحمّل أول مرة في هذه المجموعة، ثم تستفيد من browser cache. زمن المستخدم الحقيقي غير مقاس، لكن bytes مؤكدة.
- **الاحتمال:** عالٍ لكل مستخدم يفتح أحد المسارات على cold cache.
- **أصغر إصلاح:** انقل constants/labels/types التي يحتاجها client إلى module بلا import لـZod، واترك validation schemas في server-only modules. لا تستبدل Zod.
- **خطر dependency/migration:** منخفض إلى متوسط؛ يجب إبقاء enum values/types متطابقة وعدم كسر Server Actions. لا DB migration.
- **اختبارات قبل الدمج:** unit/schema tests، form rendering، build، مقارنة `route-bundle-stats.json` والتأكد من غياب Zod chunk من routes، smoke submit.
- **Rollback:** revert module split؛ لا data impact.
- **هل التأجيل معقول؟** قصيرًا نعم؛ هذا أفضل performance quick win بعد support baseline لأنه measurable ولا يحتاج architecture replacement.

### TD-14 — reads غير محدودة وroute fan-out كبير

- **الدليل:** في `src/features` توجد 58 `.order(...)` sites، ووجد الفحص `.limit(200)` واحدة فقط. كثير من histories/lists ترجع كل الصفوف بلا `.range/.limit`. Agriculture page تنفذ 26 `get*` calls داخل `Promise.all`، Livestock 22، Intake 25. التوازي يمنع waterfall لكنه لا يقلل عدد network/DB requests أو حجم rows.
- **الأثر الفعلي:** على dataset الحالي غير معروف. مع نمو events/journals/inventory، server render يقرأ تاريخًا كاملًا، يزيد Supabase/PostgREST requests والذاكرة والlatency والتكلفة.
- **الاحتمال:** منخفض في demo صغير، عالٍ عند pilot طويل أو customer data متراكمة.
- **أصغر إصلاح:** لا تجمع كل شيء في RPC ضخم الآن. أضف observability/query timing، ثم paginate أكبر timelines والجداول فقط، وادمج read model واحدًا إذا أثبت القياس أنه hot. احتفظ بالtotals في views مخصصة لا بتحميل كل rows.
- **خطر dependency/migration:** متوسط إلى عالٍ؛ pagination قد تغير UX/totals وas-of semantics. read-model SQL جديد يحتاج forward migration وموافقة.
- **اختبارات قبل الدمج:** fixtures كبيرة، as-of/tenant tests، page behavior، query count/row count/latency baseline، PostgreSQL gate، عدم تغيير financial totals.
- **Rollback:** feature flag أو revert UI/query change؛ إن أضيف view forward-only يمكن تركه غير مستخدم بدل down migration.
- **هل التأجيل معقول؟** نعم للpilot الصغير مع قياس؛ لا تنتظر حتى ظهور timeout في production.

---

## 8. تنظيف شكلي قليل القيمة الآن

### TD-15 — duplicates/deprecation/orphan optional packages لا تبرر churn منفردًا

- **الدليل:** lock يحتوي 20 أسماء package بأكثر من version، معظمها toolchain constraints طبيعية (`semver`, `minimatch`, `debug`, إلخ). deprecated الوحيدة `whatwg-encoding@3.1.1` dev-only عبر jsdom. `@img/sharp-wasm32@0.35.3` و`@emnapi/runtime@1.11.3` optional lock entries بلا parent edge حالي، لذلك `npm ls` يسميهما extraneous؛ Next→Sharp ما زال يملك platform optionals أخرى. لا advisories ولا peer conflict.
- **الأثر الفعلي:** install noise ومساحة بسيطة؛ لا runtime bug مثبت. package duplication وحدها ليست defect.
- **الاحتمال:** منخفض لأثر المستخدم، متوسط لاستمرار warning/confusion.
- **أصغر إصلاح:** لا تشغل dedupe كهدف. بعد Node/Vitest/jsdom decisions، أنشئ lockfile بالـnpm المثبت، افحص diff، وتأكد أن orphan entries/deprecation اختفت. إن بقيت، افتح issue محدد.
- **خطر dependency/migration:** منخفض وظيفيًا لكن lock churn قد يغير مئات transitives بلا قيمة. لا DB migration.
- **اختبارات قبل الدمج:** `npm ci`, `npm ls --all`, audit, lint/test/build، optional image path smoke إن استُعمل Next Image.
- **Rollback:** revert lockfile كاملًا، لا تعدّل entries يدويًا.
- **هل التأجيل معقول؟** نعم جدًا؛ cosmetic cleanup ليس أولوية.

---

## 9. packages والأدوات: ماذا نحدث الآن وماذا نؤجل

### 9.1 تحديث الآن — حزمة صغيرة بعد الموافقة

| العنصر | الحالي | الهدف المقترح | لماذا الآن | طريقة آمنة |
|---|---:|---:|---|---|
| Node runtime/CI | CI 20؛ local 22 | latest patched **Node 24 LTS** | Node 20 EOL؛ Node 24 مدعوم حتى Apr 2028 | PR toolchain أول؛ لا package changes أخرى. |
| `@types/node` | 26.2.0 | matching 24.x | إزالة type/runtime mismatch | نفس Node PR وبعد typecheck. |
| `eslint` | 9.39.5 | 10.8.1 أو latest tested 10.x | v9 EOL مؤكد | PR منفصل؛ migration guide + lint diff. |
| `next` | 16.3.0 | 16.3.1 | patch داخل Active LTS، متاحة داخل range | update مع full app/DB gate، لا major. لا advisory حالية على 16.3.0 حسب npm audit. |
| `eslint-config-next` | 16.3.0 | 16.3.1 | lockstep مع Next patch | نفس Next patch PR أو ESLint PR حسب peer resolution. |

**ملاحظة:** تحديث Next patch هنا maintenance وقائي منخفض المخاطر، وليس ادعاء أن 16.3.0 مصاب. الإصدار 16.3.0 يتضمن إصلاحات security release المعلنة في يوليو 2026.

### 9.2 نؤجل إلى PRs مستقلة

| العنصر | الحالي → المتاح | سبب عدم دمجه الآن | prerequisite |
|---|---|---|---|
| `@supabase/ssr` | 0.8.0 → 0.12.4 | package 0.x؛ عدة minor jumps وتشمل fixes في session/token refresh. Auth boundary حساسة. | auth/session E2E؛ مراجعة cookie API؛ تحديث peer Supabase JS معًا. |
| `@supabase/supabase-js` | 2.109.0 → 2.112.3 | patch/minor صغيرة لكن auth/realtime critical، و`ssr@0.12.4` يحتاج peer `^2.111.0`. | نفذه مع SSR أو في PR patch مستقل بعد E2E، لا مع Node/ESLint. |
| `vitest` | 3.2.7 → 4.1.10 | major له mocking/reporter/coverage/module-runner breaking changes. 3.2.7 صدر له backport حديث في Jul 2026؛ لا دليل abandonment فوري. | Node 24؛ migration guide؛ كل 714 tests؛ لا mix مع app deps. |
| `jsdom` | 26.1.0 → 30.0.1 | test-only major، والحديث يطلب Node `^22.22.2` أو `^24.15.0` أو `>=26`. | Node 24 أولًا؛ ارفعه مع/بعد Vitest؛ interaction tests. |
| TypeScript | 5.9.3 → 7.0.2 | TS 6 transition وTS 7 native compiler major؛ احتمال types/config/plugin changes. | Node/tooling مستقر؛ اقرأ TS6/7 breaking changes؛ PR مستقل. |
| Tailwind | 3.4.19 → 4.3.3 | لا استخدام فعلي؛ v4 migration تغير CSS/PostCSS/browser contract. | تحقق ثم **remove بدل update** غالبًا. |

### 9.3 لا تحتاج تحديثًا الآن

- React/React DOM installed `19.2.8`: نفس latest line المرصودة ومتوافقة مع Next 16.
- Zod installed `4.4.3`: لا update ظاهرة؛ المشكلة bundle boundary وليست version.
- `@testing-library/react@16.3.2`: إصدار حديث يدعم React 19.
- PostgreSQL 16: major مدعوم وفق سياسة PostgreSQL ذات الخمس سنوات؛ لا سبب لترقية DB major ضمن هذه الصيانة.

---

## 10. عناصر غير مستخدمة: تحقق قبل الإزالة

| العنصر | الحكم الحالي | ماذا نتحقق قبل الحذف |
|---|---|---|
| `@testing-library/user-event` | مرشح إزالة قوي؛ لا import | clean install + كل jsdom interaction tests؛ تأكد أنه ليس peer مطلوبًا. |
| `tailwindcss` | مرشح إزالة قوي؛ لا config/directive/class وCSS يدوي | build/CSS visual smoke؛ lock diff؛ لا تستبدله بـv4. |
| `src/shared/supabase/browser.ts` | لا importer حالي، لكن auth مستقبلية/runbook تشير إليه | auth roadmap وE2E؛ هل browser client مقصود للpassword recovery/invite؟ |
| `src/features/allocation/actions.ts`, `queries.ts` | dormant عمدًا، **لا تحذف الآن** | owner R14 policy؛ `r10-policy-block`؛ DB RPCs ما زالت موجودة. |
| `investors/forms.tsx` | UI orphan/policy-inert، **لا تحذف الآن** | owner policy وdocumentation evidence؛ لا تعتبر عدم import إذن حذف. |
| `provision_presentation_user.mjs` | operator script مستخدم من docs؛ ليس dead | اختبر command في disposable/demo فقط؛ ربما أضف npm script لاحقًا بدل الحذف. |
| direct `@supabase/supabase-js` | لا direct import لكن **مطلوب peer** لـ`@supabase/ssr` | يجب أن يبقى direct peer satisfied؛ ليس unused package عمليًا. |
| 42 exported values / 147 exported types من Knip | signals فقط | تحقق public/test contracts file-by-file؛ لا cleanup شامل. |
| optional orphan lock entries | لا تحذف يدويًا | regenerate lock بالـnpm المثبت بعد approved upgrades؛ راجع diff. |

---

## 11. خارطة صيانة مرحلية

### المرحلة 0 — موافقة وخط أساس

- لا تعديل قبل موافقة المالك.
- سجل baseline: Node/npm، `npm ls`, audit، lint/typecheck/test/build، route bundle stats، Git status.
- PostgreSQL gate يبقى mandatory لأي تغيير يمس package runtime أو source حتى لو لم تتغير migrations.

### المرحلة 1 — دعم وأمان toolchain

1. Node 24 LTS + `@types/node@24` + version/package-manager pin.
2. ESLint 10 في PR منفصل.
3. Next + `eslint-config-next` patch فقط.
4. Dependabot محدود + production-high audit check + immutable Action SHAs/permissions.

**وقف المرحلة إذا:** lock diff غير مفهوم، install hooks تغيرت، lint coverage نقص، أو app/DB gate فشل.  
**Rollback:** revert كل PR منفصلًا؛ لا تجمع الأربعة في commit واحد.

### المرحلة 2 — Auth وtest tooling

1. أضف auth/session browser E2E صغيرًا.
2. حدّث Supabase SSR + JS معًا بعد مراجعة release notes/cookies.
3. بعد استقرار Node: Vitest 4، ثم jsdom 30؛ أو PRان إذا ظهر diff كبير.
4. TypeScript 6/7 يبقى آخر tooling major، مستقلًا.

### المرحلة 3 — أداء قابل للقياس

1. افصل client constants عن Zod؛ الهدف حذف 64 KB gzip chunk من routes المحددة.
2. أضف bundle budget/report بسيط لا يمنع PR أول مرة.
3. اجمع query timing/rows، ثم paginate أكبر timelines فقط.
4. لا تنشئ generic data layer أو RPC ضخم بلا قياس.

### المرحلة 4 — صحة الكود أثناء العمل المنتج

- استخرج validation/error primitives المتطابقة فقط.
- قسّم Agriculture/Livestock forms حسب subsection عند إضافة feature أو إصلاح.
- احتفظ بbehavioral tests قبل تغيير source-contract tests.
- شغّل Knip/Madge دوريًا كdiagnostic أولًا، لا blocking cleanup gate.

### المرحلة 5 — cleanup ووثائق

- صحح README/current status وأضف historical banners.
- أزل Tailwind وuser-event فقط بعد verification.
- لا تحذف S5/allocation أو browser auth code إلا بقرار scope صريح.
- lock dedupe/orphans تُعالج كنتيجة طبيعية، لا مشروعًا مستقلًا.

---

## 12. ما لا أوصي به

- لا `npm update` شامل ولا ترقية كل latest versions في PR واحدة.
- لا Next/framework replacement ولا application rewrite.
- لا Tailwind 3→4 migration لمجرد أنها متاحة؛ package غير مستخدمة أصلًا.
- لا TypeScript 5→7 مع Node/ESLint/Supabase في نفس التغيير.
- لا حذف للـdormant allocation code قبل قرار owner policy.
- لا تعديل/rename لمigrations applied ولا down migrations تجميلية.
- لا dedupe أو formatting/module split بلا قياس أو قيمة مستخدم.
- لا coverage target اعتباطي؛ اختبر journeys والمخاطر الفعلية.

---

## 13. نقاط سليمة يجب الحفاظ عليها

- Next.js 16 هو Active LTS، وليس framework مهجورًا.
- React 19.2 line حديثة.
- PostgreSQL 16 ما زال ضمن الدعم.
- `npm audit` الحالي صفر، وlockfile له integrity لكل packages التي فُحصت.
- لا root lifecycle scripts مشبوهة، ولا generated/vendor code tracked.
- لا circular imports، ولا unresolved imports في Knip، ولا peer conflict في npm tree.
- لا skipped/focused tests، ولا lint/type suppressions في source.
- `strict: true`, `noEmit: true`, App/DB/Sonar gates قائمة.
- feature boundaries أفضل من ظاهر حجم الملفات: لا feature-to-feature runtime cycles؛ معظم feature imports المشتركة auth type-only أو shared clients/helpers.
- database migrations تُختبر clean replay وtenant isolation في CI؛ تكرار function bodies تاريخي لا يعني خطأ تلقائيًا.

---

## 14. مصادر الدعم الرسمية المستخدمة

تم الاطلاع في 2026-08-17:

- Node EOL: <https://nodejs.org/en/about/eol>
- Node release policy: <https://nodejs.org/en/about/releases/>
- Node 24 LTS: <https://nodejs.org/en/blog/release/v24.11.0>
- Node 22 support end: <https://nodejs.org/en/blog/release/v22.20.0>
- ESLint version support: <https://eslint.org/version-support/>
- ESLint 10 migration: <https://eslint.org/docs/latest/use/migrate-to-10.0.0>
- Next.js support policy: <https://nextjs.org/support-policy>
- Next.js 16 requirements: <https://nextjs.org/docs/app/guides/upgrading/version-16>
- Next.js July 2026 security release: <https://nextjs.org/blog/july-2026-security-release>
- React versions: <https://react.dev/versions>
- Supabase SSR releases: <https://github.com/supabase/ssr/releases>
- Vitest 4 migration: <https://vitest.dev/guide/migration.html>
- Tailwind 3→4 upgrade guide: <https://tailwindcss.com/docs/upgrade-guide>
- TypeScript 6 transition notes: <https://www.typescriptlang.org/docs/handbook/release-notes/typescript-6-0.html>
- PostgreSQL version policy: <https://www.postgresql.org/support/versioning/>
- GitHub Actions secure use: <https://docs.github.com/en/actions/reference/security/secure-use>

npm registry metadata (`npm view`) والـinstalled lock/tree هما المرجع للإصدارات والـpeer/engine constraints المذكورة. أي اختلاف مستقبلي يُعاد فحصه وقت تنفيذ الصيانة.

---

## 15. القرار المطلوب من المالك

لا يوجد remediation نُفذ. عند الموافقة، اختر واحدًا فقط كبداية:

1. **الموصى به:** مرحلة 1، بدءًا بـNode 24 + matching types + toolchain pin.
2. Bundle quick win TD-13 بعد مرحلة 1.
3. Auth E2E ثم Supabase update كمرحلة مستقلة.

كل خيار يجب أن يكون PR محدودًا، مع full app/database gates وrollback بالـcommit، ومن دون تغيير production أو migrations أو customer data دون تفويض منفصل.

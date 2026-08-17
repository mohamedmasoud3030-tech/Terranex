# أوامر Terranex المؤكدة من المستودع

**تاريخ التحقق:** 2026-08-17
**Commit:** `9488588f0c6fd1984a1c09769af480f85905c661`

## 1. المتطلبات

- Node.js `>=20.9.0` حسب `package.json`.
- npm مع `package-lock.json` v3.
- لتشغيل DB gate محليًا: إما PostgreSQL client/server (`psql`, `pg_dump`, `pg_restore`) متوافق، أو Docker. runner يستخدم PostgreSQL 16 عند Docker fallback.
- تطبيق فعلي يحتاج Supabase project عليه migrations الحالية وAuth user صالح.

بيئة CI الرسمية تستخدم Node 20 وPostgreSQL 16. بيئة هذا الفحص كانت Node `v22.22.3` وnpm `10.9.8`.

## 2. التثبيت

الأمر الصحيح لنسخة lockfile ثابتة:

```bash
npm ci --no-audit --no-fund
```

نتيجة الفحص: PASS؛ تم تثبيت 493 package. ظهر warning عن `whatwg-encoding@3.1.1` deprecated، دون فشل.

## 3. متغيرات التطبيق

الأسماء المطلوبة فقط:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

لإنشاء ملف محلي دون استبدال ملف موجود:

```bash
test -e .env.local || cp .env.example .env.local
```

ثم توضع قيم بيئة التطوير الآمنة في `.env.local`. لا تضع `service role`, database password، access token، أو production connection string في Git.

> ملاحظة أمان: `.env.production` موجود ومتعقب في المستودع. Next build يقرأه تلقائيًا ما لم تُمرر override. لا تشغل التطبيق بلا قصد على البيئة المشار إليها فيه، ولا تستخدم shared/production data أثناء التطوير.

## 4. التطوير والتشغيل

### development

مع بيئة Supabase development صحيحة:

```bash
npm run dev
```

لبيئة container/preview تحتاج الاستماع على كل interfaces:

```bash
npm run dev -- --hostname 0.0.0.0
```

`npm run dev` معرف في `package.json`، لكنه لم يُستخدم لاتصال authenticated حقيقي أثناء هذا الاكتشاف.

### production build

```bash
npm run build
```

لبناء آمن لا يتصل ببيئة Terranex الحقيقية أثناء الفحص استُخدم:

```bash
NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=placeholder-publishable-key \
npm run build
```

النتيجة: PASS؛ Next.js build سجل 30 route.

### تشغيل build

```bash
npm start
```

للاستماع على كل interfaces ومنفذ محدد:

```bash
npm start -- --hostname 0.0.0.0 --port 3000
```

تم التحقق من هذا الأمر محليًا باستخدام placeholder env: server بدأ، `/login` أعاد 200، و`/` بلا session أعاد redirect إلى `/login`.

## 5. فحوص التطبيق

### lint

```bash
npm run lint
```

نتيجة 2026-08-17: PASS.

### TypeScript

```bash
npm run typecheck
```

نتيجة 2026-08-17: PASS.

### Vitest

```bash
npm test
```

أو الاسم الكامل المكافئ من scripts:

```bash
npm run test
```

نتيجة 2026-08-17: PASS — 52 files و714 tests.

### dependency audit

ليست ضمن npm scripts أو CI الحالي، لكنها شُغلت بأمان:

```bash
npm audit --omit=dev --audit-level=low
npm audit --audit-level=low
```

النتيجة لكليهما: 0 vulnerabilities.

### Git whitespace/diff check

```bash
git diff --check
```

كان PASS قبل إضافة وثائق الاكتشاف.

## 6. قاعدة البيانات

### gate الكامل

```bash
npm run db:test
```

وهو ينفذ:

```bash
bash ./scripts/db-test.sh
```

السلوك:

1. يستخدم `psql` إن كان متاحًا.
2. وإلا يبدأ PostgreSQL 16 container عبر Docker.
3. ينشئ/يعيد إنشاء قاعدة `TERRANEX_TEST_DB`، والافتراضي `terranex_test`.
4. يشغل `supabase/tests/00_supabase_shim.sql`.
5. يشغل كل `supabase/migrations/*.sql` بترتيب filename.
6. يشغل كل SQL test ثم كل shell/concurrency/upgrade/backup test.

> استخدمه فقط على قاعدة disposable. الـ runner ينفذ `drop database if exists "$TERRANEX_TEST_DB"`.

النتيجة المحلية في بيئة الاكتشاف: **UNRESOLVED / exit 2** لأن `psql` وDocker غير موجودين.
النتيجة الخارجية على نفس SHA: GitHub Actions run `32030212661`، job `database`: PASS على PostgreSQL 16.

### اختيار قاعدة اختبار مختلفة

```bash
TERRANEX_TEST_DB=terranex_discovery_test npm run db:test
```

لا تستخدم اسم production أو shared DB.

### DB shell

```bash
npm run db:shell
```

أو قاعدة محددة:

```bash
bash ./scripts/db-shell.sh terranex_test
```

الأمر تفاعلي؛ لم يُشغل في بيئة الاكتشاف لعدم وجود `psql`/Docker.

## 7. R15 policy admission gate

```bash
npm run r15:admission
```

النتيجة الحالية الصحيحة:

```text
R15 admission: BLOCKED
```

والسبب: `BD-001`…`BD-012` كلها `OPEN`. exit code الحالي 1 متوقع ومقصود. لا تحاول جعله PASS بإضافة قيم وهمية؛ يحتاج قرارات مالك موثقة حسب `docs/OPEN_BUSINESS_DECISIONS.md`.

## 8. Pilot/readiness checks

### inventory

```bash
bash scripts/pilot-readiness/inventory.sh
```

نتيجة 2026-08-17: PASS — 45 checked، 0 missing.

### consistency validator

```bash
bash scripts/pilot-readiness/check-readiness-pack.sh
```

نتيجة 2026-08-17: PASS.

هذه الفحوص تثبت وجود/اتساق artifacts والأسماء فقط؛ لا تثبت production readiness أو customer UAT.

## 9. CI/CD

### Greenfield CI

الملف: `.github/workflows/greenfield-ci.yml`.

على Pull Request إلى `main`، push إلى `main`، أو manual dispatch، ينفذ:

```bash
npm ci --no-audit --no-fund
npm run lint
npm run test
npm run build
npm run typecheck
bash ./scripts/db-test.sh
```

الـ build في CI يستخدم placeholder public Supabase variables. DB job يستخدم PostgreSQL 16 service.

### Pilot/Staging DB activation

الملف: `.github/workflows/pilot-activation.yml`.

تشغيل inspection-only من GitHub CLI يمكن أن يكون:

```bash
gh workflow run pilot-activation.yml \
  -f apply_migrations=false \
  -f supabase_project_ref='<AUTHORIZED_PROJECT_REF>'
```

تطبيق migrations يغير shared environment ويحتاج تفويضًا صريحًا وGitHub Secret صالحًا:

```bash
gh workflow run pilot-activation.yml \
  -f apply_migrations=true \
  -f supabase_project_ref='<AUTHORIZED_PROJECT_REF>'
```

**لم يُنفذ أي منهما في هذا الاكتشاف.** workflow يفحص الحالة read-only أولًا، ويستخدم checksum migration ledger، ويفشل مغلقًا عند schema غير موثوقة.

لا يوجد App deploy command/workflow داخل المستودع؛ Vercel integration إن وجدت فهي خارج Git.

## 10. Demo tools — لا تستخدمها كsetup عادي

### Auth presentation user

الأداة:

```bash
node scripts/demo/provision_presentation_user.mjs
```

تحتاج server-side admin variables مثل `SUPABASE_SERVICE_ROLE_KEY` وdemo password من بيئة آمنة. لا تطبع password.

### Real Estate showcase seed

المصدر:

```text
scripts/demo/seed_real_estate_showcase.sql
```

لا يوجد npm script رسمي لتشغيله. لا تشغله على أي shared/production DB دون تفويض. الأهم: seed الحالي يستخدم S5 وcontribution posting اللذين تقفلهما policy-safety migration عندما `policy_authority` فارغة؛ لذلك ليس fresh-schema setup صالحًا حاليًا كما هو.

## 11. أقصر baseline موصى به لكل تغيير لاحق

لتغيير app فقط:

```bash
npm run lint
npm run typecheck
npm test
NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=placeholder-publishable-key \
npm run build
git diff --check
```

لتغيير migration/financial behavior، أضف gate قاعدة البيانات الإلزامي:

```bash
npm run db:test
```

ولتغيير investor-policy-dependent behavior، يجب أن يسبق العمل:

```bash
npm run r15:admission
```

ولا يبدأ العمل إن ظل `BLOCKED`.

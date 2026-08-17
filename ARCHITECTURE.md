# معمارية Terranex الحالية

**النطاق المفحوص:** `HEAD 9488588f0c6fd1984a1c09769af480f85905c661` بتاريخ 2026-08-17.
**حالة العبارات:** «مؤكد» يعني شوهد في الكود/الم migration/الاختبار أو في build فعلي. «غير معروف» يعني يحتاج بيئة حقيقية أو قرارًا خارج المستودع.

## 1. الشكل العام

Terranex هو **modular monolith** واحد:

```text
Browser
  └─ Next.js 16 App Router
       ├─ React Server Components (queries/rendering)
       ├─ Client Components (forms and local UI state)
       ├─ Server Actions (commands)
       └─ Supabase SSR session client
             ├─ Supabase Auth
             ├─ PostgreSQL 16 / PostgREST / RPC
             └─ Private Storage: procurement-evidence
```

- package واحد في جذر المستودع؛ ليس monorepo.
- لا microservices ولا backend مستقل.
- لا API routes خاصة بالتطبيق.
- لا queue/background workers/cron/webhooks.
- قاعدة بيانات واحدة هي النظام المعتمد للمعاملات.

## 2. هيكل المستودع

```text
src/app/                 Next.js routes, layouts, loading/error states, forms
src/features/            19 bounded feature folders
src/shared/              Supabase clients, exact money, idempotency
src/proxy.ts              Auth/session middleware boundary
supabase/migrations/      97 ordered SQL files
supabase/tests/           64 SQL files (includes bootstrap shim) + 42 shell files
scripts/                  DB runner, demo tools, readiness checks
.github/workflows/        App/DB CI and manual pilot DB activation
docs/                     Canonical contracts, ADRs, runbooks, readiness/status files
tests/                    52 Vitest files
```

Feature folders:

`agriculture`, `allocation`, `assets`, `auth`, `close`, `control`, `finance`, `funding`, `governance`, `intake`, `livestock`, `organizations`, `pilot`, `portfolios`, `procurement`, `projects`, `real-estate`, `revenue`, `workspace`.

## 3. تدفق القراءة والكتابة

### القراءة

1. `src/proxy.ts` يطلب `supabase.auth.getUser()` ويحوّل الزائر غير المسجل إلى `/login`.
2. App layout يعيد فحص المستخدم.
3. Server Component يستدعي دالة `queries.ts`.
4. الدالة تستخدم authenticated Supabase server client.
5. PostgREST يقرأ table أو `*_read` view.
6. RLS يطبق حد Organization مرة أخرى.
7. الصفحة تحول القيم إلى واجهة عربية.

### الكتابة

1. Client form يستخدم React `useActionState`.
2. Server Action يحول `FormData` ويفحصه بـ Zod.
3. معظم الأوامر المادية تستدعي PostgreSQL RPC واحدًا.
4. الـ RPC يعيد التحقق من `auth.uid()`، membership، role/state، tenant/project coherence، idempotency، والمبلغ.
5. المعاملة تكتب الحقائق والقيود و`audit_events` معًا.
6. `revalidatePath` يحدث الصفحات بعد النجاح.

لا يرسل المتصفح balances أو approval outcomes باعتبارها حقيقة معتمدة. المبالغ تستخدم نصًا/`BigInt` في التطبيق و`bigint minor_units` في PostgreSQL.

## 4. Frontend

### Rendering وstate

- React Server Components هي الوضع الافتراضي.
- Client Components موجودة للنماذج وحالات الخطأ/pending والاختيارات الديناميكية.
- لا Redux/Zustand/MobX/React Query.
- state محلي عبر `useState`, `useMemo`, `useActionState`, وأحيانًا `useSyncExternalStore` لحل nonce عند hydration.
- لا global client cache؛ البيانات تعاد من server بعد `revalidatePath`.

### Forms وvalidation

- HTML constraints: `required`, `minLength`, `maxLength`, input types.
- Zod في feature `schema.ts` عند Server Action boundary.
- PostgreSQL constraints/triggers/RPC checks هي الحماية الأخيرة.
- أوامر كثيرة تستخدم idempotency key ثابتًا عند retry ويتغير فقط بعد نجاح مؤكد.
- يوجد انتقال تدريجي: بعض features لديها `actions.ts` قديمة و`command-actions.ts` wrappers لتوحيد lifecycle. هذا تكرار تقني مقصود مؤقتًا لكنه يزيد سطح الصيانة.

### Styling وresponsive

- ملف واحد `src/app/globals.css` مع CSS variables وclasses، إضافة إلى inline styles.
- breakpoints عند `960px` و`720px`، grids مرنة، tables داخل horizontal scroll.
- لا Tailwind config أو Tailwind classes رغم وجود dependency `tailwindcss`.
- لا design-system package منفصل.

### اللغة وRTL

- root: `<html lang="ar" dir="rtl">`.
- النص الحالي عربي hard-coded، مع identifiers/currency codes بالإنجليزية.
- exact money parser يقبل الأرقام العربية واللاتينية والفواصل العربية.
- لا i18n library، locale routing، ملفات ترجمة، أو واجهة English فعلية. هذا يخالف عبارة الوثائق أن English/LTR “supported”.

### accessibility patterns

الموجود:

- semantic `main/nav/header/section/table` في صفحات كثيرة.
- labels للنماذج، `role="alert"`, `aria-current`, `aria-label` في مواضع.
- `:focus-visible` واضح.
- `prefers-reduced-motion` للـ skeleton.
- empty/error/loading/forbidden components لبعض المسارات.

غير المثبت:

- لا axe/Pa11y/Lighthouse automated gate.
- لا browser E2E أو keyboard journey test.
- لم يحدث فحص WCAG 2.2 AA فعلي على التطبيق الحي ضمن هذا الاكتشاف.

## 5. Backend application layer

- backend هو Next Server Actions + Supabase PostgREST/RPC.
- لا `src/app/**/route.ts`.
- commands البسيطة والمادية كلها تقريبًا RPC-backed.
- queries تستخدم tables/read views مباشرة مع authenticated client.
- الأخطاء تتحول غالبًا إلى رسائل عربية آمنة؛ لا يظهر raw database error للمستخدم في المسارات المعتادة.
- لا task scheduler ولا asynchronous retry engine.

## 6. قاعدة البيانات

### الحجم المؤكد من migration source

- **97** migration files.
- **161** base table names منشأة.
- **163** view names فريدة (`202` definitions بسبب forward replacements).
- **436** function names فريدة (`516` definitions/replacements).
- **250** index definitions.
- **280** trigger names فريدة.
- statuses غالبًا `text + CHECK` وليست PostgreSQL enum types.

### قائمة base tables الكاملة، مجمعة حسب المجال

#### Identity/Core — 4

`organizations`, `memberships`, `investment_projects`, `audit_events`.

#### Parties/agreements/funding — 8

`parties`, `project_participants`, `investment_agreements`, `agreement_versions`, `commitment_terms`, `capital_calls`, `capital_call_lines`, `contributions`.

#### S2 finance/cash — 9

`project_cash_accounts`, `semantic_accounts`, `cost_obligations`, `journal_batches`, `journal_lines`, `project_payments`, `bank_statement_imports`, `bank_statement_lines`, `reconciliation_matches`.

#### Real Estate/revenue/rental — 24

`real_estate_project_profiles`, `property_assets`, `parcels`, `property_asset_state_history`, `property_acquisitions`, `property_control_records`, `development_phases`, `development_phase_state_history`, `development_milestones`, `development_milestone_state_history`, `property_budget_versions`, `property_budget_lines`, `property_cost_items`, `property_valuations`, `real_estate_events`, `property_dispositions`, `property_sale_recognitions`, `property_sale_carrying_cost_sources`, `property_sale_collections`, `property_sale_collection_reconciliations`, `bank_statement_reconciliation_allocations`, `property_rental_income_recognitions`, `property_rental_collections`, `property_rental_collection_reconciliations`.

#### Period close/correction — 6

`accounting_periods`, `close_runs`, `close_run_gates`, `close_run_exceptions`, `correction_requests`, `close_run_snapshots`.

#### Allocation/distribution retained mechanism — 8

`s5_allocation_rule_sets`, `s5_allocation_rules`, `s5_allocation_runs`, `s5_allocation_lines`, `s5_distributions`, `s5_distribution_payments`, `s5_allocation_rule_basis`, `s5_distribution_payment_reconciliations`.

#### Pilot/opening/reconciliation/UAT — 7

`s7_opening_mapping_codes`, `s7_opening_imports`, `s7_opening_import_rows`, `s7_reconciliation_checkpoints`, `s7_reconciliation_exceptions`, `s7_uat_tasks`, `s7_pilot_rehearsals`.

#### Guided intake — 4

`project_intake_declarations`, `project_intake_section_applicability`, `project_intake_modelling_gaps`, `project_intake_evidence_items`.

#### Agriculture — 22

`agriculture_project_profiles`, `farms`, `fields`, `crop_cycles`, `crop_cycle_field_assignments`, `crop_cycle_state_history`, `field_activities`, `input_items`, `input_lots`, `input_applications`, `storage_locations`, `harvest_events`, `harvest_lots`, `harvest_inventory_movements`, `agricultural_land_assets`, `farm_land_asset_links`, `agriculture_sales`, `agriculture_sale_lines`, `agriculture_sale_recognitions`, `agriculture_sale_collections`, `crop_cycle_cost_attributions`, `crop_cycle_closeouts`.

#### Livestock — 27

`livestock_project_profiles`, `livestock_sites`, `livestock_herds`, `livestock_cohorts`, `livestock_cohort_state_history`, `livestock_cohort_initial_placements`, `livestock_cohort_movements`, `livestock_quantity_event_types`, `livestock_quantity_events`, `livestock_weight_events`, `livestock_quantity_operations`, `livestock_cohort_lineage`, `livestock_medicine_products`, `livestock_animals`, `livestock_animal_memberships`, `livestock_health_events`, `livestock_reproduction_events`, `livestock_feed_items`, `livestock_feed_issues`, `livestock_purchases`, `livestock_purchase_lines`, `livestock_sales`, `livestock_sale_lines`, `livestock_sale_recognitions`, `livestock_sale_collections`, `livestock_cohort_cost_attributions`, `livestock_cohort_closeouts`.

#### Portfolio — 3

`investment_portfolios`, `investment_portfolio_state_history`, `portfolio_project_assignments`.

#### Procurement/vendor finance/evidence — 22

`procurement_suppliers`, `purchase_requests`, `purchase_request_lines`, `purchase_orders`, `purchase_order_lines`, `purchase_receipts`, `purchase_receipt_lines`, `supplier_invoices`, `supplier_invoice_lines`, `cost_payment_proposals`, `procurement_evidence_documents`, `procurement_evidence_versions`, `procurement_evidence_links`, `procurement_acceptances`, `procurement_acceptance_lines`, `procurement_exception_reasons`, `procurement_invoice_exceptions`, `unapplied_payments`, `payment_allocations`, `supplier_advances`, `supplier_advance_applications`, `supplier_credit_notes`.

#### Finance control F3–F6 — 13

`project_milestones`, `cost_obligation_terms`, `cost_obligation_schedule_lines`, `cost_obligation_disputes`, `cost_obligation_retention_releases`, `project_budgets`, `project_budget_lines`, `approval_policies`, `approval_exceptions`, `approval_signoffs`, `fx_rate_snapshots`, `fx_conversion_log`, `tax_registry`.

#### Governance — 3

`project_risk_items`, `project_risk_resolutions`, `project_decision_records`.

#### Policy activation registry — 1

`policy_authority`.

المجموع: **161 table**.

### الملكية وtenant boundary

- كل tenant table تقريبًا يحمل `organization_id NOT NULL`.
- الاستثناءات المقصودة: `organizations` نفسه، وregistries مشتركة مثل `semantic_accounts`, `s7_opening_mapping_codes`, `livestock_quantity_event_types`.
- العلاقات الحساسة تستخدم composite foreign keys تشمل `organization_id` و/أو `project_id`.
- RLS وسياسات read تعتمد غالبًا `is_active_member(organization_id)`.
- migrations تستعمل dynamic SQL loops لبعض مجموعات الجداول، لذلك عدّ النص الحرفي وحده لا يكفي لتحديد RLS. الاختبار المرجعي هو replay/tenant test؛ GitHub DB job نجح على نفس SHA.
- لا يوجد investor self-scope في runtime الحالي؛ العضو يرى منظمة كاملة.

### constraints/indexes/concurrency

- المال `bigint`; currency غالبًا 3 أحرف uppercase.
- balanced journal batch، source uniqueness، request hash، idempotency uniqueness، state transitions، ceilings، quantity conservation، period locks، وأدلة maker-checker مفروضة في DB.
- `pg_advisory_xact_lock`, `FOR UPDATE`, unique/partial indexes، deferred constraint triggers مستخدمة ضد السباقات.
- read models تفصل cash/revenue/cost/valuation/result وتحتفظ بالـ currency/status.
- migrations forward-only؛ نفس function/view قد يعاد تعريفه في migration لاحق.

### الحذف والتصحيح

- `ON DELETE RESTRICT` هو الغالب: 830 occurrence في migration text.
- يوجد 7 `CASCADE` فقط: membership مع Organization/User، وبعض draft child rows الخاصة بالميزانية/الجداول والسياسات.
- `responsible_manager_id` الوحيد الملحوظ بـ `SET NULL`.
- facts كثيرة عليها append-only/no-delete triggers.
- الحذف المسموح للمستخدم يتركز في draft obligation وdraft budget.
- التصحيح المالي يتم reversal/repost؛ reconciliation يمكن void controlled.
- Portfolio assignment يُغلق بـ `removed_at` ولا يحذف تاريخه.

### seed data

- migrations تزرع registries فقط: semantic account roles، opening mapping codes، livestock quantity event types.
- synthetic Real Estate showcase موجود في `scripts/demo/seed_real_estate_showcase.sql` لكنه يدوي وليس migration/startup seed.
- يوجد تعارض حالي: seed القديم ينفذ S5 و`attach_contribution_cash` ولا ينشئ `policy_authority`؛ لذلك fresh replay بعد policy-safety migration سيوقف هذه الأجزاء. لم يُشغل seed على production أثناء الفحص.

## 7. Authentication وauthorization

### Session

- `@supabase/ssr` في browser/server/proxy.
- cookies هي session carrier.
- proxy refreshes/validates user، ثم layout يعيد check.
- login يستخدم `signInWithPassword`; logout يستخدم `signOut`.

### Account lifecycle الموجود

- Auth users يجب أن يكونوا موجودين مسبقًا.
- Organization onboarding يمنح `OWNER`.
- Owner يستطيع جعل membership `ACTIVE/INACTIVE`; DB يمنع تعطيل آخر Owner نشط.
- demo provisioner الوحيد الذي ينشئ Auth user يستخدم Service Role server-side ويتطلب متغيرات خارج Git.

### غير الموجود

sign-up، invite، email verification UI، forgot/reset password، MFA، profile، session/device management، user deletion، project-scoped role assignment، dedicated investor login.

### trusted boundaries

- browser غير موثوق.
- Next server يستخدم publishable key مع user session، وليس Service Role.
- DB/RLS/RPC هي السلطة النهائية.
- Service Role يظهر فقط في script إداري يدوي.
- GitHub pilot activation يستخدم Supabase Management API token من GitHub Secrets؛ لا يطبعه.

## 8. Integrations

### الموجودة

1. **Supabase Auth/Postgres/PostgREST/Storage**: النظام الأساسي.
2. **Vercel**: `vercel.json` يحدد `framework: nextjs` فقط. لا يوجد deploy workflow داخل Git.
3. **GitHub Actions**: app + PostgreSQL CI، وmanual pilot DB activation.
4. **Supabase Management API**: inspection/migration activation يدوي، fail-closed، checksum ledger.
5. **SonarCloud**: ملفات إعداد موجودة، وSonar check ظاهر على بعض Pull Requests؛ آلية الربط الخارجية غير موجودة في workflow المحلي.

### غير الموجودة

Email، WhatsApp/SMS، payment providers، bank APIs، analytics، monitoring/APM، maps، AI، ETA e-invoice، external GL adapter، object OCR، public API.

Supabase Storage يستخدم فقط أدلة Procurement. تحميل الملف محدود ومربوط بـ tenant/project/document metadata، والقراءة عبر signed URL.

## 9. PWA وoffline

لا توجد أي artifacts خاصة بـ PWA:

- لا `manifest.webmanifest`.
- لا app icons/favicon assets في المستودع.
- لا service worker.
- لا cache policy خاصة بالتطبيق.
- لا install prompt أو update flow.
- لا IndexedDB/offline drafts/conflict sync.

إذن Terranex الحالي web app عادي. أي كلام في وثائق UX عن offline هو requirement مستقبلي، وليس behavior موجودًا.

## 10. Build، deployment، configuration

### Runtime versions

- `package.json`: Node `>=20.9.0`.
- CI: Node 20 وPostgreSQL 16.
- بيئة الفحص: Node `v22.22.3`, npm `10.9.8`.
- lockfile: npm `package-lock.json`, lockfile v3، package واحد.

### runtime app variables

التطبيق يحتاج اسمين فقط:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

`.env.example` يوثق الاسمين. `.env.production` ملف tracked يحمل نفس الاسمين بقيم بيئة؛ لم تُعرض القيم في هذا الفحص. لأنه tracked، يجب الحذر: build بلا override قد يتجه تلقائيًا إلى البيئة المسجلة.

متغيرات الأدوات الإدارية المنفصلة تشمل أسماء مثل `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_SERVICE_ROLE_KEY`, وdemo credentials. قيمها لا يجب أن تدخل Git.

### deployment flow

- App: يفترض Vercel integration خارج المستودع؛ لا يوجد دليل code-level على من ينشر أو على rollback automated.
- DB: `.github/workflows/pilot-activation.yml` يدوي، inspection-only افتراضيًا، ويمكنه تطبيق migrations بعد checksum/state checks.
- workflow يحتوي default Supabase project ref؛ هذا coupling بيئي واضح وإن لم يكن secret.
- لا توجد environment matrices واضحة لـ dev/staging/prod داخل config، غير env files/secrets.

### monitoring/logs

- لا application logger structured، health route، metrics، tracing، Sentry، أو alert definitions.
- المتاح هو Vercel/Supabase/GitHub platform output خارج الكود، وحالته التشغيلية غير معروفة من المستودع.

### backups/rollback

- DB gate يحتوي automated `pg_dump/pg_restore` rehearsal على قاعدة اختبار.
- `docs/runbooks/BACKUP_AND_RESTORE.md` يشرح restore آمن إلى DB جديدة.
- production backup schedule/retention/restore لم يُثبت؛ deployment checklist ما زالت unchecked.
- migrations forward-only؛ rollback بعد كتابة حقائق جديدة يحتاج قرارًا تشغيليًا وليس down migrations آلية.

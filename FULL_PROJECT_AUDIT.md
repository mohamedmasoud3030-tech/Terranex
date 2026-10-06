# التدقيق المستقل الكامل لمشروع Terranex

> **⚠️ Historical snapshot — not current status.**
>
> This audit was measured when the repository had **52 Vitest files / 714
> tests** and **106 database verification files**. Those counts are preserved
> as history and are **not** current: the working tree now carries **76 Vitest
> files / 1095 tests** across 106 migrations and 112 database suites. The
> document also predates R14, ADR 0034 and the H1 per-currency contracts.
>
> Its engineering findings (AUD-01…AUD-n) are deliberately left unrewritten;
> read them as a dated assessment, not as an open defect list. For present
> status read `README.md`.

**تاريخ التدقيق:** 2026-08-17
**النسخة المدققة:** `243f7f09026d0cd8a793048cce03bbbaa1577081`
**قاعدة runtime قبل وثائق الاكتشاف:** `9488588f0c6fd1984a1c09769af480f85905c661`
**الفرع:** `arena/01a00fc0-terranex`
**نوع التدقيق:** Engineering + QA + Security + Product + UX + Operations، على كامل المستودع وليس على diff واحد.

## 1. ملخص تنفيذي

Terranex منتج واسع وجاد تقنيًا: تطبيق `Next.js` عربي، وقاعدة `PostgreSQL/Supabase` كبيرة، وثلاثة قطاعات تشغيلية، ونظام مالي مضبوط بقيود قوية. قاعدة البيانات هي أقوى جزء في المشروع: exact money، double-entry، RLS، composite foreign keys، append-only facts، maker/checker، idempotency في معظم الأوامر، concurrency tests، period locks، reversal، وbackup/restore rehearsal.

لكن نجاح build و714 test لا يعني أن المنتج جاهز للإطلاق الحقيقي. التدقيق وجد فجوة بين **قوة محرك قاعدة البيانات** وبين **اكتمال المنتج والتشغيل الفعلي**:

- خمسة أوامر S6 الحساسة لا تملك response-loss replay contract كاملًا في النسخة الحالية.
- نموذج الصلاحيات الفعلي هو `OWNER | MEMBER` فقط، بينما المنتج يفترض أدوارًا أكثر دقة. كل عضو نشط يستطيع قراءة نطاق واسع داخل المنظمة.
- رحلة الفريق غير مكتملة: لا دعوات، ولا إنشاء عضويات من UI، ولا password recovery أو MFA.
- أجزاء أساسية موجودة في الكود لكنها غير قابلة للاكتشاف من التنقل؛ أهمها `/projects/[projectId]/livestock/operations`، كما أن Finance/Close غير ظاهرين لقطاعي Agriculture وLivestock.
- لا توجد أدلة تشغيل حقيقية على monitoring، production backups، restore فعلي، post-deploy smoke، أو authenticated browser E2E.
- Investor economics مقفلة بشكل صحيح، وكل `BD-001…BD-012` ما زالت `OPEN`.

### حكم الإصدار

| الاستخدام | الحكم |
|---|---|
| Demo اصطناعي أو فحص داخلي | **GO بحذر**؛ build وCI وقاعدة البيانات الاصطناعية تعمل. |
| Staging غير حقيقي لاختبار الفريق | **CONDITIONAL GO** بعد إصلاح الوصول إلى الرحلات الأساسية وعدم استخدام S6 المتأثر. |
| Pilot ببيانات عميل حقيقية | **HOLD / NO-GO حاليًا**. |
| Production مالي فعلي | **NO-GO حاليًا**. |
| R15 / Investor economics | **BLOCKED عمدًا** حتى إغلاق `BD-001…BD-012`. |

لا توجد في هذا الفحص **Critical credential leak** أو cross-tenant leak مؤكدة. توجد عدة findings بدرجة **High** تكفي وحدها لمنع الإطلاق الحقيقي.

## 2. نطاق وأدلة التدقيق

تم فحص:

- كل `src/app`, `src/features`, `src/shared`, و`src/proxy.ts`.
- 30 route ناتجة من production build.
- 97 migration، و161 base table، وطبقة RLS/RPC/read views.
- 52 Vitest files و106 database verification files.
- GitHub CI، pilot activation workflow، Vercel config، env contract، demo scripts، runbooks، وcanonical product documents.
- file upload/storage path، authentication، authorization، error/loading states، RTL/CSS، bundles، queries، وعمليات النشر/الاستعادة.

### حالة Git عند بدء التدقيق

- working tree كان نظيفًا.
- الفرع كان `0 behind / 1 ahead` عن `origin/main`؛ الفرق هو وثائق الاكتشاف السابقة فقط.
- لم توجد تعديلات runtime أو migrations غير ملتزمة.
- checkout محلي shallow، لذلك لم يكن ممكنًا تدقيق التاريخ الكامل للـ Git أو secrets القديمة.
- Pull Requests المفتوحة ذات الصلة وقت التدقيق: `#164` لإصلاح S6 replay، و`#167` لوثائق الاكتشاف.

## 3. خريطة المخاطر على مستوى المشروع

| المجال | Critical | High | Medium | Low | التقييم المختصر |
|---|---:|---:|---:|---:|---|
| Product/Journeys | 0 | 3 | 4 | 1 | القدرات كثيرة، لكن onboarding والتنقل وmulti-org/project lifecycle غير مكتملة. |
| Correctness/Reliability | 0 | 3 | 3 | 1 | DB قوية، لكن توجد فجوات replay وتصنيف reversal وهوية Project. |
| Security/Privacy | 0 | 2 | 4 | 1 | tenant isolation قوي؛ least privilege، file safety، headers، retention غير مكتملة. |
| Data/Migrations | 0 | 0 | 4 | 1 | constraints قوية؛ توجد مخاطر تشغيل migration/versioning وغياب سياسة retention حية. |
| Testing/QA | 0 | 1 | 3 | 0 | DB tests ممتازة؛ لا browser E2E/accessibility، وعدد كبير من tests نصي. |
| UX/Accessibility | 0 | 1 | 4 | 2 | RTL واضح، لكن routes غير قابلة للاكتشاف، controls غير مسماة، ولا confirmations متسقة. |
| Performance | 0 | 0 | 3 | 1 | 22–29 request في صفحات أساسية، N+1، unbounded reads، وZod في client bundles. |
| PWA/Offline | 0 | 0 | 1 | 1 | غير موجود بالكامل، وهو معلن كـdeferred. |
| Operations/Release | 0 | 2 | 4 | 1 | CI/runbooks جيدان؛ لا proof لتشغيل production أو monitoring/backups حقيقية. |

> الأرقام أعلاه تصنيف للمخاطر، وليست عددًا آليًا لكل صف في الجدول التالي؛ بعض findings تؤثر في أكثر من مجال.

## 4. جدول النتائج التفصيلي

### معاني التصنيف

- **عيب مؤكد:** السلوك الخاطئ ظاهر مباشرة في الكود/build/command.
- **خطر مرجح:** لا يوجد incident مثبت، لكن المسار الحالي يسمح بخطر واقعي.
- **توصية:** تحسين مهم، وليس فشلًا مثبتًا.
- **مجهول:** يحتاج بيئة أو دليلًا خارج المستودع.

| ID | النوع | الشدة | النتيجة والدليل | أثر المستخدم/الأعمال | المناطق المتأثرة | أصغر معالجة موصى بها |
|---|---|---|---|---|---|---|
| AUD-01 | عيب مؤكد | **High** | خمسة أوامر S6 لا ترسل أو تخزن idempotency receipt كاملًا: `s6_create_accounting_period`, `s6_prepare_close_run`, `s6_request_close_run_exception`, `s6_reopen_period`, `s6_request_correction`. الدليل: `src/features/close/actions.ts` لا يرسل `p_idempotency_key` لهذه الأوامر، و`src/features/close/schema.ts` لا يطلب key لأربعة منها. | نجاح DB مع ضياع response ثم retry قد يظهر كفشل أو constraint conflict بدل الرجوع لنفس النتيجة. المستخدم لا يعرف هل العملية تمت. | Close، correction، reliability، financial operations. | مراجعة PR `#164` كإصلاح مستقل، إثبات same-key/same-payload replay وpayload mismatch وreauthorization، ثم تطبيق migration في staging فقط بعد موافقة صريحة. |
| AUD-02 | عيب مؤكد | **High** | نموذج الصلاحيات الفعلي `memberships.role in ('OWNER','MEMBER')` فقط في `20260810000100_s0_foundation.sql`. أغلب RLS read policies تستخدم فقط `is_active_member(organization_id)`. `create_investment_project`, `create_party` وعدة أوامر تشغيلية تتطلب membership فقط. | عضو تشغيلي عادي يستطيع رؤية parties، cash، bank descriptions، audit، evidence، ومعلومات كل Projects داخل المنظمة، وتنفيذ أعمال أوسع من الدور المقترح. لا يوجد investor self-scope. | AuthZ، privacy، roles، كل domains. | قبل أي pilot: يعتمد المالك capability matrix صغيرة، ثم تفرض في DB/RPC/RLS. إخفاء الأزرار وحده غير كافٍ. |
| AUD-03 | عيب مؤكد | **High** | لا توجد رحلة team onboarding داخل المنتج: لا invite/sign-up/reset/MFA، ولا command لإضافة Membership جديدة. الموجود هو create Organization للمالك، وتفعيل/تعطيل عضوية موجودة. `scripts/demo/provision_presentation_user.mjs` أداة Service Role خارج UI. | المالك غير التقني لا يستطيع إدخال فريقه دون operator/admin خارجي؛ password recovery غير متاح في المنتج. | Account lifecycle، onboarding، operations. | إضافة مسار دعوة آمن ومحدود + قبول دعوة + reset password؛ إبقاء إنشاء المستخدم الإداري server-side وعدم إدخال Service Role إلى التطبيق. |
| AUD-04 | عيب مؤكد | **High** | `/projects/[projectId]/livestock/operations` لا يوجد له أي Link في `src/app` أو `src/features`. `LIVESTOCK_SECTIONS` في `src/features/workspace/nav.tsx` يحتوي `/livestock` فقط. الصفحة غير القابلة للاكتشاف تحمل الصحة، الدواء، الحيوانات، التكاثر، العلف وFCR. كذلك Agriculture/Livestock nav لا تعرض `/costs`, `/cash`, `/close`, `/funding`, `/pilot`, `/controls`. | قدرات تشغيلية ومالية أساسية موجودة لكنها عمليًا مخفية، فيتعذر على المستخدم إكمال الرحلة بدون معرفة URL يدويًا. | Product navigation، Livestock، shared Finance، UX. | إضافة links فقط للroutes الحالية حسب القطاع، مع route/navigation tests. لا حاجة لتغيير business rules. |
| AUD-05 | عيب مؤكد | **High** | `create_investment_project` في `20260814001700_livestock_foundation.sql` يعتبر `(organization, lower(name), sector)` idempotency identity. عند وجود اسم مطابق يرجع Project القديم بلا مقارنة `internal_reference` أو `description` وبلا request hash. | محاولة إنشاء Project مختلف بنفس الاسم والقطاع تحول المستخدم بصمت إلى Project قديم؛ خطر إدخال بيانات في Project خاطئ. | Project identity، onboarding، auditability. | استخدام idempotency key + request hash. الاسم المتكرر إما يُسمح به مع internal reference فريد أو يُرفض صراحة؛ لا يرجع record قديمًا ببيانات مختلفة. |
| AUD-06 | عيب مؤكد | **High** | `getUnpostedContributions()` في `src/features/finance/queries.ts`: مجموعة `reversed` تحتوي `reversal_of_batch_id` (Journal Batch IDs)، ثم تقارنها بـ`batch.source_id` (Contribution ID). النوعان مختلفان. UI نفسها تقول إن المساهمة تعود بعد عكس مرتبط. | بعد عكس contribution cash attribution قد تظل المساهمة مخفية من قائمة إعادة الإسناد. correction journey لا يعمل كما تصفه الواجهة. | Funding/Cash correction. | إصلاح read model/query ليقارن reversal بالـoriginal batch ID، وإضافة behavioral DB/query test. الآلية حاليًا policy-gated لكنها يجب أن تكون صحيحة قبل التفعيل. |
| AUD-07 | خطر مرجح | **High** | uploads تقبل `File.type` فقط في `src/features/procurement/actions.ts` وStorage metadata. لا magic-byte validation، quarantine، malware scan، أو Content-Disposition policy. `docs/decisions/0031...` نفسه يؤجل malware/retention إلى production hardening. الملفات يصل إليها باقي الأعضاء عبر signed URLs. | عضو مخترق أو ملف مورد ضار قد ينشر PDF/image خبيثًا لفريق المنظمة. | Security، Procurement evidence، user devices. | قبل production: فحص magic bytes، تنزيل كـattachment، quarantine status، وحد أدنى malware scan. اختيار خدمة مدفوعة يحتاج موافقة المالك. |
| AUD-08 | مجهول/مانع إصدار | **High** | لا توجد أدلة repository على monitoring/APM، health endpoint، alerts، log drain، production backup schedule، restore فعلي، post-deploy smoke، quotas/cost alerts، أو named on-call owners. checklist ما زالت pending. | outage أو data issue قد يظل غير مكتشف؛ recovery time/cost غير معروف. | Operations، production readiness. | لا إطلاق حقيقي قبل staging runbook: monitoring، alerts، backup schedule، restore إلى DB جديدة، post-deploy smoke، ومسؤولين مسمين. |
| AUD-09 | توصية / قيد مؤكد | **High** | `npm run r15:admission` أعاد `BLOCKED`, exit 1؛ كل `BD-001…BD-012` ما زالت `OPEN`. Migration `20260816062000_pre_owner_policy_safety.sql` تقفل investor economics. | أي محاولة لتفعيل ownership/allocation/distribution الآن قد تخترع حقوقًا مالية وقانونية غير معتمدة. | Investor economics، legal/accounting، R15–R17. | لا “إصلاح” تقني. يلزم قرار المالك والأدلة والمراجعة القانونية/المحاسبية حسب `docs/OPEN_BUSINESS_DECISIONS.md`. |
| AUD-10 | عيب مؤكد | **Medium** | `create_organization`, `create_party`, `add_project_participant`, و`activate_agreement_version` لا تملك idempotency keys/receipts. الدليل: actions وRPC signatures الحالية. | response loss يمكن أن ينشئ Organization/Party مكررًا أو يجعل retry يظهر فشلًا رغم نجاح العملية. | Onboarding، Terms، reliability. | إضافة command key + request hash + replay receipt لكل command؛ البدء بـOrganization وagreement activation. |
| AUD-11 | عيب مؤكد | **Medium** | Home يربط `/projects` في `src/app/(app)/page.tsx` لكن production build لا يحتوي route `/projects`. | زر “كل المشاريع” وKPI ينتهيان إلى 404 للمستخدم المسجل. | Home، navigation. | إنشاء list route بسيط أو توجيه الروابط إلى `/` إن كانت Home هي القائمة المعتمدة؛ أضف link integrity test. |
| AUD-12 | عيب مؤكد | **Medium** | Global `/intake` يرسل كل Projects، بما فيها Agriculture/Livestock، إلى `/projects/[id]/intake`. هذه الصفحة تجمع Real Estate profile/assets/parcels/budgets وتعرض نصًا عقاريًا. كما أن صفحات كثيرة تختار `organizations[0]` ولا يوجد Organization switcher. | رحلة القطاع قد تعرض متطلبات غير مناسبة، والمستخدم متعدد المنظمات قد يعمل على منظمة غير التي يقصدها. | Guided intake، multi-org UX، sector consistency. | اجعل intake sector-aware، وأضف active Organization selection واضحًا محفوظًا في session/URL، دون تغيير tenant authority. |
| AUD-13 | عيب مؤكد | **Medium** | Project lifecycle في DB هو فعليًا `DRAFT | FUNDING` فقط؛ لا command عام لـ`DUE_DILIGENCE | ACTIVE | EXITING | CLOSED | CANCELLED` المذكورة في canonical journey. | تقارير وحالات Project لا تعبر دورة الاستثمار كاملة حتى لو كانت sector objects تملك lifecycles. | Product completeness، reporting. | إما توثيق النطاق الحالي بصدق، أو اعتماد وتنفيذ state machine مستقل في slice لاحقة؛ لا تستنتج transitions من sector state. |
| AUD-14 | عيب مؤكد | **Medium** | permission UI غير متسقة: `TermsPage` يعرض `ActivateVersionButton` لكل عضو رغم أن DB تتطلب OWNER؛ `FundingPage` لا يقرأ membership ويعرض Capital Call form لكل عضو رغم OWNER requirement. | المستخدم يرى إجراءً متاحًا ثم يحصل على رفض غامض؛ يزيد الدعم ومحاولات retry. | Terms/Funding UX، authorization. | جلب membership وإخفاء/تعطيل owner-only controls مع شرح، مع بقاء DB هي السلطة النهائية. |
| AUD-15 | خطر مرجح | **Medium** | صفحات القطاع تطلب datasets كاملة بلا pagination/limit. Agriculture تنفذ 27 call إجمالًا، Intake تنفذ 25 call في أول `Promise.all` ثم calls إضافية، Livestock 23 إجمالًا، Operations تنفذ 22 data call إضافة إلى auth، وProcurement تنفذ 17 call بعد Project. الدليل: `Promise.all` في صفحاتها. | latency مرتفع، ضغط PostgREST/DB، وquota/cost أكبر مع تاريخ طويل. | Performance، Supabase cost، low-end/mobile. | إضافة project workspace aggregate read models أو عدد أقل من RPC/read calls، pagination و“latest N” مع drill-down منفصل. قِس قبل/بعد. |
| AUD-16 | عيب مؤكد | **Medium** | N+1 متسلسل: `cash/page.tsx:50-54` يستدعي `getLedgerForBatch` لكل payment؛ `costs/page.tsx:102-108` يستدعي `getLedgerForObligation` لكل obligation. | زمن الصفحة ينمو خطيًا بعدد المعاملات، وكل call ينتظر السابق. | Cash/Costs performance. | query واحدة بـ`.in(...)` أو read model يجلب كل traces المطلوبة دفعة واحدة. |
| AUD-17 | عيب مؤكد | **Medium** | client routes تستورد constants من Zod schema modules. أكبر chunk `3szwarg70504l.js` حجمه 283,405 bytes غير مضغوط ويحتوي Zod. Route-specific client total بلغ تقريبًا 302 KiB لـ`/projects/new`، 369 KiB Agriculture، 359 KiB Livestock، 387 KiB Intake، فوق shared framework chunks. | تحميل/parse أكبر على شبكة وهاتف ضعيف، خصوصًا field users. | Bundles، mobile performance. | انقل enums/constants الخفيفة إلى modules بلا Zod، واجعل validation schemas server-only حيث يمكن؛ أضف bundle budget. |
| AUD-18 | عيب مؤكد | **Medium** | لا توجد security headers مخصصة في `next.config.ts`/Vercel. smoke المحلي لـ`/login` لم يعرض CSP، `frame-ancestors`/`X-Frame-Options`, `X-Content-Type-Options`, Referrer-Policy أو Permissions-Policy، وأظهر `X-Powered-By`. | clickjacking والدفاع ضد content-sniffing/XSS أقل من المطلوب لتطبيق مالي. | Web security، deployment. | أضف headers تدريجيًا؛ ابدأ `frame-ancestors 'none'`, `nosniff`, referrer/permissions، ثم CSP report-only قبل enforcement. |
| AUD-19 | خطر مرجح | **Medium** | checksum evidence يحسبها Server Action، لكن `register_procurement_evidence` callable مباشرة من role `authenticated` ويثق في `p_sha256`; DB تتحقق من size/MIME metadata فقط ولا تتحقق من bytes. | caller مباشر يمكنه تسجيل checksum لا يطابق الملف؛ audit يعرض SHA كأنه حقيقة. | Evidence integrity، audit. | اجعل registration غير callable من browser مباشرة أو تحقق checksum عبر trusted server/storage process؛ أضف download-and-rehash verification في audit path. |
| AUD-20 | عيب مؤكد | **Medium** | 38 من 52 Vitest files تقرأ source/migration text عبر `readFileSync`. لا Playwright/Cypress، لا authenticated browser smoke، لا automated accessibility، لا visual regression، ولا coverage threshold. | 714 test قد تعطي ثقة أكبر من الحقيقة؛ broken `/projects` وunreachable Livestock route لم تفشلا الاختبارات. | QA، release confidence. | أضف 5–8 E2E journeys حرجة، link/navigation test، axe smoke، وحد أدنى coverage للـbusiness parsers. لا تستبدل DB tests القوية. |
| AUD-21 | عيب مؤكد | **Medium** | dynamic Procurement table inputs في `LinesEditor`, `ReceiptForm`, `SupplierInvoiceForm` بلا `label`, `name` أو `aria-label`; table headers وحدها لا تمنح دائمًا accessible name للـform control. لا توجد accessibility gate. | مستخدم قارئ الشاشة لا يعرف وظيفة الحقل أو السطر. | Accessibility، Procurement. | أضف `aria-label` يتضمن الصنف ورقم السطر أو `<label>` مرتبطًا، ثم axe/component test. |
| AUD-22 | عيب مؤكد | **Medium** | لا يوجد dialog/confirmation واحد (`<dialog>` و`role="dialog"` = 0). إلغاء membership، حذف draft budget/obligation، وعكس القيود تعتمد على زر مباشر؛ بعضها يطلب reason لكنه لا يعرض confirmation consequence. | accidental destructive/reversal actions، خصوصًا على الهاتف. | UX safety، access، finance. | confirmation step صغير يذكر object والنتيجة، مع focus management؛ DB reversal/last-owner guards تبقى كما هي. |
| AUD-23 | توصية/نقص مؤكد | **Medium** | لا manifest، icons، service worker، install flow، offline fallback، cache/update policy أو IndexedDB. Canonical architecture يصرح أن PWA/offline deferred. | field users بلا اتصال لا يستطيعون حفظ draft، ولا توجد installability. | PWA، Agriculture/Livestock field UX. | لا تضف cache عامًا الآن. بعد اعتماد الحاجة، صمم offline drafts non-financial فقط، ولا تخزن صفحات/بيانات auth المالية في shared caches. |
| AUD-24 | خطر مرجح | **Medium** | `.env.production` tracked ويحتوي Supabase URL وpublishable key غير سريين، وNext يعلن تحميله في build. لا environment marker أو staging matrix. Pilot workflow لديه default project ref. | developer قد يشغل local app على مشروع مشترك دون قصد؛ apply workflow قد يستهدف default عند اختيار apply يدويًا. | Environment separation، privacy، operations. | اترك publishable values إن كان ذلك قرارًا مقصودًا، لكن أضف explicit environment banner/guard، staging project، وrequire typed confirmation للـproject ref عند apply. |
| AUD-25 | خطر مرجح | **Medium** | لا توجد سياسة retention/deletion/legal hold منفذة للملفات أو البيانات الشخصية. evidence metadata/objects append-only و`ON DELETE RESTRICT`; parties، tax numbers، user IDs، health facts تبقى بلا lifecycle. الوثائق تقول إن retention ما زالت concern قبل production. | تكلفة تخزين متصاعدة، وصعوبة تنفيذ متطلبات تعاقدية/خصوصية لاحقة. | Privacy، Storage، data lifecycle، operations. | قرار owner/legal أولًا: retention classes، legal hold، export، offboarding، وما الذي لا يجوز حذفه. ثم commands مؤمنة، لا SQL يدوي. |
| AUD-26 | عيب مؤكد | **Medium** | لا توجد generated Supabase DB types. queries تعتمد 23 `as unknown as` casts؛ TypeScript لا يثبت أن view columns/statuses تطابق migrations. | schema drift قد يمر build ثم يفشل runtime أو يعطي شكل بيانات خاطئ. | Code health، correctness. | توليد types من schema في CI أو تعريف typed database contract، وإزالة casts تدريجيًا. |
| AUD-27 | عيب مؤكد | **Medium** | `currencyDecimals()` في `src/shared/money/index.ts` يعيد `2` لأي currency غير معروفة رغم تعليق يقول إن العملة المجهولة لا تعامل بصمت كـ2. | عند توسعة العملات قد تُفسر عملة ذات 0/3 decimals بشكل خاطئ. | Money input/formatting، FX expansion. | fail closed للعملة غير المسجلة، أو registry ISO مع scale مثبت؛ أضف test لعملة مجهولة. |
| AUD-28 | عيب مؤكد | **Medium** | `scripts/demo/seed_real_estate_showcase.sql` ينفذ `attach_contribution_cash` وS5 allocation/distribution لكنه لا ينشئ approved `policy_authority`. schema الحالية تبدأ registry فارغة وتمنع هذه الأوامر. | seed الموصوف بأنه idempotent/re-runnable يفشل على fresh current database أو يشجع bypass للـpolicy gate. | Demo، onboarding، docs، policy safety. | لا تضف fake policy. عدّل demo إلى neutral/company funding facts أو اجعله يعلن بوضوح أنه legacy غير صالح بعد policy gate. |
| AUD-29 | عيب مؤكد | **Medium** | migration prefix `20260814001200` مستخدم لملفين. runner الداخلي يرتب full filename، لكن Supabase CLI التقليدي يعامل timestamp كversion. لا يوجد `supabase/config.toml`. | أداة deployment مختلفة قد تصطدم بالنسخة المكررة أو تطبق ترتيبًا غير متوقع. | Migrations، portability. | وثّق أن custom ledger هو الطريق الوحيد، وأضف CI check يمنع duplicate numeric prefix مستقبلًا؛ لا تعدّل migration مطبقة. |
| AUD-30 | عيب مؤكد | **Medium** | تقارير الحالة متعارضة: `README.md` و`FINAL_DELIVERY_REPORT.md` تصف Procurement/Budget/R13 كغير مكتملة بينما الكود والـlatest roadmap يقولان العكس. UX docs تقول English/PWA/roles أوسع من runtime. | المالك أو المطور قد يختار roadmap خاطئة أو يعلن readiness غير حقيقية. | Documentation، planning، release governance. | ضع banner “historical snapshot” على الملفات القديمة واجعل `PROJECT_STATUS.md`/هذا التدقيق نقطة الحالة الحالية، دون حذف السجل التاريخي. |
| AUD-31 | عيب مؤكد | **Low** | action patterns متكررة: `actions.ts` + `command-actions.ts` في عدة features، وبعض forms على القديم وبعضها على wrapper الجديد. `investors/forms.tsx` وAllocation UI غير موصولين عمدًا، و`src/shared/supabase/browser.ts` بلا importer فعلي. | صيانة أصعب واحتمال أن يصلح مسار ويُنسى آخر. | Code health. | بعد تثبيت tests، وحّد command adapter تدريجيًا؛ لا تحذف policy-inert S5 قبل قرار R14. |
| AUD-32 | توصية | **Low** | dependencies مباشرة بلا استخدام واضح في production source: `tailwindcss`, `@testing-library/user-event`; `@supabase/supabase-js` لا يستورد مباشرة لكنه قد يكون peer/transitive requirement. package لا يثبت npm version في `packageManager`. | install أكبر وبيئات تطوير أقل تكرارًا. | Dependencies/tooling. | تحقق بـlock/peer graph ثم أزل غير المستخدم فقط؛ أضف `packageManager` وNode version file. لا تنفذ major upgrades ضمن إصلاحات أخرى. |
| AUD-33 | عيب مؤكد | **Low** | لا favicon/app icons. `/favicon.ico` أعاد 404. response المحلي يعرض `X-Powered-By: Next.js`. | ثقة/هوية أقل وتسريب تقني بسيط. | UX/branding/security hygiene. | أضف favicon مناسبًا وعطّل powered-by header عند إضافة security headers. |
| AUD-34 | عيب مؤكد | **Low** | CSS عالمي يطبق `width:100%` على كل `input` بما فيها radio/checkbox؛ inline `flexDirection:'row'` على `.stack` لا يعمل لأن `.stack` هي CSS Grid. | controls قد تظهر بمساحات غريبة، وصفوف أزرار الأخطاء تبقى عمودية. | Responsive/UI polish. | خصص text-like inputs فقط، واستخدم class flex صريحًا بدل inline غير فعال؛ اختبر 360px. |

## 5. نقاط قوة مؤكدة يجب الحفاظ عليها

1. **Tenant isolation:** GitHub database job على نفس SHA نجح، ويشغل PostgreSQL 16 مع suites متعددة للـRLS/two-tenant/SECDEF ACL.
2. **Financial invariants:** المال `bigint minor_units`; balanced journal، reversal، period locks، ceilings، request hashes، وatomic RPCs واسعة الاستخدام.
3. **Concurrency:** عدد كبير من `pg_advisory_xact_lock`, `FOR UPDATE`, unique constraints، وshell race tests.
4. **Auditability:** `audit_events` append-only، facts كثيرة immutable، والحذف يتركز في drafts.
5. **Storage boundary:** bucket خاص، 10 MB، MIME allowlist، server-generated object path، signed URLs لـ300 ثانية، وFK تمنع orphaned registered evidence.
6. **XSS/Injection surface:** React escaping مستخدم؛ لا `dangerouslySetInnerHTML`, `eval`, أو raw SQL من التطبيق. Supabase query methods/RPCs مستخدمة بدل بناء SQL من input.
7. **No exposed secret found:** الفحص لم يجد private keys، GitHub tokens، `sb_secret_`, أو DB URLs. `.env.production` يحمل publishable config فقط حسب shape؛ لم تُعرض قيمه.
8. **CI/Runbooks:** replay، forward upgrades، backup rehearsal، incident/runbook set، وmanual fail-closed activation أفضل من المعتاد لمشروع بهذا العمر.
9. **Policy safety:** R15 block حقيقي في script وDB، وليس مجرد نص في README.
10. **RTL basics:** `lang="ar" dir="rtl"`, focus-visible، reduced motion، labels كثيرة، loading/error/empty states في مسارات رئيسية.

## 6. نتائج baseline الفعلية

| الفحص | النتيجة | الملاحظات |
|---|---|---|
| `git status --short --branch` | PASS | clean عند البداية؛ لا تغييرات غير مرتبطة. |
| `git fetch origin --prune` | PASS | الفرع `0 behind / 1 ahead`؛ ahead هو docs commit. |
| `npm ci --no-audit --no-fund` | PASS | 493 packages؛ warning واحد deprecated `whatwg-encoding@3.1.1`. |
| `npm run lint` | PASS | لا ESLint failures. |
| `npm run typecheck` | PASS | TypeScript strict build؛ مع ملاحظة casts في AUD-26. |
| `npm test` | PASS | 52/52 files، 714/714 tests، لا `.skip/.only/.todo`. |
| Production build مع placeholder env | PASS | Next.js 16.3.0؛ 30 routes؛ `/projects` غير موجود. |
| Local production smoke | PARTIAL PASS | `/login` = 200 عربي؛ `/` و`/assets` anonymous = 307 إلى `/login`; `/favicon.ico` = 404. |
| Security response headers | FAIL جزئي | headers الدفاعية المذكورة في AUD-18 غير موجودة محليًا. |
| `npm audit --audit-level=low` | PASS | 0 vulnerabilities معلنة. |
| `npm outdated --long` | INFO | patch/minor/major updates متاحة؛ لا upgrade نُفذ. |
| `npm ls --depth=0` | PASS مع ملاحظة | dependencies محلولة؛ optional platform packages ظهرت `extraneous` في npm output. |
| `npm run db:test` محليًا | UNRESOLVED | exit 2: لا `psql` ولا Docker. لم يُعتبر PASS محليًا. |
| GitHub Greenfield CI run `32032504002` على نفس HEAD | PASS | App، Database، وSonarCloud جميعها PASS. |
| `npm run r15:admission` | BLOCKED كما يجب | exit 1؛ `BD-001…BD-012` OPEN. |
| readiness inventory | PASS | 45/45 artifacts. |
| readiness pack validator | PASS | names/structure/human-gate wording متسقة. |
| credential-pattern scan | PASS محدود | لا secret patterns في tracked snapshot؛ Git history الكامل غير متاح لأن checkout shallow. |
| PWA artifact scan | ABSENT | لا manifest/icons/service worker/offline cache. |
| Optional license query diagnostic | INCONCLUSIVE | `npm query ".license"` غير مدعوم وأعاد `EQUERYNODEPTYPE`; لا حكم license compliance مبني عليه. |

## 7. مراجعة مستويات الاختبار

### الموجود فعليًا

- Unit/schema/exact-money tests.
- React component tests لعدد محدود من forms/idempotency/hydration.
- Source-contract tests كثيرة.
- Behavioral PostgreSQL tests قوية تشمل multi-tenant، concurrency، forward upgrade، backup/restore، R13 synthetic scenario.
- Lint، typecheck، build، SonarCloud.

### الفجوات

- لا authenticated browser E2E.
- لا اختبار Journey كامل من login إلى operation إلى finance إلى close عبر UI.
- لا automated accessibility.
- لا route/link integrity test.
- لا coverage report أو threshold.
- لا load/performance test.
- لا production smoke بعد deploy.
- لا security header test، file malware/magic-byte test، أو session-cookie assertion.
- لا flakiness history/SLA؛ GitHub metadata الأخيرة ناجحة، لكن التاريخ المحلي shallow.

### خطر الثقة الكاذبة

38/52 Vitest files تعتمد على قراءة source/migration text. هذه مفيدة كـarchitecture guards لكنها لا تثبت behavior runtime. مثال واضح: tests كلها نجحت مع وجود رابط `/projects` المكسور ومع route Livestock operations غير الموصول.

## 8. مراجعة Security وPrivacy حسب نوع الهجوم

| المجال | النتيجة |
|---|---|
| Authentication | Supabase SSR + `auth.getUser()` في Proxy/Layout. لا bypass مؤكد. Account recovery/MFA غير منفذين. |
| Authorization | cross-tenant قوي ومختبر؛ intra-tenant least privilege غير كافٍ (`OWNER/MEMBER`). |
| Secrets | لا secret مؤكد؛ publishable URL/key فقط tracked. full-history scan غير ممكن. |
| SQL injection | لا finding مؤكد؛ inputs تمر Zod/RPC وSupabase query builder. Dynamic SQL في migrations يستخدم identifiers ثابتة/`format('%I')`. |
| XSS | لا unsafe React sinks؛ output escaped. Uploaded PDFs/images تظل file risk مستقلًا. |
| CSRF | لا custom REST mutation routes. Server Actions تعتمد حماية Next origin/action protocol؛ لا custom proxy-origin config. لم يُختبر authenticated cross-origin فعليًا. |
| SSRF | لا user-controlled server URL fetch في المنتج. demo admin script يأخذ Supabase URL من trusted environment فقط. |
| File upload | private وsize-limited، لكن content sniffing/malware/checksum authority ناقصة. |
| Webhooks/CORS | لا webhooks ولا custom APIs؛ CORS غير مطبق لأنه لا توجد تلك surfaces. |
| Cookies | managed بواسطة `@supabase/ssr`; flags الفعلية تحتاج live authenticated response ولم يمكن فحصها. |
| Logs/analytics | لا analytics/APM. Audit table قد يحتوي business metadata ومتاح لكل MEMBER داخل المنظمة. |
| Sensitive caches | auth routes dynamic حسب build؛ `/login` static long-cache ولا يحتوي بيانات خاصة. authenticated cache headers لم تُفحص دون session. |
| Clickjacking/headers | لا CSP/frame restriction مخصصة. |
| Privacy retention | لا production retention/deletion/export lifecycle مثبت. |

## 9. مراجعة UX/UI

### الإيجابي

- عربية/RTL فعلية، وليست translation layer سطحية.
- حالات loading/error/empty موجودة في مسارات كبيرة.
- رسائل كثيرة تفرق بين cash/revenue/result/distribution.
- focus-visible وreduced-motion.
- tables لها headers، ومعظم الحقول داخل labels.
- demo/policy blocks موضحة بصدق.

### السلبي

- navigation غير كاملة كما في AUD-04/AUD-11.
- الصفحات القطاعية ضخمة جدًا، خصوصًا Agriculture وLivestock؛ التنقل بالـanchors لا يعوض غياب تقسيم مهام يومية واضحة.
- finance-heavy tables تستخدم horizontal scroll فقط على الهاتف، ولا توجد mobile summary cards لكل table.
- success feedback غير متسق؛ بعض forms تعرض success، وأخرى تعتمد فقط على ظهور row جديد.
- owner-only controls تظهر أحيانًا لغير المالك.
- لا confirmation dialogs أو focus management بعد العمليات الحساسة.
- dynamic inputs غير مسماة في Procurement.
- لا English/LTR implementation رغم قول بعض الوثائق إنه supported.
- لم يُنفذ اختبار 360px/keyboard/screen reader فعلي.

## 10. مراجعة الأداء

### أدلة كمية

- Agriculture page: 27 query function calls.
- Intake page: 25 calls في أول `Promise.all` ثم calls إضافية مشروطة.
- Livestock page: 23 calls إجمالًا.
- Real Estate Operations: 22 data calls إضافة إلى auth.
- Procurement: 17 data calls بعد Project، وsigned URLs لكل evidence row.
- Cash/Costs فيهما N+1 متسلسل.
- معظم read helpers بلا `.limit()` أو pagination.
- route-specific uncompressed chunks: Agriculture ~369 KiB، Livestock ~359 KiB، Intake ~387 KiB، Project New ~302 KiB؛ shared framework chunks إضافية.
- لا images أو custom fonts؛ هذه نقطة إيجابية.

### الحكم

لا توجد load measurements حقيقية، لذلك لا يُدعى وجود outage. لكن النمط الحالي سيتدهور مع تاريخ طويل وسيزيد Supabase requests والـquota cost. يجب القياس على staging ببيانات بحجم واقعي قبل pilot.

## 11. مراجعة PWA

الحالة **غير منفذة بالكامل**:

- manifest: لا يوجد.
- icons/favicon: لا يوجد.
- installability: لا توجد.
- service worker: لا يوجد.
- offline fallback: لا يوجد.
- cache policy/update flow: لا يوجد.
- authenticated data cache safety: غير مطبق لأنه لا يوجد SW.

هذا ليس regression لأن architecture تقول deferred، لكنه يمنع ادعاء offline field readiness. أي PWA مستقبلية يجب ألا cache صفحات مالية أو signed URLs في shared cache.

## 12. مراجعة Operations وDeployment

### الموجود

- Vercel framework declaration بسيط.
- GitHub App/DB CI.
- Manual Supabase activation يفحص الحالة أولًا، يستخدم checksum ledger، ويفشل مغلقًا.
- concurrency group يمنع عمليتي activation متوازيتين لنفس ref.
- PostgreSQL backup/restore rehearsal في الاختبارات.
- runbooks جيدة للحوادث، migration failure، restore، reconciliation، access.

### الناقص أو غير المثبت

- لا App deploy workflow في Git؛ Vercel integration الخارجية مجهولة.
- لا staging/prod config matrix موثقة في code.
- لا environment banner/kill switch/maintenance mode.
- لا metrics، traces، health، alerts، log retention.
- لا backup frequency/retention proof أو restore فعلي.
- لا rollback automation؛ migrations forward-only.
- لا quota/cost budget/alerts لـVercel/Supabase/Storage/Sonar.
- لا named support/on-call owners؛ placeholders موجودة في runbooks.
- لا post-deploy smoke.

## 13. خطة المعالجة ذات الأولوية

### Milestone 0 — تثبيت الأدلة ومنع الاستخدام الخطر

**آمن، لا يغير business behavior:**

1. أعلن `NO-GO` للـproduction الحقيقي وR15.
2. عطّل استخدام أوامر S6 الخمسة في أي pilot حتى إصلاح replay.
3. أضف characterization tests لـAUD-04/05/06/11 قبل الإصلاح.
4. لا تشغل demo seed الحالي على fresh/shared DB.

### Milestone 1 — Reliability + الوصول للرحلات الأساسية

1. مراجعة PR `#164` واختباره في staging؛ migration تحتاج موافقة المالك قبل التطبيق.
2. إصلاح `/projects` link/list.
3. ربط `/livestock/operations` وإظهار Finance/Cash/Close/Pilot/Controls للقطاعات المناسبة.
4. إصلاح `getUnpostedContributions`.
5. إصلاح Project creation idempotency/payload mismatch.
6. إخفاء owner-only actions لغير المالك مع بقاء DB checks.

**Gate:** lint/type/tests/build + full DB replay + new E2E navigation/replay tests.

### Milestone 2 — Team onboarding وleast privilege

يتطلب owner-approved role matrix:

1. Invite/accept/reset flow.
2. Roles/capabilities قابلة للدفاع: Owner، Finance، Operator، Reviewer، Read-only؛ Investor منفصل فقط بعد policy.
3. DB authorization/RLS لكل capability، لا UI فقط.
4. Organization selector واضح.
5. access audit وemergency revoke test.

### Milestone 3 — Browser QA وUX safety

1. Playwright journeys: login، org/project، كل sector landing، procurement/payment، close/retry، access revoke.
2. axe/keyboard/focus tests.
3. labels للـdynamic inputs.
4. confirmation dialogs للـreversal/access/delete drafts.
5. sector-aware intake، success messages، mobile 360px review.

### Milestone 4 — Security وEvidence hardening

1. security headers + CSP report-only.
2. magic-byte/content-disposition/quarantine.
3. trusted checksum verification.
4. retention/legal hold policy ثم implementation.
5. secret/history scan على full Git clone، dependency/Action SHA policies.

### Milestone 5 — Performance وcost control

1. instrument request count/TTFB وDB query timing في staging.
2. aggregate read models/pagination بدل 20+ calls.
3. batch N+1 traces.
4. فصل constants عن Zod schemas وbundle budget.
5. Supabase/Vercel quota and cost alerts.

### Milestone 6 — Production operations gate

1. Staging يطابق production config.
2. migration activation dry-run ثم apply المصرح.
3. scheduled backup + restore إلى DB جديدة.
4. monitoring/alerts/on-call/support names.
5. rollback/cutover rehearsal.
6. post-deploy authenticated smoke.
7. real customer UAT فقط بعد ذلك.

### Milestone 7 — PWA ثم R15 لاحقًا

- PWA/offline تبدأ فقط بعد threat model وfield validation؛ drafts non-financial أولًا.
- R15 يبدأ فقط عندما يصبح `npm run r15:admission` PASS بأدلة حقيقية.

## 14. أمور تحتاج موافقة المالك

1. دمج وتطبيق أي migration، بما فيها S6 replay fix.
2. role/capability matrix ومن يرى cash، bank، parties، evidence، health، audit.
3. team invitation وadmin/support access model.
4. قرارات `BD-001…BD-012` والأدلة القانونية/المحاسبية.
5. retention، legal hold، deletion، offboarding، وdata export policy.
6. اختيار malware scanner أو خدمة مدفوعة.
7. staging/production Supabase/Vercel projects والتكاليف والـquotas.
8. backup frequency، retention، RPO/RTO، ومن يعتمد restore.
9. monitoring/APM provider وخطة الدعم/on-call.
10. هل English/LTR وPWA داخل أول pilot أم بعده.
11. أي وصول إلى production/shared data، أو تشغيل demo seed، أو migration apply.

## 15. مناطق لم يمكن التحقق منها

| المنطقة | لماذا لم تتحقق |
|---|---|
| Authenticated UI journeys | لا يوجد local safe Supabase tenant/user، والسياسة تمنع لمس shared/production دون تفويض. |
| Cookie flags/session expiry | تحتاج authenticated live response وإعدادات Supabase الفعلية. |
| Production deployment SHA | Vercel integration خارج المستودع ولم يُطلب الوصول للإنتاج. |
| Live migration sync | لم نصل إلى Supabase الحقيقي. |
| Production data/RLS behavior | DB CI اصطناعية نجحت، لكن لم تُستخدم بيانات حقيقية. |
| Actual backup schedule/restore | repository يثبت rehearsal فقط، لا تشغيلًا حقيقيًا. |
| Browser/mobile/screen-reader | لا Playwright/Chrome accessibility environment ولا حساب دخول. |
| Load/performance at scale | لا dataset واقعي ولا staging metrics. |
| Malware behavior | لا scanner أو malicious-file sandbox. |
| Historical secret exposure | checkout shallow؛ scan شمل tracked snapshot الحالي فقط. |
| Legal/accounting correctness | تحتاج owner contracts ومحاسب/محامٍ؛ ليست قابلة للاستنتاج من code. |
| Real customer acceptance | UAT/pilot/buyer evidence غير موجودة، والوثائق تصرح بأنها pending. |
| Recurring cost | لا billing/plan/usage data لـSupabase/Vercel/Sonar في المستودع. |

## 16. الخلاصة: أهم خمس نتائج

1. **S6 replay غير آمن بالكامل** في خمسة أوامر حساسة؛ لا تستخدمها في pilot قبل إصلاح مثبت.
2. **الصلاحيات داخل المنظمة واسعة جدًا** بسبب `OWNER | MEMBER` فقط؛ tenant isolation جيد لكن least privilege غير مكتمل.
3. **رحلات أساسية مخفية أو مكسورة**: Livestock operations بلا أي رابط، Finance/Close غير ظاهرين لقطاعين، و`/projects` مفقود.
4. **الاستعداد التشغيلي الحقيقي غير مثبت**: لا monitoring، backup schedule/restore فعلي، authenticated E2E أو post-deploy smoke.
5. **قاعدة البيانات أقوى من طبقة المنتج**؛ الاختبارات النصية الكثيرة والبناء الناجح لا يلتقطان فجوات navigation، accessibility، performance، والحسابات متعددة الأدوار.

### أسلم Milestone أول

ابدأ بـ **Milestone 1 محدود جدًا**: ثبّت tests التي تعيد إنتاج S6/navigation/contribution issues، راجع إصلاح S6 في staging بعد موافقة صريحة على migration، ثم أصلح links والتنقل فقط دون تغيير قواعد مالية أو سياسات مستثمرين. لا يبدأ أي refactor واسع أو R15 في هذه المرحلة.

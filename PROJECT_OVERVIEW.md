# نظرة واقعية على مشروع Terranex

**تاريخ الفحص:** 2026-08-17
**النسخة المفحوصة:** `9488588f0c6fd1984a1c09769af480f85905c661`
**الفرع:** `arena/01a00fc0-terranex`، وكان مطابقًا لـ `origin/main` وقت الفحص (`0 behind / 0 ahead`).
**قاعدة هذا المستند:** الكود، الـ migrations، الاختبارات، إعدادات التشغيل، والبناء الفعلي. الادعاءات التي لم تُشاهد في تشغيل حقيقي مذكورة بوضوح.

## 1. ما هو المنتج؟

Terranex هو تطبيق ويب عربي لإدارة عمليات شركات الاستثمار الخاصة. يرتب البيانات بهذا الشكل:

`Organization → Investment Portfolio → Investment Project → sector facts / finance facts / evidence`

المشروع الواحد ينتمي إلى قطاع أساسي واحد:

- `REAL_ESTATE`: استثمار عقاري.
- `AGRICULTURE`: زراعة ومحاصيل.
- `LIVESTOCK`: ثروة حيوانية.

يوصل المنتج بين العمليات اليومية والمال والرقابة: أصول ودورات تشغيل، موردون ومشتريات، التزامات ومدفوعات، كشف بنك ومطابقة، إيراد وتحصيل، قيود مالية مزدوجة، إغلاق فترات، أدلة، مخاطر، وقرارات.

### الحدود المؤكدة

- ليس سوق استثمار عام، ولا crowdfunding، ولا بنكًا، ولا يحفظ أموال العملاء.
- لا يرسل أموالًا فعليًا؛ يسجل ويعتمد ما تم عبر القنوات البنكية الخارجية.
- ليس دفترًا قانونيًا/ضريبيًا كاملًا ولا ERP عامًا.
- `Portfolio` تجميع إداري وتقارير فوق مشاريع مستقلة، وليس تلقائيًا صندوقًا أو شركة قانونية أو وعاء مستثمرين.
- آليات ملكية المستثمرين وتخصيص الأرباح والتوزيعات موجودة تاريخيًا في قاعدة البيانات، لكنها مقفلة بسياسة fail-closed حاليًا. القرارات `BD-001` إلى `BD-012` كلها `OPEN`.

## 2. المستخدمون والأدوار

### ما تقترحه وثائق المنتج

الوثائق تصف Owner، Investment Manager، Finance Officer، Sector Manager، Reviewer، Investor، وAuditor.

### ما ينفذه النظام حاليًا

العضوية الفعلية داخل `memberships.role` لها قيمتان فقط:

| الدور الفعلي | الصلاحية العامة |
|---|---|
| `OWNER` | قراءة المنظمة كلها، تنفيذ الأعمال العادية، والموافقات الحساسة المحجوزة للمالك. كثير من الموافقات تمنع الشخص نفسه من الإعداد والاعتماد. |
| `MEMBER` | قراءة بيانات المنظمة كلها وتنفيذ أعمال تشغيلية كثيرة، دون صلاحيات المالك الحساسة. |

`project_participants.role = INVESTOR` هو وصف لطرف داخل مشروع، وليس حساب دخول بدور Investor مستقل. لا توجد حاليًا صلاحية investor self-scope أو بوابة مستثمر منفصلة.

### حدود الوصول المؤكدة

- كل الصفحات عدا `/login` تمر عبر `src/proxy.ts` وتتطلب Supabase Auth session.
- RLS يعزل البيانات على مستوى `organization_id` وعضوية `ACTIVE`.
- العضو النشط يستطيع عادة قراءة كل بيانات منظمته؛ لا يوجد نطاق قراءة مختلف لكل Project في نموذج العضوية الحالي.
- أوامر قاعدة البيانات تستخرج المستخدم من `auth.uid()`، ولا تثق في هوية يرسلها المتصفح.
- أوامر مادية كثيرة تتطلب `OWNER` و/أو maker-checker.

## 3. الرحلات الأساسية الموجودة

1. تسجيل الدخول بحساب موجود، ثم تسجيل الخروج.
2. إنشاء Organization؛ المنشئ يصبح `OWNER`.
3. إنشاء Portfolio وتعديله، نقله بين `DRAFT | ACTIVE | ARCHIVED`، وإسناد/إزالة/نقل Projects مع سجل تاريخي.
4. إنشاء Project واختيار القطاع؛ العملة الابتدائية/الفعلية للمشروع هي EGP، والحالة تبدأ `DRAFT`.
5. فتح مساحة القطاع وتنفيذ عمليات Real Estate أو Agriculture أو Livestock.
6. تعريف أطراف وموردين، ثم طلب شراء → أمر شراء → استلام → فاتورة مورد → مقترح دفع → اعتماد/تسجيل → مطابقة بنكية.
7. إنشاء التزام مالي، اعتماده، دفع جزء/كل المبلغ، وعكس القيد عند التصحيح.
8. إنشاء موازنة، اعتمادها، عرض الاستهلاك و`FAC`، وإدارة الاستثناءات.
9. تسجيل إيراد/بيع/إيجار أو إنتاج زراعي/حيواني، ثم تحصيله ومطابقته.
10. فتح فترة محاسبية، تشغيل بوابات الإغلاق، اعتماد الإغلاق، وطلب/اعتماد/تنفيذ تصحيح.
11. إدخال أرصدة افتتاحية، التحقق منها، مطابقة نقاط رقابية، تسجيل UAT/rehearsals، وإدارة حالة العضوية.
12. عرض Home وPortfolio وAssets وProject read models مع drill-down إلى الحقائق.
13. عرض هوية المشاركين ونسخة الاتفاقية فقط؛ أرقام entitlement/allocation/distribution محجوبة حتى اعتماد السياسة.

## 4. قائمة الصفحات والمسارات الكاملة

أثبت `next build` وجود **30 route**. كل المسارات التالية محمية عدا `/login`.

| Route | الوظيفة الحالية | ملاحظات |
|---|---|---|
| `/login` | تسجيل الدخول بالبريد وكلمة المرور | لا يوجد sign-up أو reset password أو MFA. |
| `/` | Home تنفيذية: Projects، Portfolios، Assets، نتائج قطاعات، تجميع مالي، إشارات نزاهة | تستخدم أول Organization متاح للمستخدم. |
| `/onboarding` | إنشاء Organization | لا يوجد تعديل/حذف Organization في UI. |
| `/intake` | نقطة بدء إدخال مشروع | نصها ما زال عقاريًا/تجريبيًا في أجزاء منه رغم دعم 3 قطاعات. |
| `/assets` | سجل أصول cross-sector وأداء القطاعات | قراءة مشتقة؛ لا يوجد Universal Asset table للكتابة. |
| `/portfolios` | قائمة المحافظ | إنشاء/فتح Portfolio. |
| `/portfolios/new` | إنشاء Portfolio | manager اختياري من أعضاء المنظمة. |
| `/portfolios/[portfolioId]` | تفاصيل Portfolio، roll-up، lifecycle، المشاريع الحالية والتاريخية | يدعم assign/remove/move. |
| `/projects/new` | إنشاء Project واختيار القطاع | `REAL_ESTATE | AGRICULTURE | LIVESTOCK`. |
| `/projects/[projectId]` | قشرة Project وملخص نقد/نتيجة/فترة وروابط مساحة العمل | تعرض وقائع مساهمات مسجلة دون اعتبارها entitlement. |
| `/projects/[projectId]/overview` | ملخص Real Estate | يعيد Agriculture وLivestock إلى مساحة قطاعهما. |
| `/projects/[projectId]/operations` | Real Estate operations | profile، assets، parcels، acquisition/control، phases، milestones، budget، valuation، disposal، sale. |
| `/projects/[projectId]/revenue` | إيراد وبيع وتحصيل | يتضمن rental flow للعقار. |
| `/projects/[projectId]/agriculture` | مساحة الزراعة الكاملة | land، farm، field، crop cycle، activity، input، harvest، inventory، sale، result، closeout. |
| `/projects/[projectId]/livestock` | المواقع والقطعان والدفعات والحركة والوزن والشراء/البيع والنتيجة والإقفال | Cohort-first. |
| `/projects/[projectId]/livestock/operations` | عمليات حيوانية تفصيلية | Animal identity اختياري، صحة/دواء، تكاثر، علف، `FCR`. |
| `/projects/[projectId]/procurement` | المشتريات المشتركة | Supplier، PR، PO، receipt، invoice، evidence، payment proposal. |
| `/projects/[projectId]/budget` | الموازنة والحدود والاستهلاك و`FAC` | draft/approve/supersede/delete draft. |
| `/projects/[projectId]/costs` | الالتزامات وشروطها وجدولها ونزاعاتها وحجز الضمان والدفع | يعرض journal trace وaudit. |
| `/projects/[projectId]/cash` | حسابات النقد والبنك والمدفوعات وكشف البنك والمطابقة والعكس | CSV يُدخل كنص داخل نموذج. |
| `/projects/[projectId]/funding` | capital calls والمساهمات المسجلة | الجزء الاقتصادي/الترحيل الرأسمالي مقفول حتى Policy activation. |
| `/projects/[projectId]/terms` | الأطراف والمشاركون ومسودات/تفعيل الاتفاقية | التفعيل وإصدار call رُفعا إلى `OWNER`. |
| `/projects/[projectId]/close` | الفترات، close runs، gates، exceptions، snapshots، corrections، reopen | توجد مشكلة replay معروفة موضحة في `PROJECT_STATUS.md`. |
| `/projects/[projectId]/integrity` | الوضع المالي، إشارات النزاهة، سياسات الموافقة، الاستثناءات، FX، tax registry | يسجل treatment/FX facts؛ لا يحسب ضريبة قانونية كاملة. |
| `/projects/[projectId]/governance` | مخاطر Project وقرارات غير قابلة للتعديل | resolution وevidence references. |
| `/projects/[projectId]/intake` | guided intake/readiness | declarations، evidence، gaps، opening position، checks. |
| `/projects/[projectId]/pilot` | opening import، reconciliation، UAT، rehearsals، access recovery | يفرق بين الدليل التقني ودليل العميل الحقيقي. |
| `/projects/[projectId]/controls` | لوحة الرقابة والجاهزية | تعرض الدور، technical gates، real-world gates، الأعضاء. |
| `/projects/[projectId]/investors` | شفافية المشاركين الآمنة | identity/agreement فقط؛ Policy Blocked ظاهر. |
| `/projects/[projectId]/statements` | لا تعرض statement | redirect إلى `/investors`. |

### عيب route مؤكد

الكود يضع روابط إلى `/projects` في Home، لكن build لا يحتوي route بهذا الاسم. المستخدم غير المسجل يُحوّل أولًا إلى `/login`؛ أما المستخدم المسجل فسيصل إلى 404. التنقل العلوي يستخدم `/` للمشاريع، لذلك العيب محدود ببعض روابط “كل المشاريع” وKPI.

## 5. قائمة الميزات حسب النظام

### الهوية والتنظيم

- Supabase email/password sign-in، session cookies، sign-out.
- Organization creation وعضوية `OWNER` تلقائية.
- تفعيل/تعطيل العضوية، مع حماية آخر Owner نشط.
- لا يوجد تسجيل عام، دعوات، password recovery، MFA، profile management، أو account deletion.
- لا يوجد Organization switcher؛ الصفحات الرئيسية تختار `organizations[0]`.

### Portfolio وProject والإدارة

- Portfolio identity/purpose/manager/lifecycle.
- Project membership history داخل Portfolio؛ Project واحد له parent حالي واحد.
- Project creation لثلاثة قطاعات.
- Cross-sector asset register وsector performance كـ read projections.
- Risks، resolutions، immutable decisions.
- Project lifecycle العام المنفذ فعليًا فقط `DRAFT | FUNDING`؛ lifecycle الكامل المذكور في وثائق المنتج غير منفذ كحالات Project عامة.

### Finance وControl

- exact money في `bigint minor units`، وقيود double-entry.
- semantic accounts، cash accounts، obligations، journal batches/lines.
- payment proposals/payments، bank statement imports، reconciliation/void/reversal.
- accounting periods، close runs/gates/exceptions/snapshots، corrections.
- budgets، commitments، due/aging، retention، disputes، approval policies/exceptions/signoffs.
- FX snapshots/conversion logs وOrganization reporting currency.
- tax treatment registry فقط، وليس tax engine.
- Project/Portfolio/Organization roll-ups، financial integrity signals.

### Funding والمشاركون

- Parties، project participants، agreements/versions، commitment terms، capital calls، contributions.
- آليات S5 allocation/distribution موجودة في schema/code لكنها policy-inert؛ UI forms غير موصولة بالصفحة الحالية، وDB يرفض الكتابة بدون `policy_authority` معتمد.
- `policy_authority` يبدأ فارغًا؛ لا توجد سياسة مستثمرين معتمدة في المستودع.

### Procurement والأدلة

- Suppliers وربط Supplier بـ Party.
- Purchase Requests/Orders/lines، submit/approve.
- Receiving، supplier invoices، acceptances/exceptions.
- Payable/payment linkage إلى Finance Core.
- Private Supabase Storage bucket اسمه `procurement-evidence`، versioned metadata، typed links، checksum، signed read URL، approval evidence gates.
- لا يوجد Document Center عام خارج نطاق Procurement.

### Real Estate

- Project profile والاستراتيجية.
- Property assets، parcels، acquisition، control/title/permit/inspection records.
- Development phases/milestones، property budgets، cost classification، valuations.
- Disposition، control transfer، sale recognition، carrying cost، collections، bank reconciliation، realized result.
- Basic rental recognition → receivable → collection → reconciliation.
- لا يوجد full lease/property management: tenants lifecycle، maintenance، service charges، facilities غير موجودة.

### Agriculture

- Agriculture profile، land asset/control basis، farm، field، crop cycle وfield allocation.
- Field activities، input items/lots/applications.
- Harvest events/lots، storage locations، inventory movements/transfer/adjustment/spoilage.
- Sale approval، physical issue، revenue recognition، collection، lot traceability.
- Authoritative cost attribution، cycle result، integrity issues، closeout.
- لا يوجد valuation مخزون زراعي مخمّن أو تصنيع غذائي.

### Livestock

- Project profile، sites، herds، cohorts، initial placement، lifecycle.
- Movements، quantity events، birth/mortality، split/merge lineage، weights.
- Optional individual animals، medicine/vaccine references، health events، reproduction.
- Feed items/issues وFCR عند كفاية البيانات.
- Purchases، sales، approval/recognition/collection، cost attribution، cohort result/closeout.
- لا يوجد IoT/RFID integration فعلي؛ `RFID` مجرد identifier type.

### Intake، Pilot، والتشغيل

- Readiness declarations، section applicability، modelling gaps، evidence records.
- Controlled opening import ومراجعة/اعتماد ورفض.
- Reconciliation checkpoints/exceptions، UAT tasks، technical rehearsals، access recovery.
- Runbooks للنسخ والاستعادة، الحوادث، فشل migration، الأخطاء المالية، والمطابقة.
- Synthetic demo seed موجود كأداة يدوية، وليس seed تلقائيًا.

## 6. أشياء غير موجودة في المنتج الحالي

- لا REST/GraphQL API خاص بالتطبيق ولا Next Route Handlers.
- لا jobs، queues، cron، webhooks، background workers، أو event outbox.
- لا email/SMS/WhatsApp delivery، ولا notification subsystem رغم ذكره في بعض الخطط.
- لا payment gateway أو bank API؛ التسجيل يدوي/CSV.
- لا analytics، maps، AI، accounting adapter، ETA e-invoice adapter، أو public API.
- لا PWA manifest، icons، service worker، install flow، offline cache، أو offline sync.
- لا English locale أو i18n framework؛ الواجهة الحالية عربية فقط مع `lang="ar" dir="rtl"`.
- لا billing/plans، support admin console، أو production monitoring داخل الكود.

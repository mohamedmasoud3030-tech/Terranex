# خطة الإكمال السريع — Terranex إلى نظام تشغيل يومي فعلي
**تاريخ:** 2 أغسطس 2026
**الهدف:** بأقل وقت وجهد (مستخدم واحد يعمل بمساعدة AI فقط)، تحويل Terranex إلى نظام مُعتمَد فعلاً داخل الشركة، باستخدام مكتبات ومكونات مفتوحة المصدر مثبتة ومُختبرة بدل إعادة اختراع أي شيء.
**القاعدة الذهبية:** **لا نُعيد بناء شيء موجود.** كل ما يمكن جلبه من npm كمكتبة أو نسخه كمكوّن React من مشروع MIT مفتوح المصدر — نأخذه مباشرة.

---

## 0. الفلسفة — اقرأها قبل أي سطر كود

### ما الذي نأخذه جاهزاً (npm install)؟
المحركات الرياضية والمكتبات التي لا مجال للخطأ فيها:
- التحقق من صحة التواريخ (تقويم حقيقي)
- العمليات المالية بدون أخطاء float
- توليد PDF عربي RTL
- جداول البيانات القابلة للفرز/الفلترة
- دعم التقويم الهجري (مستقبلاً)
- إرسال البريد الإلكتروني
- التشفير والتوقيع الرقمي للفواتير

### ما ننسخه ككود (copy-paste MIT components)؟
الـ UI components والمخططات التي تحتاج RTL/tailwind/shadcn متوافق مع واجهتنا:
- قوالب الفواتير
- الـ DataTable القوية (faceted filters, sorting, pagination)
- بطاقات الـ Dashboard المالية
- صفحة تسجيل الدخول الأنيقة

### ما نبنيه بأنفسنا (وبعناية)؟
المنطق المالي الخاص بـ Terranex (وهو أقوى ما عندك أصلاً):
- **نواصل البناء على النواة الموجودة** (Profitability + Settlement + Ownership + Distributions) — لا نلمسها.
- نضيف طبقات جديدة جنباً إلى جنب معها، لا نستبدلها.
- أي migration جديد تُكتب بأسلوب الـ migrations الموجودة (مع rollback، مع RLS، مع guards).

### ما الذي لن نفعله أبداً في هذه المرحلة؟
- ❌ لن نـ fork مشروعاً كاملاً (ERPNext/Odoo) ونحاول دمجه (عشرات الآلاف من الملفات، مستحيل لشخص واحد)
- ❌ لن نبني قيد مزدوج كامل ERP من الصفر (هذا سنة عمل على الأقل)
- ❌ لن نضيف AI/ML/تنبؤات قبل أن تكتمل الأساسيات
- ❌ لن نترجم للغة الإنجليزية قبل أن يكون النظام مُستخدَماً عربياً 6 أشهر
- ❌ لن نبني mobile app أصلي (PWA تكفي)

### الحل الذكي للمحاسبة: **"القيد المزدوج المُبسَّط التلقائي"**
بدلاً من بناء ERP محاسبي كامل أو توريط نفسك بـ fork لـ ERPNext، سنستخدم حلاً وسطاً:
> **نُنشئ دفتر أستاذ مُبسَّط (Mini Ledger) مكوّن من 4 جداول فقط، ويُغذَّى تلقائياً من العمليات الحالية (المعاملات، التسويات، التوزيعات) عبر RPCs الذرية الموجودة. المستخدم لا يرى كلمة "قيد" أو "دفتر أستاذ" في الواجهة — لكن تحت الغطاء كل عملية مالية تُسجَّل كقيد مزدوج متوازن رياضياً. هذا يعطينا:**
> 1. توازن الدفاتر تلقائياً (لا يمكن أن يختفي مبلغ)
> 2. إمكانية إصدار قائمة دخل وميزانية عمومية
> 3. حسابات بنكية حقيقية
> 4. عدم إجبار المستخدم على تعلم المحاسبة
>
> يُمكن لاحقاً (بعد سنة) إما توسيع هذا الدفتر إلى نظام محاسبة كامل، أو الربط بـ ERPNext/نظام محاسبي خارجي لمن أراد — دون أن نخسر أي بيانات.

---

## 1. المكتبات التي سنضيفها (npm install) — جاهزة 100%

هذه كلها مكتبات ناضجة وMIT/ISC license ومستخدمة في عشرات آلاف المشاريع.

### 1.1 المال والعملات — بدلاً من `number` الخام في كل مكان

| المكتبة | الإصدار | لماذا؟ | الجهد المطلوب |
|---|---|---|---|
| **`dinero.js` v2** | أحدث | تتعامل مع المال كـ integer (cents/subunits)، لا floating point errors، تدعم 166 عملة، TypeScript-safe، تمنع إضافة USD إلى EUR خطأ في compile time، 8 دوال تقريب مختلفة، تدعم العملات بلا كسور (JPY) وبـ 3 كسور (OMR/KWD/BHD/TND). بدلاً من تخزين `amount: number` ونرى أخطاء `0.1 + 0.2 !== 0.3` للأبد. | يومان — نغلفها في `core/lib/money.ts` ونحوّل جميع حسابات الـ profitability إليها. |

**الأثر:** يحذف 90% من أخطاء التقريب، ويجعل التعامل مع OMR (3 منازل) و KWD آمناً.

### 1.2 التواريخ الحقيقية — إصلاح ثغرة "2026-02-30"

| المكتبة | لماذا؟ | الجهد |
|---|---|---|
| **لا حاجة لمكتبة إضافية** — الدالة `toDateOnly()` موجودة فعلاً في `core/lib/dateOnly.ts` ومُختبرة | نربطها في Zod `.superRefine` لكل schemas الـ 6 التي تقبل تاريخاً. **استخدم الموجود.** | نصف يوم |
| `@daypicker/react` + `@daypicker/hijri` (لاحقاً) | Date picker احترافي مع دعم Hijri/Um AlQura للأسواق الخليجية عندما نحتاجه | في المرحلة 2 فقط |

### 1.3 جدول البيانات — لصفحات المعاملات/الذمم/الشركاء

| المكتبة | الإصدار | لماذا؟ | الجهد |
|---|---|---|---|
| **`@tanstack/react-table` v8** (موجود كـ dep لكن غير مستخدم — نفّعله) | الحالي الموجود في package.json | الحل المعياري في React ecosystem. sorting, filtering, faceted filters, pagination, column visibility, row selection. | 3 أيام |
| انسخ **مكوّن DataTable جاهز من shadcn/ui** (MIT) — يأتي مع: sorting، faceted filters، view options، row actions، pagination — كاملاً كـ copy-paste من صفحة shadcn الرسمية. | — | مبني فوق @tanstack/react-table، متوافق 100% مع Tailwind/shadcn/Radix المستخدمة فعلاً عندك. | يوم واحد لنقل المكونات |

**طريقة النقل:**
1. اذهب لـ https://ui.shadcn.com/docs/components/data-table
2. انسخ الملفات التالية إلى `src/components/ui/data-table/`:
   - `data-table.tsx`
   - `data-table-column-header.tsx`
   - `data-table-faceted-filter.tsx`
   - `data-table-pagination.tsx`
   - `data-table-toolbar.tsx`
   - `data-table-view-options.tsx`
   - `data-table-row-actions.tsx`
3. استخدمها مباشرة في صفحات المعاملات والذمم.

**مرجع أفضل (جاهز 100% بكل المميزات):** انسخ من مشروع [openstatusHQ/data-table-filters](https://github.com/openstatusHQ/data-table-filters) (MIT) — فيه faceted filters، URL state (nuqs)، infinite scroll — مبني على نفس المجموعة. لا تحتاج إضافة nuqs إلا إذا أردت URL-filters قابلة للمشاركة.

### 1.4 PDF عربي — تقارير وفواتير

| المكتبة | لماذا؟ | الجهد |
|---|---|---|
| **`@react-pdf/renderer`** | أفضل حل server-side-rendered PDF في React. | موجود بالفعل في مشروعك (أو أضف فقط يومان) |
| **`@bendanziger/react-pdf-rtl`** (مكتبة جديدة 2026) | يُصلح مشكلة الـ RTL/Arabic shaping الموجودة في @react-pdf/renderer منذ 2019 | نصف يوم |
| خط **Noto Sans Arabic Regular + Bold** | من Google Fonts (SIL Open Font License، مجاني) — أفضل خط عربي للـ PDF (ligatures كاملة) | ربع يوم — ضعه في `/public/fonts/` |

### 1.5 الفواتير — قوالب جاهزة

الحل: **نسّخ قالب فاتورة من مشروع `invoify` (MIT)** وعدّله للعربية.

المشروع: **github.com/al1abb/invoify** (2,172 commits، MIT license، نفس الـ stack: React + TypeScript + Tailwind + shadcn/ui + RHF + Zod + Puppeteer PDF).

**طريقة النقل:**
1. انسخ مجلد قوالب الفواتير من `/components/invoice/templates/` (فيه 2 قوالب احترافية جاهزة).
2. عدّل النصوص إلى العربية، اعكس الـ layout (RTL)، غيّر الشعار.
3. اربطه ببيانات فاتورة جديدة من نوع `Invoice` (كيان جديد سنضيفه، راجع القسم 3.2).
4. استخدم PDF generation الموجود عندهم (Puppeteer في Next لكن سنحوّله إلى @react-pdf/renderer ليتوافق مع Vite).

**الجهد:** 3–4 أيام وتكون الفواتير جاهزة بـ PDF بتصميم احترافي.

### 1.6 النسخ الاحتياطي الآلي

| الحل | لماذا؟ | الجهد |
|---|---|---|
| **GitHub Actions + pg_dump + Cloudflare R2 (أو Google Drive)** — انسخ workflow جاهز من [المرجع Medium](https://medium.com/@efethesage/i-didnt-want-to-pay-for-supabase-backups-so-i-built-my-own-b61948974d5a) أو استخدم **[`mansueli/Supa-Backup`](https://github.com/mansueli/Supa-Backup)** GitHub Action الجاهز. | لا حاجة لبناء backup UI داخل التطبيق الآن. نسخ احتياطي يومي تلقائي على الساعة 2 صباحاً، يُرفع إلى Cloudflare R2 مجاني لحد 10GB، مع احتفاظ 30 يوماً. ونضيف زر "Backup Now" في الإعدادات يستدعي نفس الـ workflow عبر `workflow_dispatch`. | يوم واحد — انسخ الـ YAML، ضع Secrets في GitHub. |

---

## 2. المكونات التي سننسخها copy-paste (كود React/MIT)

### 2.1 Dashboard مالي احترافي

**المصدر:** [abderrahimghazali/shadcn-fintech](https://github.com/abderrahimghazali/shadcn-fintech) (MIT)
- لوحة مالية فاخرة بـ 9 صفحات جاهزة: نظرة عامة، حسابات بنكية، المعاملات، التحويلات، البطاقات، التحليلات، الموازنات، الاستثمارات، الإعدادات.
- نفس الـ stack: Next.js + shadcn/ui + Tailwind + Recharts + Lucide.
- **طريقة النقل:** انسخ مكونات الـ cards والـ charts (ليس الصفحات كاملة لأنها Next.js وليست Vite)، ثم أعد تركيبها في `src/features/dashboard/` مع بيانات Terranex.
- **الجهد:** 2–3 أيام لبطاقات البنوك والمعاملات والتحليلات.

### 2.2 صفحة تسجيل الدخول الأنيقة (اختياري)

الموجود حالياً بسيط. يمكن نسخ صفحة sign-in من shadcn-fintech أو من [Kiranism/next-shadcn-dashboard-starter](https://github.com/Kiranism/next-shadcn-dashboard-starter) (MIT) التي فيها authentication + منظمات + فرق كاملة مع Clerk — **لكننا لا نحتاج Clerk لأننا نستخدم Supabase Auth بالفعل** — فقط ننسخ الشكل/الـ styling.

### 2.3 لوحة الإشعارات (Notifications)

انسخ من shadcn-fintech — نحتاجها لاحقاً لتنبيهات الاستحقاقات والمواعيد.

---

## 3. ما سنبنيه بأنفسنا (حسب الأولوية) — مع خطة يومية

> **ملاحظة:** كل جديد سنبنيه يُكتب على نفس الأسلوب الموجود في Terranex:
> - جدول Postgres مع `owner_id` و composite FKs و RLS (4 policies) و `deleted_at` soft delete.
> - TypeScript types تُطابق السكيما حرفياً.
> - Zod schema للتحقق client-side + RPC ذرّي server-side مع idempotency + advisory lock.
> - Store عبر `createSupabaseStore` + TanStack Query + RHF + Zod في الفورم.
> - rollback migration لكل migration جديدة.
> - اختبارات لكل RPC.

### المرحلة أ — الإطلاق فعلياً (أسبوع واحد — أولوية قصوى)

**هدف:** الخروج من حالة NO-GO. نظام مُنشور على Supabase إنتاجي مع نسخ احتياطي آلي، وكل البلوكرز المُوثقة مغلقة.

| # | المهمة | التفصيل | الجهد |
|---|---|---|---|
| أ.1 | تدوير المفاتيح | استخرج `VITE_SUPABASE_URL` و `VITE_SUPABASE_PUBLISHABLE_KEY` و `service_role` جديد من Supabase dashboard. ضعهم في `.env.local` (لا ترفع للgit). احذف القديم من GitHub secrets و Supabase. | نصف يوم |
| أ.2 | نشر الـ migrations على Supabase إنتاجي | `supabase link --project-ref <ref>` ثم `supabase db push`. شغّل الاختبارات الموجودة ضد قاعدة حقيقية. | نصف يوم |
| أ.3 | Backup آلي | أنشئ `.github/workflows/backup.yml` باستخدام `mansueli/Supa-Backup@v1.0.5` ينسخ يومياً لـ Cloudflare R2 أو GitHub. اختبر الاستعادة مرة واحدة. | يوم |
| أ.4 | إصلاح الـ P0 bugs الـ 5 المُوثقة في تقرير 2026-07-31 | (1) ثغرة التواريخ المستحيلة — اربط `toDateOnly()` في كل Zod schemas (2) `StockAdjustmentPanel` — استخدم `validateStockAdjustment` نفسها، try/catch مع عرض رسالة عربية، تحقق من أن القيمة رقم حقيقي وفارغ ليس صفراً (3) equity constraint انقله إلى SQL/RPC (4) fx_rate في Obligations — استخدم نفس منطق المعاملات (5) رسائل أخطاء الخادم العربية — أضف طبقة ترجمة في `serverErrorTranslator.ts` | 3 أيام |
| أ.5 | تمكين الشركة الأولى واختيار العملة الأساس | أنشئ جدول `company_settings` (سجل واحد لكل owner): الاسم، الرقم الضريبي، العنوان، الهاتف، العملة الأساس، بداية السنة المالية. أضف صفحة إعدادات الشركة. حول كل `amount_egp` إلى `amount_base` (عملة أساس قابلة للتغيير). هام: لا تغيّر أسماء الأعمدة الآن — فقط غيّر المنطق ليحوّل إلى `company_settings.base_currency` بدلاً من EGP الثابت. وأضف OMR كعملة أساس افتراضية لمستخدم مسقط. | يومان |

### المرحلة ب — العمليات اليومية الأساسية (3–4 أسابيع)

**هدف:** أن يقوم النظام بما يحتاجه المستخدم كل صباح: معرفة الرصيد، تسجيل فاتورة، تسجيل قبض/دفع، معرفة المستحقات.

#### ب.1 حسابات البنوك والصناديق (أهم ميزة على الإطلاق) — 5 أيام

**كيانات جديدة:**

```sql
-- جدول الحسابات النقدية
bank_accounts (
  id uuid pk,
  owner_id uuid fk -> auth,
  name_ar text,                        -- "البنك الأهلي - جاري 1234" / "صندوق المكتب"
  name_en text,
  type text,                           -- 'bank' | 'cash' | 'wallet'
  currency currency_code,              -- OMR, USD, EGP...
  opening_balance numeric(18,3),       -- الرصيد الافتتاحي
  opening_date date,
  bank_name text,
  account_number text,
  iban text,
  is_archived boolean default false,
  created_at timestamptz default now()
)

-- حركات الحساب (تُنشأ تلقائياً من المعاملات/التسويات)
bank_transactions (
  id uuid pk,
  owner_id uuid,
  bank_account_id uuid fk,
  transaction_id uuid fk nullable,    -- لو جاءت من معاملة
  settlement_id uuid fk nullable,     -- لو جاءت من تسوية
  distribution_payment_id uuid fk nullable,
  direction text,                      -- 'deposit' | 'withdrawal'
  amount numeric(18,3),
  currency currency_code,
  fx_rate_to_base numeric,
  amount_base numeric(18,3),
  counterparty_account_id uuid nullable, -- للتحويلات بين حساباتنا
  memo text,
  transaction_date date,
  is_reconciled boolean default false,
  document_id uuid nullable,
  created_at timestamptz default now()
)
```

**الربط التلقائي (في RPC الذرية الموجودة):**
- كل `Transaction` من نوع `income` تُنشئ `deposit` في حساب البنك المختار.
- كل `Transaction` من نوع `expense` تُنشئ `withdrawal`.
- كل `Settlement` مدين (عميل دفع لنا) تُنشئ `deposit`.
- كل `Settlement` دائن (نحن دفعنا لمورد) تُنشئ `withdrawal`.
- توزيعات الأرباح المدفوعة تُنشئ `withdrawal`.
- تحويل بين حسابين ينشئ `withdrawal` من أحدهما و `deposit` في الآخر (نفس المعرّف `transfer_id` لضمان التوازن).

**هذا يعطي تلقائياً:**
- رصيد البنك اللحظي = opening + Σ deposits − Σ withdrawals
- لا يمكن أن يخرج رصيد حساب البنك عن الحقيقة رياضياً
- Dashboard يعرض "كم لدينا الآن؟"
- لا يُجبر المستخدم على فهم "قيد مزدوج" — يختار "من أي حساب دُفع؟" في الفورم فقط

**الواجهة:**
- صفحة `/banking` بحسابات البنك كبطاقات (انسخ من shadcn-fintech)، رصيد كل حساب ظاهر.
- صفحة كشف حساب لكل حساب مع DataTable (نسخ shadcn data-table).
- زر "تسجيل إيداع/سحب يدوي" للحركات غير الناتجة من معاملة.
- زر "تحويل بين حساباتي" (يُنشئ حركتين متعاكستين).

#### ب.2 طبقة المال الآمنة — يومان

1. `npm install dinero.js@2`
2. أنشئ `src/core/lib/money.ts`:

```ts
import { dinero, toDecimal, add, subtract, multiply, allocate, toSnapshot, compare } from 'dinero.js';
import { OMR, USD, EGP, SAR, AED, EUR, GBP } from 'dinero.js/currencies';
import type { Currency } from '@/core/types/domain';

const CURRENCIES = { OMR, USD, EGP, SAR, AED, EUR, GBP };

export function money(amount: number | string, currency: Currency) {
  const currencyObj = CURRENCIES[currency];
  const exponent = currencyObj.exponent;
  // input is decimal string "12.345" → convert to subunit integer
  const [whole = '0', frac = ''] = String(amount).split('.');
  const fracPadded = frac.padEnd(exponent, '0').slice(0, exponent);
  const subunit = parseInt(whole + fracPadded, 10) * (String(amount).startsWith('-') ? -1 : 1);
  return dinero({ amount: subunit, currency: currencyObj });
}

export function toNumber(d) {
  return Number(toDecimal(d));
}

export const OMR_MONEY = (n: number | string) => money(n, 'OMR');
// إلخ
```

3. غلف جميع العمليات الحسابية في `profitability.ts` لتستخدم `dinero` بدلاً من `number` الخام. **هذا يمنع فئة كاملة من bugs للأبد.**

#### ب.3 الفواتير (Invoices) — 5–7 أيام

**الجداول الجديدة:**

```sql
sales_invoices (
  id uuid pk,
  owner_id uuid,
  invoice_number text,                -- سلسلة قابلة للتخصيص: INV-2026-0001
  project_id uuid fk nullable,
  partner_id uuid fk,                -- العميل
  status text,                        -- 'draft' | 'sent' | 'partial' | 'paid' | 'cancelled' | 'overdue'
  issue_date date,
  due_date date,
  currency currency_code,
  fx_rate_to_base numeric,
  subtotal numeric(18,3),
  vat_rate numeric(5,2) default 0,   -- 0, 5, 15, 20 حسب البلد
  vat_amount numeric(18,3),
  discount_amount numeric(18,3) default 0,
  total numeric(18,3),               -- final total
  total_base numeric(18,3),
  amount_paid numeric(18,3) default 0,
  notes text,
  document_id uuid nullable,         -- PDF المُصدَّر
  created_at, updated_at
)

sales_invoice_items (
  id uuid pk,
  invoice_id uuid fk,
  owner_id uuid,
  description_ar text,
  description_en text,
  quantity numeric(15,3),
  unit_price numeric(18,3),
  vat_rate numeric(5,2),
  line_total numeric(18,3)
)

purchase_invoices -- نفس الهيكل لكن للموردين (اتجاه معاكس)
```

**الربط التلقائي:**
- عند إنشاء `sales_invoice` بحالة صادرة، تُنشأ `Transaction` اتجاه income مرتبطة بالعميل، و `Obligation (receivable)` بقيمة الإجمالي آلياً.
- عند تسجيل `purchase_invoice`، تُنشأ `Transaction` expense و `Obligation (payable)`.
- الـ settlements الموجودة بالفعل تُخفض `amount_paid` في الفاتورة المرتبطة وتُحدث الحالة (partial/paid).

**الواجهة:**
- صفحة `/invoices/sales` و `/invoices/purchase` بـ DataTable مع faceted filters (حالة، شريك، تاريخ).
- نموذج إنشاء فاتورة (RHF + Zod) مع بنود قابلة للإضافة/الحذف (drag-and-drop)، حساب تلقائي للضريبة/الإجمالي.
- **قالب PDF:** انسخ من `al1abb/invoify` قالباً احترافياً عربياً RTL باستخدام @react-pdf/renderer + خط Noto Sans Arabic. عند الحفظ، يُولَّد PDF ويُرفع لسلة Documents ويُخزن في Storage.
- زر "إرسال بالبريد" — استخدم `resend.com` (API مجاني لـ 3000 إيميل/شهر، يُرسل الفاتورة PDF مرفقاً).

**الضريبة:**
- بدأ بـ VAT عام يدوي فقط (يُدخل المُحاسب النسبة في إعدادات الشركة).
- لا ZATCA/ETA integration الآن (مشروع منفصل لاحقاً). بُني `zatca-xml-js` (MIT) عند الحاجة فقط.

#### ب.4 إصلاح الـ RBAC (صلاحيات المستخدمين) — 3 أيام

لا نحتاج RBAC مُعقداً — لشركة واحدة نحتاج 4 أدوار فقط:

| الدور | الصلاحيات |
|---|---|
| **owner** | كل شيء (هو المستخدم الحالي `auth.uid()`) |
| **accountant** | قراءة كل شيء + كتابة المعاملات والفواتير والتسويات + لا حذف + لا تغيير ملكية |
| **data_entry** | كتابة المعاملات والأحداث التشغيلية فقط، لا يرى التوزيعات، لا يرى أرصدة البنوك كاملة |
| **viewer** | قراءة فقط (مثلاً محاسب قانوني، أو شريك اطلاع) |

**الطريقة الأسهل (ب native Supabase بدون مكتبات):**

```sql
-- جدول الأدوار
create table user_roles (
  owner_id uuid not null references auth.users(id) on delete cascade,
  -- ملاحظة: في single-company company_id ليس ضرورياً — owner_id للجدول نفسه هو صاحب الدعوة (الـ owner)
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','accountant','data_entry','viewer')),
  invited_at timestamptz default now(),
  primary key (owner_id, user_id)
);
-- RLS policies user_roles يراها owner فقط
```

ثم **بدّل كل الـ RLS policies** الـ 44 الموجودة لتضيف شرطاً مثل:

```sql
-- مثال لسياسة SELECT على المعاملات
using (
  auth.uid() = owner_id   -- هو المالك
  or exists (select 1 from user_roles ur   -- أو تم منحه صلاحية
             where ur.owner_id = transactions.owner_id
               and ur.user_id = auth.uid()
               and ur.role in ('accountant','data_entry','viewer'))
)
```

**الواجهة:**
- صفحة `/team` بسيطة: إضافة مستخدم بالبريد الإلكتروني (دعوة عبر Supabase Auth magic link أو إرسال رابط)، اختيار دور، حذف.
- في الواجهة: اختبار دور المستخدم وإخفاء الأزرار التي ليس له صلاحية لها.

**بديل أسرع (إذا أردت مكتبة جاهزة):** استخدم [`point-source/supabase-tenant-rbac`](https://github.com/point-source/supabase-tenant-rbac) (v3 موجودة، توفر دوال RLS مُعدّة مسبقاً مع مطالبات مُحدّثة فوراً بدون انتظار JWT refresh) — لكن في حالتنا single-company النموذج اليدوي أبسط وأسرع.

#### ب.5 شجرة الحسابات الأساسية + دفتر الأستاذ المُبسَّط — 5 أيام

**لا نقل للـ lefra** وجدته أثناء البحث: مكتبة لطيفة لكن صغيرة (9 نجوم، 136 commit، آخر تحديث يوليو 2026) — لا أثق بها للمال. نكتب 4 جداول بسيطة بأنفسنا.

```sql
-- شجرة الحسابات — بذرة أولية بحسابات أساسية فقط
accounts (
  id uuid pk,
  owner_id uuid,
  code text,                 -- 1000, 1100, 1110, 2000... ترقيم شجري
  name_ar text,
  name_en text,
  type text,                 -- 'asset' | 'liability' | 'equity' | 'income' | 'expense'
  parent_id uuid fk nullable,
  is_bank_account boolean default false,
  is_archived boolean default false,
  created_at
)

journal_entries (
  id uuid pk,
  owner_id uuid,
  entry_date date,
  memo text,
  reference_type text,       -- 'transaction' | 'settlement' | 'invoice' | 'distribution' | 'manual' | 'transfer'
  reference_id uuid,
  created_by uuid,
  is_reversed boolean default false,
  reversed_by_id uuid nullable,
  created_at
)

journal_lines (
  id uuid pk,
  owner_id uuid,
  journal_entry_id uuid fk,
  account_id uuid fk,        -- الحساب (أصل/خصم/دخل/مصروف/بنك...)
  debit_amount_base numeric(18,3) default 0,
  credit_amount_base numeric(18,3) default 0,
  project_id uuid nullable,  -- ربط اختياري بمشروع لربحية
  partner_id uuid nullable,
  description text
)

-- constraint: لكل قيد مجموع المدين = مجموع الدائن
-- check: sum(debit) = sum(credit) per journal_entry
```

**الزرع التلقائي (Automatic Posting):**
نعدّل كل الـ RPCs الذرية الموجودة (`record_transaction_atomic`، `record_settlement_atomic`، `record_distribution_atomic`، `record_stock_adjustment_atomic`) لتنشئ معها `journal_entry` + `journal_lines` المُتوازنة تلقائياً.

**أمثلة:**
- تسجيل مصروف أعلاف 100 OMR نقداً من صندوق المزرعة:
  - مدين (Debit): 100 على حـ/مصروف الأعلاف (expense)
  - دائن (Credit): 100 على حـ/الصندوق (asset ← bank_account)
- تسجيل استلام دفعة من عميل 500 OMR في البنك الأهلي:
  - مدين (Debit): 500 على حـ/البنك الأهلي (asset)
  - دائن (Credit): 500 على حـ/ذمم العملاء (asset contra / receivable)
- تسجيل توزيع أرباح 1000 OMR لشريك:
  - مدين: 1000 على حـ/الأرباح المحتجزة (equity)
  - دائن: 1000 على حـ/الشريك مستحق التوزيع (liability)

**هام جداً:** المستخدم **لن يرى هذه الجداول في الواجهة إلا في صفحة "دفتر الأستاذ" للمحاسب/المالك.** يبقى كل شيء يُسجَّل عبر صفحات المعاملات/الفواتير/التسويات/التوزيعات كما هو — لكن تحت الغطاء لدينا double-entry حقيقي دون أي جهد إضافي من المستخدم.

**هذا يحل كل مشاكل المرحلة 1 بضربة واحدة:**
- قائمة دخل (P&L) حقيقية
- ميزانية عمومية (Balance Sheet)
- أرصدة الحسابات
- توازن الدفاتر (لو لم تتوازن نعرف أن هناك خطأ فوراً)
- تدقيق أسهل للمحاسب القانوني

**شجرة الحسابات الافتراضية للزرع (seed) — نكتب migration تُدخل حسابات IFRS مبسطة:**
```
1000 الأصول (Assets)
  1100 الأصول المتداولة
    1110 الصندوق (Cash)
    1120 البنوك (Bank Accounts)
    1130 ذمم مدينة (Receivables)
    1140 المخزون (Inventory)
  1200 الأصول الثابتة
    1210 أراضي
    1220 مباني
    1230 معدات
    1240 ثروة حيوانية
2000 الخصوم (Liabilities)
  2100 ذمم دائنة (Payables)
  2200 قروض
  2300 ضريبة القيمة المضافة مستحقة
3000 حقوق الملكية (Equity)
  3100 رأس المال
  3200 مسحوبات الشركاء
  3300 أرباح محتجزة
  3400 أرباح العام
4000 الإيرادات (Income)
  4100 إيراد مبيعات عقارية
  4200 إيراد محاصيل زراعية
  4300 إيراد مبيعات حيوانات
5000 المصروفات (Expenses)
  5100 تكاليف تشغيل
    5110 أعلاف
    5120 أسمدة وبذور
    5130 أدوية وتحصينات
    5140 عمالة
  5200 مصروفات عمومية
  5300 مصروفات تسويقية
```

**هذه الشجرة تُزرع تلقائياً عند إنشاء حساب الشركة الأول، ويمكن للمحاسب تعديلها وإضافة حسابات لاحقاً. ننسخ الحسابات الأساسية من IFRS standard chart of accounts لشركة استثمار صغيرة (انظر ملفات ERPNext chart_of_accounts على GitHub مرجعاً لكن لا ندمج كود ERPNext).**

#### ب.6 التقارير المالية الرسمية — 3 أيام

بالاستناد لدفتر الأستاذ (ب.5):

1. **قائمة الدخل (Income Statement):** لكل فترة — مجموع إيرادات 4000 − مجموع مصروفات 5000 = صافي الربح
2. **الميزانية العمومية (Balance Sheet):** أصول 1000 = خصوم 2000 + حقوق ملكية 3000 (يجب أن تتوازن دائماً)
3. **كشف حساب (Account Statement):** لكل حساب في شجرة الحسابات — كل الحركات عليه
4. **ميزان المراجعة (Trial Balance):** جميع الحسابات وأرصدتها (مدين/دائن) للتدقيق

**كلها تُصدَّر PDF بـ @react-pdf/renderer وقالب RTL عربي.**

### المرحلة ج — العمق التشغيلي (4–6 أسابيع)

**هدف:** تخدم الزراعة والثروة الحيوانية فعلياً.

#### ج.1 المخزون الحقيقي (للأعلاف والأسمدة والبذور والمنتجات) — 10 أيام

نبنيه بنفس أسلوب Terranex المُجرّب:

```sql
inventory_items (id, owner_id, name_ar, name_en, sku, category, unit,
                default_location_id, reorder_point, current_qty, avg_cost, ...)
inventory_locations (id, owner_id, name_ar, ...)
inventory_movements (id, owner_id, item_id, movement_type ('in'|'out'|'transfer'),
                     from_location_id, to_location_id, quantity, unit_cost,
                     total_cost, reference_type (purchase_invoice|sale_invoice|feed_consumption|adjustment...),
                     reference_id, project_id, notes, created_at)
```

**الربط التلقائي:**
- عند `purchase_invoice` فيها مواد (بذور/أعلاف/أسمدة) → حركة وارد تلقائياً.
- عند حدث تشغيلي `feed_consumption` → حركة صرف من مخزون الأعلاف (بدلاً من التسجيل يدوياً).
- عند `harvest` → حركة وارد للمحصول.
- عند بيع → حركة صرف.

**تكلفة المخزون:** Weighted Average (المتوسط المرجح) — أبسط طريقة محاسبية، كافية لشركتنا في المرحلة الأولى.

**الواجهة:**
- صفحة `/inventory` ببطاقات رصيد + تنبيهات "تحت حد الطلب" (reorder point).
- حركات مخزون DataTable.
- صفحة جرد دوري (Physical Count) → تُسجل تعديل مخزون كحركة مع سبب.

#### ج.2 الأحداث التشغيلية — تحسينات — 5 أيام
- إصلاح التنبيهات الصامتة للكميات (بدلاً من تغيير الإشارة تلقائياً — اطلب تأكيداً أو ارفض).
- ربط أحداث الأعلاف/الاستهلاك بالمخزون (ج.1).
- تقويم أحداث مستقبلية (تحصينات/ري/حصاد) مع تنبيهات.
- تسجيل سريع من الهاتف (PWA mobile-optimized form: زر "تسجيل ولادة" بصفحة واحدة، ثلاث حقول).

#### ج.3 الاهتلاك (Depreciation) — يومان
جدول بسيط:
```sql
fixed_assets (id, asset_id فk, acquisition_cost, salvage_value, useful_life_years,
              depreciation_method ('straight_line'), depreciation_start_date,
              accumulated_depreciation)
```
ننشئ RPC يُولّد قيد اهتلاك شهرياً: مدين مصروف اهتلاك / دائن مجمّع اهتلاك.

#### ج.4 إقفال الفترات (Period Close) — 3 أيام
```sql
closed_periods (id, owner_id, period_type ('month'|'year'), period_start, period_end, closed_at, closed_by, locked boolean default true)
```
- عند إقفال شهر: لا يُسمح بإنشاء/تعديل/حذف أي معاملة أو قيد أو تسوية في هذه الفترة إلا بصلاحية owner.
- زر "إقفال الشهر" في صفحة الإعدادات يُحذر ويطلب تأكيداً بكلمة.

#### ج.5 تطبيق موبايل للأحداث (PWA) — 5 أيام
حسّن الـ PWA الموجود (manifest + service worker):
- اجعل صفحة `/events/mobile` بنموذج بسيط جداً (أصل، نوع الحدث، كمية، ملاحظة، صورة) — 3 نقرات فقط.
- ادعم Workbox background sync للعمل بدون إنترنت (عندما يعود الإنترنت يُرسل الأحداث المُسجّلة).
- أضف زر "مسح الباركود/QR" للأصل (للأصول ذات ملصق).

### المرحلة د — التميز والقيمة المضافة (6 أسابيع +)

#### د.1 بوابة الشركاء (Investor Portal) — 10 أيام
صفحة مستقلة على نطاق فرعي مثل `investors.terranex.app` (أو مسار `/p/`):
- شريك يسجل دخوله بـ Supabase Auth (لكن بدور `investor` منفصل).
- يرى فقط: حصصه في المشاريع، التوزيعات التي حصل عليها، كشوفات حساب شريك، مستندات الفواتير/العقود المتعلقة به.
- **هذه هي أول ميزة "تبيع" فعلاً** — لا يقدمها أي نظام محلي في السعر الصغير.

#### د.2 تحليلات متقدمة — 5 أيام
- مؤشرات زراعية: إنتاجية الفدان، تكلفة الطن، مقارنة مواسم.
- مؤشرات حيوانية: متوسط وزن الرأس، نسبة النفوق، تكلفة الرأس.
- مؤشرات عقارية: العائد على الاستثمار (ROI)، فترة التطوير، هامش الربح.
- تنبؤات بسيطة (linear projection) للإيرادات والمصروفات الشهرية القادمة.

#### د.3 ZATCA/ETA e-invoicing (متى ما لزم)
عندما تحتاج الشركة فعلاً لإصدار فواتير ضريبية إلكترونية (في السعودية ZATCA، أو مصر ETA):
- استخدم مكتبة **`wes4m/zatca-xml-js`** (MIT، TypeScript) لتوليد وتوقيع XML لزاتكا.
- توقع شهادة عبر API.
- أرسل الفواتير لـ Fatoora portal.
- **لا تبدأ بهذا الآن** — التكامل مع ZATCA مشروع بذاته (3–4 أسابيع).

#### د.4 التكامل البنكي (متى ما لزم)
استخدم خدمة مثل **Lean Technologies** أو **Dapi** أو **Tarabut Gateway** (fintech APIs في الخليج/MENA) لسحب حركات البنوك تلقائياً ومطابقتها (reconciliation). لا تفعل هذا إلا بعد أن يكون النظام مُستخدماً يومياً لـ 6 أشهر.

---

## 4. الترتيب الزمني المقترح (خريطة طريق 3 شهور إلى usable، 6 شهور إلى complete)

```
الأسبوع 1:     ─┬─ أ.1 تدوير مفاتيح
                ├─ أ.2 نشر migrations
                ├─ أ.3 Backup آلي GitHub Actions
                └─ أ.4 إصلاح P0 bugs الخمس

الأسبوع 2–3:   ─┬─ أ.5 إعدادات الشركة والعملة الأساس
                ├─ ب.2 dinero.js طبقة المال الآمنة
                └─ ب.1 حسابات البنوك والصناديق + الربط التلقائي بالمعاملات

الأسبوع 4–6:   ─┬─ ب.3 الفواتير (sales + purchase) مع PDF عربي
                ├─ ب.4 RBAC بأدوار أساسية
                └─ إطلاق أول نسخة مستخدمة فعلياً من الشركة (Milestone 1)

الأسبوع 7–9:   ─┬─ ب.5 دفتر الأستاذ المُبسَّط + الربط التلقائي بكل RPCs
                ├─ ب.6 التقارير المالية الرسمية (P&L، ميزانية، كشف حساب)
                └─ إزالة الحاجة لبرنامج محاسبة خارجي (Milestone 2)

الأسبوع 10–13: ─┬─ ج.1 المخزون الحقيقي
                ├─ ج.2 تحسين الأحداث التشغيلية وربطها بالمخزون
                ├─ ج.3 الاهتلاك
                ├─ ج.4 إقفال الفترات
                └─ ج.5 PWA موبايل للأحداث الميدانية (Milestone 3: الشركة تعتمد عليه فعلياً)

الأسبوع 14–24: ─┬─ د.1 بوابة الشركاء (الأولوية في المرحلة د)
                ├─ د.2 تحليلات متقدمة
                ├─ ZATCA integration (إن لزم)
                ├─ تكامل بنكي (إن لزم)
                └─ بيع لشركات أخرى مماثلة (Milestone 4: منتج تجاري)
```

---

## 5. قواعد ذهبية لا تكسرها

### 5.1 كل يوم ينتهي بنظام أخضر
بعد أي تعديل، شغّل قبل النوم:
```bash
npm run typecheck   # 0 errors
npm run lint        # pass
npm test            # كل الاختبارات خضراء (لا تُكسر القديم)
npm run build       # success
```
هذا الدرع الحامي موجود في `.github/workflows/quality-gate.yml` ولا تسمح لأي كود بالمرور إن كسره.

### 5.2 كل يوم تضيف شيئاً صغيراً وتختبره
لا تكتب يوم كامل بدون اختبار ما تكتبه. حتى وإن كنت تعمل بمساعدة AI، اختبر كل شاشة بعد كتابتها.

### 5.3 لا تنسخ كوداً لا تفهمه
حين تنسخ قالب فاتورة أو DataTable من مشروع آخر، اقرأه وافهمه سطراً بسطر قبل لصقه. قدّم للـ AI الكود وقل له "اشرح لي هذا سطراً بسطر".

### 5.4 النسخ الاحتياطي يومياً قبل أي تعديل على السكيما
قبل أي migration جديدة، شغّل backup يدوياً واحتفظ به محلياً. إذا أخطأت في migration والـ rollback لم يعمل، يمكنك استعادة النسخة.

### 5.5 لا تضف ميزة جديدة حتى تُغلق الميزة الحالية 100%
لا تبدأ الفواتير قبل الانتهاء من البنوك. لا تبدأ دفتر الأستاذ قبل الفواتير. لا تبدأ المخزون قبل إغلاق المرحلة ب.
> **"نفّذ أقل، لكن نفّذه كاملاً"** — نفس التوصية من تقرير يونيو، ما زالت صحيحة.

### 5.6 اللغة: عربي فقط في الكود والنصوص
- أوقف i18n الإنجليزية مؤقتاً (علق toggle اللغة في TopBar، احذف استخدام `en.ts` في كل الصفحات الجديدة).
- كل النصوص عربية في الأساس. عندما يطلب عميل فعلي الإنجليزية — أضفها.
- لكن **أسماء المتغيرات والدوال والـ code باللغة الإنجليزية دائماً** — لا تكتب كود برمجي بحروف عربية، يصعب قراءته مع المكتبات.

---

## 6. الخلاصة — ما يمكن إنجازه بأسبوع، شهر، و3 أشهر

| بعد | الوضع |
|---|---|
| **أسبوع واحد** | النظام منشور على Supabase إنتاجي، نسخ احتياطي يومي، لا P0 bugs، الشركة/العملة قابلة للتخصيص، مُستعد لإدخال البيانات الحية. |
| **4 أسابيع** | حسابات بنوك ظاهرة على الـ Dashboard، رصيد نقدي حي، فواتير عربية PDF، RBAC للمحاسب، يمكن استخدام النظام بدل Excel للمعاملات اليومية. |
| **8 أسابيع** | دفتر أستاذ مُبسَّط تلقائي، قائمة دخل وميزانية عمومية، ذمم آجلة عبر الفواتير، النظام مصدر الحقيقة الوحيد للشركة. |
| **12 أسبوعاً** | مخزون حقيقي، أحداث تشغيلية مرتبطة بالمخزون، إقفال فترات، اهتلاك، موبايل PWA للأحداث الميدانية — نظام كامل يُغنيك عن أي برنامج آخر. |
| **6 أشهر** | بوابة شركاء، تحليلات متقدمة، أول شركة خارجية تبدأ في استخدامه. |

**هذه الخطة كُتبت لتكون قابلة للتنفيذ فعلاً من شخص واحد يعمل بمساعدة AI (كما أنت الآن)، دون فريق، دون استثمار مادي يُذكر (كل المكتبات مجانية، Supabase مجاني لحد 500MB، Resend مجاني لحد 3000 إيميل، Cloudflare R2 مجاني حتى 10GB، GitHub Actions مجاني للمشاريع الخاصة).**

أنت تمتلك بالفعل النواة الأغلى (المحركات المالية الثلاثة)، وما تبقي هو إضافة طبقات معيارية كل منها مكوّن من 2–5 جداول و RPCs ذرية تم إنشاء 7 منها مسبوقة عندك كنموذج يمكن أن تنسخ منه.

**الخطوة التالية الآن:** اخبرني هل تريد أن نبدأ فوراً بتنفيذ **المرحلة أ.1 (تدوير المفاتيح) وأ.2 (نشر migrations)** وأكتب لك أوامرها خطوة بخطوة — أم تريد أن أبدأ مباشرة بكتابة كود **ب.1 (حسابات البنوك)** بعد إصلاح P0 bugs؟

---

*خطة مُعدّة من Agent Mode — Arena.ai*
*2 أغسطس 2026 — كل مكتبة ومكون ذُكر في هذا المستند تم التحقق من وجوده ورخصته وتوافقه مع مكدس Terranex (React 19 + Vite + TS + Tailwind + shadcn/ui + Supabase).*

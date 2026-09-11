#!/usr/bin/env node
/**
 * Builds docs/design/design-system.html — a visual specification of the
 * Terranex interface language.
 *
 * The stylesheet is READ FROM src/app/globals.css and inlined, and the markup
 * uses exactly the class names the real components emit. This page is
 * therefore a rendering of the shipped CSS, not an idealised mockup: if the
 * two drift, this file stops matching the product.
 *
 * Usage: node ./scripts/build-design-gallery.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const css = readFileSync(resolve(root, 'src/app/globals.css'), 'utf8');
const outDir = resolve(root, 'docs/design');
mkdirSync(outDir, { recursive: true });

const GLYPHS = {
  REAL_ESTATE:
    'M2 13.5 8 3.2l6 10.3M4.6 12.8V8.2h2.9v4.6M9.4 12.8V6.4h2.9v6.4M1.6 13.5h12.8',
  AGRICULTURE:
    'M8 14.4V6.6M8 9.9C8 7.2 9.9 5.2 12.6 5c.3 2.8-1.6 4.9-4.6 4.9M8 11.7c0-2.4-1.7-4.2-4.1-4.4-.3 2.5 1.4 4.4 4.1 4.4M3.4 14.4h9.2',
  LIVESTOCK:
    'M5.4 4.2c-1.5.5-2.3 1.8-2.3 3.3 0 1.9 1.2 2.9 1.2 4.4 0 1.4 1.1 2.5 3.7 2.5s3.7-1.1 3.7-2.5c0-1.5 1.2-2.5 1.2-4.4 0-1.5-.8-2.8-2.3-3.3M5.4 4.2 4 2.6M10.6 4.2 12 2.6',
};
const SECTORS = [
  { key: 'REAL_ESTATE', ar: 'عقارات', tone: 'sector-real-estate', theme: 'sector-theme-real-estate' },
  { key: 'AGRICULTURE', ar: 'زراعة', tone: 'sector-agriculture', theme: 'sector-theme-agriculture' },
  { key: 'LIVESTOCK', ar: 'ثروة حيوانية', tone: 'sector-livestock', theme: 'sector-theme-livestock' },
];

const glyph = (key, size = 14) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${GLYPHS[key]}"/></svg>`;

const chip = (s) => `<span class="sector-chip ${s.tone}">${glyph(s.key)}${s.ar}</span>`;

const BADGES = [
  ['badge-neutral', 'مفتوح', 'tone-open'],
  ['badge-success', 'معتمد', ''],
  ['badge-warning', 'قيد الانتظار', 'tone-open'],
  ['badge-danger', 'مرفوض', ''],
  ['badge-info', 'معلومة', ''],
];

const BUTTONS = [
  ['button', 'إجراء أساسي'],
  ['button secondary', 'إجراء ثانوي'],
  ['button ghost', 'إجراء شبح'],
  ['button danger', 'إجراء خطر'],
  ['button sm', 'صغير'],
];

const html = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>تيرانكس — نظام التصميم</title>
<style>
${css}

/* Gallery chrome only. Nothing below this line ships in the product. */
body { padding-block-end: 80px; }
.gallery-shell { max-width: 1180px; margin-inline: auto; padding: var(--sp-6) var(--sp-5); display: grid; gap: var(--sp-8); }
.gallery-hero { display: grid; gap: var(--sp-3); border-block-end: 1px solid var(--line); padding-block-end: var(--sp-6); }
.gallery-hero h1 { font-size: 2.25rem; }
.gallery-kicker { font-size: var(--fs-300); font-weight: 700; letter-spacing: .06em; color: var(--brand); }
.gallery-lede { max-width: 62ch; color: var(--muted); line-height: 1.8; }
.gallery-toc { display: flex; flex-wrap: wrap; gap: var(--sp-2); }
.gallery-toc a { text-decoration: none; font-size: var(--fs-300); font-weight: 700; padding: 6px 12px; border-radius: var(--r-pill); background: var(--surface); border: 1px solid var(--line); }
.gallery-toc a:hover { border-color: var(--brand); color: var(--brand-strong); }
.gallery-block { display: grid; gap: var(--sp-4); }
.gallery-block > header { display: grid; gap: 4px; border-block-end: 1px solid var(--line-soft); padding-block-end: var(--sp-3); }
.gallery-block > header h2 { font-size: 1.375rem; }
.gallery-note { font-size: var(--fs-300); color: var(--muted); max-width: 74ch; line-height: 1.7; }
.swatch-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px,1fr)); gap: var(--sp-3); }
.swatch { border: 1px solid var(--line); border-radius: var(--r-lg); overflow: hidden; background: var(--surface); }
.swatch span { display: block; height: 56px; }
.swatch div { padding: 8px 10px; font-size: var(--fs-300); }
.swatch code { display: block; background: none; border: 0; padding: 0; color: var(--muted); }
.type-row { display: grid; grid-template-columns: 130px 1fr; gap: var(--sp-4); align-items: baseline; border-block-end: 1px solid var(--line-soft); padding-block: var(--sp-2); }
.type-row > code { font-size: var(--fs-300); }
.frame { border: 1px dashed var(--line-strong); border-radius: var(--r-lg); padding: var(--sp-4); background: var(--paper); }
.frame-label { font-size: var(--fs-300); color: var(--muted-2); font-weight: 700; margin-block-end: var(--sp-2); }
.frames { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: var(--sp-4); align-items: start; }
</style>
</head>
<body>
<div class="gallery-shell">

  <header class="gallery-hero">
    <p class="gallery-kicker">TERRANEX DESIGN SYSTEM</p>
    <h1>لغة واجهة تيرانكس</h1>
    <p class="gallery-lede">
      نظام تشغيل استثماري لأصول حقيقية في ثلاثة قطاعات: عقارات، زراعة، وثروة حيوانية.
      الواجهة مبنية على مبدأ واحد: <strong>كل رقم يقول من أين جاء، وكل حالة تُفهم بدون لون،
      وكل إجراء جسيم يشرح أثره قبل تنفيذه.</strong>
      هذه الصفحة تُبنى من <code>src/app/globals.css</code> نفسه — ما تراه هنا هو ما يُشحن.
    </p>
    <nav class="gallery-toc" aria-label="أقسام المواصفة">
      <a href="#tokens">الرموز</a>
      <a href="#type">الخط</a>
      <a href="#sector">هوية القطاعات</a>
      <a href="#status">لغة الحالة</a>
      <a href="#money">الأرقام المالية</a>
      <a href="#actions">الإجراءات</a>
      <a href="#forms">النماذج</a>
      <a href="#tables">الجداول</a>
      <a href="#nav">التنقل</a>
      <a href="#cards">البطاقات</a>
      <a href="#states">الحالات</a>
      <a href="#confirm">الإجراءات الجسيمة</a>
      <a href="#responsive">الاستجابة</a>
    </nav>
  </header>

  <!-- ------------------------------------------------------------ TOKENS -->
  <section id="tokens" class="gallery-block">
    <header><h2>الرموز اللونية</h2>
      <p class="gallery-note">لون واحد للعلامة، وخمس حالات دلالية، وثلاثة ألوان قطاعات. لا يُستخدم أي لون حرفي خارج هذا القسم — كل قيمة أدناه رمز.</p>
    </header>
    <div class="swatch-row">
      <div class="swatch"><span style="background:#0e5c46"></span><div>العلامة<code>--brand</code></div></div>
      <div class="swatch"><span style="background:#093f30"></span><div>العلامة الداكنة<code>--brand-strong</code></div></div>
      <div class="swatch"><span style="background:#e9f2ee"></span><div>خلفية العلامة<code>--brand-soft</code></div></div>
      <div class="swatch"><span style="background:#10211b"></span><div>الحبر<code>--ink</code></div></div>
      <div class="swatch"><span style="background:#5b6c64"></span><div>الثانوي<code>--muted</code></div></div>
      <div class="swatch"><span style="background:#dbe5df"></span><div>الحد<code>--line</code></div></div>
      <div class="swatch"><span style="background:#f5f8f6"></span><div>الورق<code>--paper</code></div></div>
    </div>
    <div class="swatch-row">
      <div class="swatch"><span style="background:#0d6b48"></span><div>نجاح<code>--success</code></div></div>
      <div class="swatch"><span style="background:#8a5c07"></span><div>تحذير<code>--warning</code></div></div>
      <div class="swatch"><span style="background:#9d2b2b"></span><div>خطر<code>--danger</code></div></div>
      <div class="swatch"><span style="background:#1e4396"></span><div>معلومة<code>--info</code></div></div>
      <div class="swatch"><span style="background:#b5761b"></span><div>حلقة التركيز<code>--focus</code></div></div>
    </div>
  </section>

  <!-- -------------------------------------------------------------- TYPE -->
  <section id="type" class="gallery-block">
    <header><h2>الخط والأرقام</h2>
      <p class="gallery-note">
        العربية هي لغة التأليف. العناوين بخط كوفي/عرضي والجسم بخط نصي.
        <strong>الأرقام الجدولية (<code>tnum</code>) إلزامية</strong> في كل عمود مالي: بدونه لا يمكن مقارنة صفين بصريًا.
      </p>
    </header>
    <div class="card stack">
      <div class="type-row"><code>--fs-800 / 800</code><h1 style="font-size:2rem;margin:0">مشروع استثماري</h1></div>
      <div class="type-row"><code>--fs-700 / 800</code><h1 style="margin:0">عنوان الصفحة</h1></div>
      <div class="type-row"><code>--fs-600 / 750</code><h2 style="margin:0">عنوان القسم</h2></div>
      <div class="type-row"><code>--fs-500 / 750</code><h3 style="margin:0">عنوان فرعي</h3></div>
      <div class="type-row"><code>--fs-400</code><p style="margin:0">نص أساسي يصف الواقعة المالية كما سُجّلت في المصدر الرسمي، دون استنتاج أو تقدير.</p></div>
      <div class="type-row"><code>--fs-300</code><p class="muted" style="margin:0">نص ثانوي: أساس الرقم، التاريخ، المرجع.</p></div>
      <div class="type-row"><code>tnum</code><p class="num" style="margin:0;font-size:1.25rem">١٬٢٣٤٬٥٦٧٫٨٩ &nbsp;·&nbsp; 987,654.32</p></div>
    </div>
  </section>

  <!-- ------------------------------------------------------------ SECTOR -->
  <section id="sector" class="gallery-block">
    <header><h2>هوية القطاعات الثلاثة</h2>
      <p class="gallery-note">
        نظام واحد وثلاث شخصيات. كل قطاع له لون ورسم مميز، ويُوضع كخط جانبي على رأس مساحة العمل وعلى بطاقة المشروع.
        <strong>اللون هنا هوية فقط — لا يحمل معنى.</strong> المعنى يأتي من شارة الحالة المجاورة له.
      </p>
    </header>
    <div class="grid">
      ${SECTORS.map((s) => `
      <div class="${s.theme}">
        <article class="project">
          <strong>مشروع ${s.ar}</strong>
          <div class="badge-row">
            ${chip(s)}
            <span class="status badge-success">نشط</span>
            <span class="status">EGP</span>
          </div>
          <p class="muted">بطاقة المشروع تحمل خط القطاع الجانبي وشريحة القطاع.</p>
        </article>
      </div>`).join('')}
    </div>
    <div class="frame">
      <p class="frame-label">رؤوس مساحات العمل — الخط الجانبي يرث لون القطاع</p>
      <div class="stack">
        ${SECTORS.map((s) => `
        <header class="project-context card page-header ${s.theme}">
          <div class="page-header-main">
            <a class="back-link" href="#sector">→ مساحة المشروع</a>
            <div class="page-title-row">
              <h1 style="font-size:1.25rem">الأصول العقارية</h1>
              ${chip(s)}
              <span class="status badge-success">نشط</span>
            </div>
            <p class="muted page-description">اسم المشروع · EGP · وصف مختصر من السجل الرسمي</p>
          </div>
          <div class="page-actions"><a class="button sm" href="#sector">إجراء</a></div>
        </header>`).join('')}
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------------------ STATUS -->
  <section id="status" class="gallery-block">
    <header><h2>لغة الحالة</h2>
      <p class="gallery-note">
        كل حالة تُفهم بدون لون: <strong>نقطة مصمتة</strong> = مستقرة/مكتملة،
        <strong>حلقة</strong> = مفتوحة/قيد التنفيذ، <strong>شرطة</strong> = ملغاة.
        هكذا تنجو الحالة من الطباعة بالأبيض والأسود ومن عمى الألوان ومن قارئ الشاشة.
      </p>
    </header>
    <div class="card stack">
      <div class="badge-row">
        ${BADGES.map(([cls, label, mod]) => `<span class="status ${cls} ${mod}">${label}</span>`).join('')}
      </div>
      <div class="badge-row">
        <span class="status status-draft">مسودة</span>
        <span class="status status-active">نشط</span>
        <span class="status status-archived">مؤرشف</span>
        <span class="role-badge">عضو تشغيلي</span>
        <span class="role-badge owner">مالك المنظمة</span>
      </div>
      <p class="gallery-note">
        مفردتان منفصلتان عمدًا: <strong>شارة الحالة</strong> تصف سجلًا، و<strong>شارة الدور</strong> تصف صلاحية شخص.
        خلطهما يجعل القارئ يظن أن «مالك» حالة للسجل.
      </p>
      <div class="milestones">
        <div class="gate"><div class="gate-dot satisfied"></div><span>بوابة مكتملة — سند الملكية مثبت</span><span class="status badge-success">محققة</span></div>
        <div class="gate"><div class="gate-dot pending"></div><span>بوابة مفتوحة — الحيازة غير مثبتة</span><span class="status badge-warning tone-open">قيد الانتظار</span></div>
        <div class="gate"><div class="gate-dot not"></div><span>بوابة لم تبدأ — التصريح</span><span class="status">لم تبدأ</span></div>
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------------------- MONEY -->
  <section id="money" class="gallery-block">
    <header><h2>الأرقام المالية</h2>
      <p class="gallery-note">
        الرقم وحده ليس معلومة. كل مبلغ يُعرض مع <strong>أساسه</strong> و<strong>تاريخ سريانه</strong> و<strong>عملته</strong>.
        عندما لا تكون هناك حقيقة مسجلة، يُعرض السبب — لا صفر ولا شرطة.
      </p>
    </header>
    <div class="overview-kpis">
      <div class="overview-kpi"><span>رأس المال المساهم به</span><strong class="num">٤٬٥٠٠٬٠٠٠٫٠٠ ج.م</strong><small class="as-of">مساهمات مسجلة فقط</small></div>
      <div class="overview-kpi"><span>النقدية الحالية</span><strong class="num">١٬٢٣٤٬٥٦٧٫٨٩ ج.م</strong><small class="as-of">مجموع أرصدة الحسابات</small></div>
      <div class="overview-kpi negative"><span>التزامات متأخرة</span><strong class="num">٣٢٠٬٠٠٠٫٠٠ ج.م</strong><small class="as-of">٣ التزامات متأخرة</small></div>
      <div class="overview-kpi"><span>التقييم الإداري</span><strong class="muted" style="font-size:1rem">غير مسجل</strong><small>لا يُعرض صفر بديلًا عن غياب الواقعة</small></div>
    </div>
    <div class="stat-grid">
      <a class="stat stat-link" href="#money"><span class="stat-label">النتيجة المحققة</span><strong class="stat-value num">٧٨٠٬٠٠٠٫٠٠ ج.م</strong><small class="stat-hint">من قيود الاعتراف المتوازنة</small></a>
      <a class="stat stat-link stat-negative" href="#money"><span class="stat-label">انحراف الموازنة</span><strong class="stat-value num">−٤٥٬٠٠٠٫٠٠ ج.م</strong><small class="stat-hint">فعلي أعلى من المعتمد</small></a>
      <div class="stat"><span class="stat-label">الفترة المحاسبية</span><strong class="stat-value">٢٠٢٦/٠٩</strong><small class="stat-hint">فترة مفتوحة</small></div>
    </div>
  </section>

  <!-- ----------------------------------------------------------- ACTIONS -->
  <section id="actions" class="gallery-block">
    <header><h2>الإجراءات</h2>
      <p class="gallery-note">إجراء أساسي واحد لكل شاشة. الحد الأدنى لمنطقة اللمس ٤٠ بكسل. الإجراء الخطر لا يبدو كالأساسي أبدًا.</p></header>
    <div class="card">
      <div class="badge-row">
        ${BUTTONS.map(([cls, label]) => `<button class="${cls}">${label}</button>`).join('')}
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------------------- FORMS -->
  <section id="forms" class="gallery-block">
    <header><h2>النماذج</h2>
      <p class="gallery-note">كل حقل له تسمية، وتلميح يشرح لماذا يُطلب، وخطأ مربوط بالحقل نفسه لا رسالة عائمة.</p></header>
    <div class="card stack">
      <div class="form-grid">
        <label class="field">المبلغ
          <input type="text" inputmode="decimal" placeholder="٠٫٠٠" data-money />
          <span class="field-hint">بالجنيه المصري. تُقبل الأرقام العربية واللاتينية.</span>
        </label>
        <label class="field">العملة
          <select><option>EGP — جنيه مصري</option><option>USD — دولار أمريكي</option></select>
          <span class="field-hint">عملة الواقعة، لا عملة التقرير.</span>
        </label>
        <label class="field">المرجع الداخلي
          <input type="text" value="RE-2026-014" />
        </label>
        <label class="field">تاريخ الواقعة
          <input type="date" />
          <span class="field-error" id="err-date">التاريخ لاحق لتاريخ الإغلاق. اختر تاريخًا داخل فترة مفتوحة.</span>
        </label>
      </div>
      <div class="form-actions">
        <button>حفظ الواقعة</button>
        <button class="secondary" type="button">حفظ كمسودة</button>
        <button class="ghost cancel" type="button">إلغاء</button>
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------------------ TABLES -->
  <section id="tables" class="gallery-block">
    <header><h2>الجداول</h2>
      <p class="gallery-note">
        أعمدة المال محاذاة للنهاية وبأرقام جدولية. على الهاتف يتحول كل صف إلى بطاقة مُعنونة — نفس البيانات، بلا تمرير أفقي.
      </p>
    </header>
    <div class="table-wrap">
      <table class="table-stackable">
        <caption class="sr-only">التزامات التكلفة: المورد والفئة والمبلغ المعتمد والمدفوع والمتبقي</caption>
        <thead>
          <tr>
            <th scope="col">المورد</th>
            <th scope="col">الفئة</th>
            <th scope="col" class="num">المعتمد</th>
            <th scope="col" class="num">المدفوع</th>
            <th scope="col" class="num">المتبقي</th>
            <th scope="col">الحالة</th>
          </tr>
        </thead>
        <tbody>
          <tr><td data-label="المورد">شركة البناء المتحدة</td><td data-label="الفئة">إنشاءات</td><td class="num" data-label="المعتمد">١٬٢٠٠٬٠٠٠٫٠٠</td><td class="num" data-label="المدفوع">٨٠٠٬٠٠٠٫٠٠</td><td class="num" data-label="المتبقي">٤٠٠٬٠٠٠٫٠٠</td><td data-label="الحالة"><span class="status badge-warning tone-open">مدفوع جزئيًا</span></td></tr>
          <tr><td data-label="المورد">مكتب الاستشارات الهندسية</td><td data-label="الفئة">استشارات</td><td class="num" data-label="المعتمد">١٥٠٬٠٠٠٫٠٠</td><td class="num" data-label="المدفوع">١٥٠٬٠٠٠٫٠٠</td><td class="num" data-label="المتبقي">٠٫٠٠</td><td data-label="الحالة"><span class="status badge-success">مدفوع</span></td></tr>
          <tr><td data-label="المورد">مورد الحديد</td><td data-label="الفئة">مواد</td><td class="num" data-label="المعتمد">٦٤٠٬٠٠٠٫٠٠</td><td class="num" data-label="المدفوع">٠٫٠٠</td><td class="num" data-label="المتبقي">٦٤٠٬٠٠٠٫٠٠</td><td data-label="الحالة"><span class="status badge-danger">متأخر</span></td></tr>
        </tbody>
      </table>
    </div>
    <details class="card section-collapsible">
      <summary>حقول المفتاح والقيمة <span class="section-summary-desc">تُستخدم لعرض وقائع الأصل</span></summary>
      <div class="section-body">
        <dl class="facts">
          <div><dt>سند الملكية</dt><dd>مثبت · ٢٠٢٦/٠٣/١٢</dd></div>
          <div><dt>الحيازة</dt><dd>غير مثبتة</dd></div>
          <div><dt>حالة الدفع</dt><dd>مدفوع جزئيًا</dd></div>
          <div><dt>المساحة</dt><dd class="num">٤٬٢٠٠ م²</dd></div>
        </dl>
      </div>
    </details>
  </section>

  <!-- --------------------------------------------------------------- NAV -->
  <section id="nav" class="gallery-block">
    <header><h2>التنقل</h2>
      <p class="gallery-note">
        مساحة عمل المشروع كانت ١٣ تبويبًا متجاورًا بلا تصنيف — لا يمكن مسحها بصريًا.
        صارت أربع مجموعات مُسمّاة: <strong>القطاع · المال · الشفافية · الرقابة</strong>. المسارات والصلاحيات لم تتغير.
      </p>
    </header>
    <div class="frame sector-theme-real-estate">
      <p class="frame-label">مجموعات مساحة عمل مشروع عقاري</p>
      <div class="workspace-nav-grouped">
        <nav class="workspace-nav-group" aria-label="الأصول العقارية">
          <span class="workspace-nav-group-label">الأصول العقارية</span>
          <div class="workspace-nav tab-strip">
            <a class="workspace-nav-item current" href="#nav"><strong>نظرة عامة</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>الأصول العقارية</strong></a>
          </div>
        </nav>
        <nav class="workspace-nav-group" aria-label="المال">
          <span class="workspace-nav-group-label">المال</span>
          <div class="workspace-nav tab-strip">
            <a class="workspace-nav-item" href="#nav"><strong>رأس المال</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>التكاليف والنقدية</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>الإيراد والبيع</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>الإغلاق المالي</strong></a>
          </div>
        </nav>
        <nav class="workspace-nav-group" aria-label="الشفافية والاستيراد">
          <span class="workspace-nav-group-label">الشفافية والاستيراد</span>
          <div class="workspace-nav tab-strip">
            <a class="workspace-nav-item" href="#nav"><strong>شفافية المشاركين</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>الاستيراد والمطابقة</strong></a>
          </div>
        </nav>
        <nav class="workspace-nav-group" aria-label="الرقابة والحوكمة">
          <span class="workspace-nav-group-label">الرقابة والحوكمة</span>
          <div class="workspace-nav tab-strip">
            <a class="workspace-nav-item" href="#nav"><strong>المشتريات</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>الموازنة</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>مركز النزاهة</strong></a>
            <a class="workspace-nav-item" href="#nav"><strong>المخاطر والقرارات</strong></a>
          </div>
        </nav>
      </div>
    </div>
    <div class="frame">
      <p class="frame-label">تبويبات داخل الصفحة (مثبّتة أثناء التمرير)</p>
      <nav class="tab-strip tab-strip-inpage" style="position:static" aria-label="مثال">
        <a class="tab" href="#nav">الأصول والسيطرة</a>
        <a class="tab" href="#nav">التطوير</a>
        <a class="tab" href="#nav">ضبط التكلفة</a>
        <a class="tab" href="#nav">التصرف</a>
        <a class="tab" href="#nav">النتيجة المحققة</a>
      </nav>
    </div>
  </section>

  <!-- ------------------------------------------------------------- CARDS -->
  <section id="cards" class="gallery-block">
    <header><h2>بطاقات المشاريع</h2>
      <p class="gallery-note">
        البطاقة معاينة قرار لا بطاقة تسويق: الهوية، القطاع، الحالة، العملة، المرجع — وطريق واحد واضح للدخول.
        المحفظة ليست كائنًا قطاعيًا، لذا لا تستعير لون قطاع.
      </p>
    </header>
    <ul class="grid card-list">
      <li class="sector-theme-real-estate">
        <a class="project" href="#cards">
          <strong>برج النيل الإداري</strong>
          <div class="badge-row">${chip(SECTORS[0])}<span class="status badge-success">مرحلة التمويل</span><span class="status">EGP</span></div>
          <p class="muted">استحواذ واحتفاظ — المعادي، القاهرة</p>
          <small class="muted">المرجع: <code>RE-2026-014</code></small>
        </a>
      </li>
      <li class="sector-theme-agriculture">
        <a class="project" href="#cards">
          <strong>مزرعة وادي النطرون</strong>
          <div class="badge-row">${chip(SECTORS[1])}<span class="status">مسودة</span><span class="status">EGP</span></div>
          <p class="muted">دورات محاصيل — بطاطس وقمح</p>
          <small class="muted">المرجع: <code>AG-2026-003</code></small>
        </a>
      </li>
      <li class="sector-theme-livestock">
        <a class="project" href="#cards">
          <strong>موقع التسمين — بني سويف</strong>
          <div class="badge-row">${chip(SECTORS[2])}<span class="status badge-success">مرحلة التمويل</span><span class="status">EGP</span></div>
          <p class="muted">قطعان ودفعات قابلة للعد</p>
          <small class="muted">المرجع: <code>LS-2026-001</code></small>
        </a>
      </li>
      <li>
        <a class="project no-sector" href="#cards">
          <strong>محفظة الأصول المدارة</strong>
          <div class="badge-row"><span class="status status-active">نشطة</span><span class="status">٣ مشاريع مُسندة</span></div>
          <p class="muted">إطار إداري للمشاريع المستقلة — ليس صندوقًا ولا وعاء أموال مجمّعًا</p>
        </a>
      </li>
    </ul>
  </section>

  <!-- ------------------------------------------------------------ STATES -->
  <section id="states" class="gallery-block">
    <header><h2>الحالات</h2>
      <p class="gallery-note">
        سبع حالات مختلفة لا يجوز أن تبدو متشابهة: تحميل، فارغ، فارغ بعد التصفية، خطأ، بلا صلاحية، غير معرَّف بسياسة، وتنبيه.
      </p>
    </header>
    <div class="stack">
      <div class="stack" role="status" aria-busy="true">
        <div class="skeleton skeleton-title"></div>
        <div class="skeleton skeleton-nav"></div>
        <div class="skeleton skeleton-block"></div>
      </div>
      <div class="banner info">لا نعرض إجماليًا نقديًا موحدًا حتى تتوفر عملة تقرير وسعر صرف صالح لكل مشروع مطلوب تحويله.</div>
      <div class="banner warning">٣ سطور بنكية غير مطابقة. الإغلاق المالي متوقف حتى معالجتها.</div>
      <div class="banner" role="alert">حاصرات رقابة مفتوحة: قيود غير متوازنة (٢) · استثناءات مطابقة حرجة (١)</div>
      <section class="card stack empty">
        <h2>لا توجد مشاريع بعد</h2>
        <p class="muted">أدخل أول مشروع عبر المسار الموجّه. لن نعرض أرقامًا أو بيانات تجريبية.</p>
        <div class="page-actions center"><a class="button" href="#states">بدء إدخال المشروع</a></div>
      </section>
      <section class="card stack" role="alert">
        <h2>غير مصرح</h2>
        <p class="error">عضويتك الحالية لا تسمح بقراءة هذه الصفحة.</p>
        <div><a class="button" href="#states">العودة</a></div>
      </section>
      <div class="banner info">
        <strong>غير محدد بسياسة معتمدة</strong> — استحقاقات المشاركين محجوبة حتى تُحسم القرارات المعلّقة. لا يُعرض صفر ولا تقدير بديل.
      </div>
    </div>
  </section>

  <!-- ----------------------------------------------------------- CONFIRM -->
  <section id="confirm" class="gallery-block">
    <header><h2>الإجراءات الجسيمة</h2>
      <p class="gallery-note">
        قبل أي إجراء لا رجعة فيه، تُسمى الواقعة ويُشرح أثرها. الحماية ليست عائقًا في مسار التحويل — هي جزء من المنتج.
      </p>
    </header>
    <div class="confirm-panel">
      <h4>ترحيل قيد الإغلاق — الفترة ٢٠٢٦/٠٨</h4>
      <p class="confirm-consequence">
        سيُقفل الشهر وتُثبَّت لقطته. بعد الترحيل لا يمكن تعديل أي قيد في هذه الفترة إلا بمسار تصحيح معتمد يُنشئ قيدًا عكسيًا في فترة مفتوحة.
        البوابات المتحققة: ٧ من ٩.
      </p>
      <div class="form-actions">
        <button class="secondary">ترحيل الإغلاق</button>
        <button class="ghost cancel" type="button">تراجع</button>
      </div>
    </div>
    <div class="confirm-panel danger">
      <h4>عكس قيد مُرحّل</h4>
      <p class="confirm-consequence">
        القيد الأصلي أثّر على نقدية الفترة ٢٠٢٦/٠٧ بمبلغ ٢٥٠٬٠٠٠٫٠٠ ج.م. العكس ينشئ قيدًا مقابلًا بتاريخ اليوم ولا يحذف السجل الأصلي.
      </p>
      <div class="form-actions">
        <button class="danger">عكس القيد</button>
        <button class="ghost cancel" type="button">تراجع</button>
      </div>
    </div>
  </section>

  <!-- -------------------------------------------------------- RESPONSIVE -->
  <section id="responsive" class="gallery-block">
    <header><h2>الاستجابة</h2>
      <p class="gallery-note">
        الجوال ليس نسخة مصغّرة من سطح المكتب: التنقل ينطوي، والجداول تتحول إلى بطاقات مُعنونة،
        ويملك كل شاشة إجراء أساسي واحد بعرض كامل. غيّر عرض النافذة لترى الجدول أعلاه يتحول.
      </p>
    </header>
    <div class="frames">
      <div class="frame">
        <p class="frame-label">≤ 720px — شريط الإجراءات</p>
        <div class="form-actions"><button>حفظ الواقعة</button><button class="secondary">مسودة</button><button class="ghost cancel">إلغاء</button></div>
      </div>
      <div class="frame">
        <p class="frame-label">≤ 720px — شبكة الأرقام</p>
        <div class="stat-grid">
          <div class="stat"><span class="stat-label">النقدية</span><strong class="stat-value num">١٬٢٣٤٬٥٦٧٫٨٩</strong></div>
          <div class="stat"><span class="stat-label">الالتزامات</span><strong class="stat-value num">٣٢٠٬٠٠٠٫٠٠</strong></div>
        </div>
      </div>
    </div>
    <p class="gallery-note">
      نقاط الكسر: ١١٨٠ · ٩٦٠ · ٨٦٠ · ٧٢٠ بكسل. الحد الأدنى لمنطقة اللمس ٤٠ بكسل (٤٤ في قوائم الروابط).
      الحركة تُحترم عبر <code>prefers-reduced-motion</code>، والألوان عبر <code>forced-colors</code>، والطباعة تُخفي التنقل والإجراءات.
    </p>
  </section>

  <footer class="gallery-note" style="border-block-start:1px solid var(--line);padding-block-start:var(--sp-6)">
    بُنيت هذه الصفحة بواسطة <code>scripts/build-design-gallery.mjs</code> من <code>src/app/globals.css</code> مباشرة.
    لا توجد خطوط أو صور أو مكتبات خارجية — الملف مستقل بذاته ويعمل دون اتصال.
  </footer>

</div>
</body>
</html>
`;

const out = resolve(outDir, 'design-system.html');
writeFileSync(out, html, 'utf8');
console.log(`wrote ${out} (${(html.length / 1024).toFixed(1)} kB, css ${(css.length / 1024).toFixed(1)} kB inlined)`);

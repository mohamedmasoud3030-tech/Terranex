#!/usr/bin/env node
/**
 * R14 owner decision pack — INTERACTIVE, v3 (design overhaul).
 * One harmonious palette (pine family + single gold accent + neutrals),
 * a fixed spacing/margin scale, and a demo-link card (permanent URL).
 * Self-contained: no external resources. Arabic RTL. Prints to A4.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const SRC = 'docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md';
const OUT = process.argv[2] ?? '/home/user/R14_Owner_Decision_Pack_AR.html';
const DEMO_URL = 'https://terranex.vercel.app';
const md = readFileSync(SRC, 'utf8');

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const escAttr = (s) => esc(s).replace(/"/g, '&quot;');
const plain = (s) => s.replace(/\*\*/g, '');
const inline = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

function blocks(text) {
  const out = [];
  const lines = text.split('\n');
  let i = 0;
  const flushPara = (buf) => {
    const t = buf.join(' ').trim();
    if (t) out.push(`<p>${inline(t)}</p>`);
    buf.length = 0;
  };
  let para = [];
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim() || /^---+$/.test(l.trim())) { flushPara(para); i++; continue; }
    const ol = l.match(/^\s*(\d+)\.\s+(.*)$/);
    const ul = l.match(/^\s*-\s+(.*)$/);
    if (ol || ul) {
      flushPara(para);
      const re = ol ? /^\s*(\d+)\.\s+(.*)$/ : /^\s*-\s+(.*)$/;
      const items = [];
      while (i < lines.length) {
        const m = lines[i].match(re);
        if (!m) break;
        items.push(`<li>${inline(m[2] ?? m[1])}</li>`);
        i++;
      }
      out.push(`<${ol ? 'ol' : 'ul'}>${items.join('')}</${ol ? 'ol' : 'ul'}>`);
      continue;
    }
    if (l.trim().startsWith('|')) {
      flushPara(para);
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        const cells = lines[i].trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
        if (!cells.every((c) => /^-+$/.test(c) || c === '')) rows.push(cells);
        i++;
      }
      const [head, ...body] = rows;
      out.push(
        `<table><thead><tr>${head.map((c) => `<th>${inline(c)}</th>`).join('')}</tr></thead><tbody>` +
        body.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('') +
        `</tbody></table>`,
      );
      continue;
    }
    para.push(l.trim());
    i++;
  }
  flushPara(para);
  return out.join('\n');
}

const parts = md.split(/\n(?=## )/);
const meta = parts[0];
const introRaw = parts.find((p) => p.startsWith('## لماذا هذه الوثيقة؟')) ?? '';
const approvalRaw = parts.find((p) => p.startsWith('## كيف يُعتمد أي قرار')) ?? '';
const decisions = parts
  .filter((p) => /^## القرار /.test(p))
  .map((p) => {
    const head = p.match(/^## القرار [^(]+\((BD-\d+)\) — (.+)$/m);
    return { code: head[1], title: head[2], body: p.slice(p.indexOf('\n')) };
  });

const metaPairs = meta.split('\n').filter((l) => l.startsWith('**')).map((l) => {
  const m = l.match(/\*\*(.+?):\*\*\s*(.*)$/);
  return m ? [m[1], m[2]] : null;
}).filter(Boolean);

function optionRows(code, items) {
  const name = code.toLowerCase().replace('-', '') + '-o';
  return (
    '<div class="opts">' +
    items
      .map(
        (t, i) =>
          `<label class="opt"><input type="checkbox" name="${name}" value="${i + 1}" data-d="${code}" data-t="${escAttr(plain(t))}"><span class="opt-mark" aria-hidden="true"></span><span class="opt-text">${inline(t)}</span></label>`,
      )
      .join('') +
    '</div>'
  );
}

function yesNoRows(code, items, key) {
  return (
    '<ul class="yn-list">' +
    items
      .map((t, i) => {
        const n = `${key}-${i + 1}`;
        return (
          `<li><div class="yn"><span class="yn-q">${inline(t)}</span>` +
          `<span class="yn-acts">` +
          `<label class="yn-opt"><input type="radio" name="${n}" value="نعم" data-d="${code}" data-t="${escAttr(plain(t) + ' → نعم')}"><span>نعم</span></label>` +
          `<label class="yn-opt"><input type="radio" name="${n}" value="لا" data-d="${code}" data-t="${escAttr(plain(t) + ' → لا')}"><span>لا</span></label>` +
          `</span></div></li>`
        );
      })
      .join('') +
    '</ul>'
  );
}

function renderSub(sub, d) {
  const h = sub.match(/^### (.+)$/m)[1];
  let body = sub.slice(sub.indexOf('\n'));
  body = body.replace(/\n\*\*(قرار المالك|ملاحظات|تاريخ السريان):\*\*[^\n]*/g, '');

  const isOptions = /الخيارات|حددوا ما ينطبق/.test(h) || (d.code === 'BD-011' && /الجزء الثاني/.test(h));
  const isYesNo = d.code === 'BD-011' && /الجزء الثالث/.test(h);
  const edge = h.includes('السؤال') ? 'edge-q' : h.includes('تنبيه') ? 'edge-warn' : h.includes('المستند') ? 'edge-doc' : 'edge-neutral';
  const hideH = h.includes('السؤال') ? ' hide-h' : '';

  let inner;
  if (isOptions || isYesNo) {
    const lines = body.split('\n');
    const paras = [];
    const items = [];
    let buf = [];
    const flush = () => {
      const t = buf.join(' ').trim();
      if (t) paras.push(`<p>${inline(t)}</p>`);
      buf.length = 0;
    };
    for (const l of lines) {
      const m = l.match(/^\s*(?:\d+\.|-)\s+(.*)$/);
      if (m) { flush(); items.push(m[1].trim()); }
      else if (!l.trim() || /^---+$/.test(l.trim())) flush();
      else buf.push(l.trim());
    }
    flush();
    const rows = isYesNo
      ? yesNoRows(d.code, items, d.code.toLowerCase().replace('-', '') + '-yn')
      : optionRows(d.code, items);
    inner = paras.join('\n') + rows;
  } else {
    inner = blocks(body);
  }
  return `<div class="sub ${edge}${hideH}"><h4>${inline(h)}</h4>${inner}</div>`;
}

const decisionHtml = (d, idx) => {
  const subs = d.body.split(/\n(?=### )/).filter((s) => s.startsWith('### ')).map((s) => renderSub(s, d)).join('\n');
  return `
<section class="decision" data-code="${d.code}" data-title="${escAttr(d.title)}">
  <header class="d-head">
    <div class="d-num">${idx}</div>
    <div>
      <div class="d-code">${d.code}</div>
      <h2>${inline(d.title)}</h2>
    </div>
  </header>
  ${subs}
  <div class="answer">
    <div class="answer-title">✍ قرار المالك — علّموا ما ينطبق أعلاه ثم اكتبوا:</div>
    <div class="f"><label for="${d.code}-decision">نص القرار كما أقررتموه</label>
      <textarea id="${d.code}-decision" data-f="${d.code}-decision" data-d="${d.code}" rows="2" placeholder="اكتبوا القرار بصراحة — وإن كان يختلف من مشروع لآخر فاذكروا ذلك"></textarea></div>
    <div class="f"><label for="${d.code}-notes">ملاحظات / تفاصيل / أسئلة معلّقة</label>
      <textarea id="${d.code}-notes" data-f="${d.code}-notes" data-d="${d.code}" rows="2"></textarea></div>
    <div class="f f-date"><label for="${d.code}-date">تاريخ السريان</label>
      <input type="date" id="${d.code}-date" data-f="${d.code}-date" data-d="${d.code}"></div>
  </div>
  <div class="print-answer" data-p="${d.code}"></div>
</section>`;
};

const tocRows = decisions
  .map((d, i) => `<tr><td class="num">${i + 1}</td><td class="code">${d.code}</td><td>${inline(d.title)}</td><td class="st" id="st-${d.code}">—</td></tr>`)
  .join('');

const innerScript = `
(function () {
  var KEY = 'terranex-r14-pack';
  var store = null;
  try { localStorage.setItem('__t', '1'); localStorage.removeItem('__t'); store = localStorage; } catch (e) { store = null; }
  var saveNote = document.getElementById('save-note');
  if (!store && saveNote) {
    saveNote.textContent = 'الحفظ التلقائي غير متاح داخل هذه المعاينة — نزّلوا الملف وافتحوه في المتصفح ليُحفظ تلقائيًا، أو انسخوا الإجابات قبل الإغلاق';
    saveNote.classList.add('warn');
  }
  function inputs() { return Array.prototype.slice.call(document.querySelectorAll('[data-d]')); }
  function collect() {
    var st = {};
    inputs().forEach(function (el) {
      if (el.type === 'checkbox' || el.type === 'radio') {
        if (el.checked) st[el.name + '|' + el.value] = el.getAttribute('data-t') || el.value;
      } else if (el.value && el.value.trim()) {
        st[el.getAttribute('data-f')] = el.value.trim();
      }
    });
    return st;
  }
  function save() {
    if (store) { try { store.setItem(KEY, JSON.stringify(collect())); } catch (e) {} }
    updateProgress();
  }
  function restore() {
    if (!store) return;
    var raw = null;
    try { raw = store.getItem(KEY); } catch (e) { return; }
    if (!raw) return;
    var st;
    try { st = JSON.parse(raw); } catch (e) { return; }
    inputs().forEach(function (el) {
      if (el.type === 'checkbox' || el.type === 'radio') {
        if (st[el.name + '|' + el.value] !== undefined) el.checked = true;
      } else {
        var k = el.getAttribute('data-f');
        if (st[k]) el.value = st[k];
      }
    });
  }
  function decisionParts(sec) {
    var code = sec.getAttribute('data-code');
    var get = function (f) { var el = sec.querySelector('[data-f="' + code + '-' + f + '"]'); return el ? el.value.trim() : ''; };
    var sel = Array.prototype.slice.call(sec.querySelectorAll('input:checked'));
    var parts = [];
    if (sel.length) {
      var seen = {};
      var opts = [];
      sel.forEach(function (s) { var t = s.getAttribute('data-t') || s.value; if (!seen[t]) { seen[t] = 1; opts.push(t); } });
      parts.push('المحدد: ' + opts.join(' ؛ '));
    }
    if (get('decision')) parts.push('القرار: ' + get('decision'));
    if (get('notes')) parts.push('ملاحظات: ' + get('notes'));
    if (get('date')) parts.push('تاريخ السريان: ' + get('date'));
    return parts;
  }
  function updateProgress() {
    var done = {};
    inputs().forEach(function (el) {
      var ok = (el.type === 'checkbox' || el.type === 'radio') ? el.checked : !!(el.value && el.value.trim());
      if (ok) done[el.getAttribute('data-d')] = 1;
    });
    var codes = Object.keys(done);
    var n = codes.length;
    var pn = document.getElementById('prog-num');
    var pb = document.getElementById('prog-bar');
    if (pn) pn.textContent = n;
    if (pb) pb.style.width = (n / 12 * 100) + '%';
    document.querySelectorAll('td.st').forEach(function (td) { td.textContent = '—'; td.classList.remove('ok'); });
    codes.forEach(function (c) {
      var td = document.getElementById('st-' + c);
      if (td) { td.textContent = '✓'; td.classList.add('ok'); }
    });
  }
  function buildText() {
    var lines = ['حزمة قرارات R14 — إجابات مسجلة بتاريخ ' + new Date().toLocaleDateString('ar-EG'), ''];
    var any = false;
    document.querySelectorAll('section.decision').forEach(function (sec) {
      var parts = decisionParts(sec);
      if (parts.length) {
        any = true;
        lines.push(sec.getAttribute('data-code') + ' — ' + sec.getAttribute('data-title'));
        parts.forEach(function (p) { lines.push('  ' + p); });
        lines.push('');
      }
    });
    if (!any) lines.push('(لم تُسجَّل أي إجابة بعد)');
    return lines.join('\\n');
  }
  function escHtml(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function fillPrint() {
    document.querySelectorAll('section.decision').forEach(function (sec) {
      var box = sec.querySelector('.print-answer');
      if (!box) return;
      var parts = decisionParts(sec);
      box.innerHTML = parts.length
        ? '<div class="pa-inner"><strong>✍ الإجابة المسجلة:</strong><br>' + parts.map(escHtml).join('<br>') + '</div>'
        : '<div class="pa-inner none">— لم تُسجَّل إجابة —</div>';
    });
  }
  function flash(msg) {
    var t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(function () { t.classList.remove('show'); }, 2600);
  }
  function showFallback(txt) {
    var ov = document.getElementById('copy-fallback');
    var ta = document.getElementById('copy-area');
    if (!ov || !ta) return;
    ta.value = txt;
    ov.classList.add('show');
    ta.focus();
    ta.select();
  }
  document.addEventListener('input', save);
  document.addEventListener('change', save);
  document.getElementById('btn-copy').addEventListener('click', function () {
    var txt = buildText();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(txt).then(
        function () { flash('تم نسخ الإجابات — الصقوها في رسالة أو ملف'); },
        function () { showFallback(txt); }
      );
    } else showFallback(txt);
  });
  document.getElementById('copy-close').addEventListener('click', function () {
    document.getElementById('copy-fallback').classList.remove('show');
  });
  document.getElementById('btn-print').addEventListener('click', function () {
    fillPrint();
    try { window.print(); } catch (e) { flash('الطباعة غير متاحة هنا — افتحوا الملف في المتصفح'); }
  });
  window.addEventListener('beforeprint', fillPrint);
  var clearBtn = document.getElementById('btn-clear');
  var armTimer = null;
  clearBtn.addEventListener('click', function () {
    if (clearBtn.getAttribute('data-arm') !== '1') {
      clearBtn.setAttribute('data-arm', '1');
      clearBtn.textContent = 'متأكدون؟ اضغطوا مرة أخرى';
      armTimer = setTimeout(function () {
        clearBtn.removeAttribute('data-arm');
        clearBtn.textContent = 'مسح الكل';
      }, 4000);
      return;
    }
    clearTimeout(armTimer);
    clearBtn.removeAttribute('data-arm');
    clearBtn.textContent = 'مسح الكل';
    inputs().forEach(function (el) {
      if (el.type === 'checkbox' || el.type === 'radio') el.checked = false;
      else el.value = '';
    });
    if (store) { try { store.removeItem(KEY); } catch (e) {} }
    updateProgress();
    flash('تم مسح كل الإجابات');
  });
  restore();
  updateProgress();
})();
`;

const html = `<!doctype html>
<html dir="rtl" lang="ar">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>حزمة قرارات السياسة الاستثمارية — نسخة تفاعلية</title>
<style>
  /* ============ ONE PALETTE: pine family + one gold accent + neutrals ============ */
  :root {
    --pine-950: #07271D;
    --pine-900: #0A3527;
    --pine-800: #0C4534;
    --pine-700: #0E5C46;
    --pine-600: #12705A;
    --pine-200: #CFE3D9;
    --pine-100: #E4F0EA;
    --pine-50:  #F1F7F4;
    --gold-700: #8A6212;
    --gold-600: #A97A1E;
    --gold-500: #C79A3D;
    --gold-100: #F6EEDA;
    --gold-50:  #FBF6E9;
    --ink-900: #142019;
    --ink-700: #33413A;
    --ink-500: #5E6E66;
    --line:    #DEE7E1;
    --line-2:  #C7D5CC;
    --paper:   #F2F6F3;
    --sheet:   #FFFFFF;

    /* ============ FIXED SPACING & SIZE SCALE ============ */
    --sp-1: 4px;  --sp-2: 8px;  --sp-3: 12px; --sp-4: 16px;
    --sp-5: 20px; --sp-6: 24px; --sp-7: 32px; --sp-8: 40px;
    --r-lg: 12px; --r-md: 10px; --r-sm: 8px;
    --fs-xs: 12.5px; --fs-s: 14px; --fs-b: 16px; --fs-m: 17.5px; --fs-h: 21px; --fs-1: 30px;
    --content: 840px;
  }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0; background: var(--paper); color: var(--ink-900);
    font-family: "Segoe UI", Tahoma, "Noto Kufi Arabic", "Noto Sans Arabic", sans-serif;
    font-size: var(--fs-b); line-height: 1.9;
  }
  .page { max-width: var(--content); margin: 0 auto; padding: 96px var(--sp-7) var(--sp-8); }
  @media (max-width: 700px) { .page { padding: 150px var(--sp-4) var(--sp-6); } }

  /* ============ TOOLBAR ============ */
  .toolbar { position: fixed; top: 0; inset-inline: 0; z-index: 50; background: var(--pine-950); color: #E8F2ED; display: flex; align-items: center; gap: var(--sp-4); flex-wrap: wrap; padding: var(--sp-3) var(--sp-7); }
  .toolbar .prog { display: flex; align-items: center; gap: var(--sp-3); font-size: var(--fs-s); }
  .toolbar .prog strong { font-size: var(--fs-m); color: #fff; }
  .bar { width: 110px; height: 6px; background: rgba(255,255,255,.16); border-radius: 99px; overflow: hidden; }
  .bar i { display: block; height: 100%; width: 0; background: var(--gold-500); border-radius: 99px; transition: width .3s; }
  .toolbar .acts { display: flex; gap: var(--sp-2); flex-wrap: wrap; }
  .toolbar button { font: inherit; font-size: var(--fs-s); border: 1px solid rgba(255,255,255,.28); background: transparent; color: #E8F2ED; padding: 6px 16px; border-radius: var(--r-sm); cursor: pointer; }
  .toolbar button:hover { background: rgba(255,255,255,.1); }
  .toolbar button.danger { border-color: rgba(240,200,200,.45); color: #F2DCDC; }
  .toolbar button.danger[data-arm="1"] { background: #7A2E2E; border-color: #7A2E2E; color: #fff; }
  .save-note { font-size: var(--fs-xs); color: #A9C9BB; margin-inline-start: auto; }
  .save-note.warn { color: var(--gold-500); }

  /* ============ COVER ============ */
  .cover { background: linear-gradient(160deg, var(--pine-950) 0%, var(--pine-800) 100%); color: #E8F2ED; border-radius: var(--r-lg); padding: var(--sp-8); margin-bottom: var(--sp-6); }
  .cover .eyebrow { color: #9FC6B5; font-size: var(--fs-s); letter-spacing: .08em; margin-bottom: var(--sp-3); }
  .cover h1 { font-size: var(--fs-1); line-height: 1.4; margin: 0 0 var(--sp-4); color: #fff; font-weight: 800; }
  .cover .sub { color: #C9DFD5; margin: 0; max-width: 56ch; }
  .cover .interactive-note { color: var(--gold-500); font-size: var(--fs-s); font-weight: 700; margin: var(--sp-4) 0 0; }
  .meta { width: 100%; border-collapse: collapse; margin: var(--sp-6) 0 0; font-size: var(--fs-xs); }
  .meta td { padding: var(--sp-2) var(--sp-3); border-top: 1px solid rgba(232,242,237,.18); vertical-align: top; }
  .meta td:first-child { color: #9FC6B5; white-space: nowrap; width: 150px; }

  /* ============ DEMO LINK CARD ============ */
  .demo { background: var(--sheet); border: 1px solid var(--line-2); border-radius: var(--r-lg); padding: var(--sp-6); margin-bottom: var(--sp-6); display: flex; gap: var(--sp-5); align-items: center; flex-wrap: wrap; }
  .demo-icon { flex: none; width: 52px; height: 52px; border-radius: var(--r-md); background: var(--pine-100); color: var(--pine-700); display: flex; align-items: center; justify-content: center; font-size: 24px; }
  .demo-body { flex: 1; min-width: 240px; }
  .demo-body h3 { margin: 0 0 var(--sp-1); font-size: var(--fs-m); color: var(--pine-900); }
  .demo-body p { margin: 0; color: var(--ink-500); font-size: var(--fs-s); }
  .demo-cta { flex: none; display: flex; flex-direction: column; align-items: center; gap: var(--sp-2); }
  .demo-cta a.btn-demo { display: inline-block; background: var(--pine-700); color: #fff; text-decoration: none; font-weight: 700; font-size: var(--fs-s); padding: 10px 26px; border-radius: var(--r-sm); border: 1px solid var(--pine-800); }
  .demo-cta a.btn-demo:hover { background: var(--pine-600); }
  .demo-cta .url { font-size: var(--fs-xs); color: var(--ink-500); direction: ltr; unicode-bidi: embed; max-width: 250px; overflow-wrap: anywhere; }

  /* ============ WHY NOW ============ */
  .why-now { background: var(--pine-50); border: 1px solid var(--pine-200); border-radius: var(--r-lg); padding: var(--sp-5) var(--sp-6); margin: 0 0 var(--sp-6); }
  .why-now h3 { margin: 0 0 var(--sp-3); color: var(--pine-900); font-size: var(--fs-h); }
  .why-now p { margin: 0 0 var(--sp-3); }
  .why-now p:last-child { margin: 0; }

  h2.section { font-size: var(--fs-h); color: var(--pine-900); margin: var(--sp-7) 0 var(--sp-4); }
  .intro-card, .approval { background: var(--sheet); border: 1px solid var(--line); border-radius: var(--r-lg); padding: var(--sp-5) var(--sp-6); }

  /* ============ TABLES ============ */
  table { width: 100%; border-collapse: collapse; background: var(--sheet); font-size: var(--fs-s); }
  th, td { border: 1px solid var(--line); padding: var(--sp-3); text-align: start; vertical-align: top; }
  th { background: var(--pine-50); color: var(--pine-900); }
  td.num { text-align: center; font-weight: 700; color: var(--pine-700); white-space: nowrap; }
  td.code { font-weight: 700; white-space: nowrap; color: var(--ink-500); font-size: var(--fs-xs); }
  td.st { text-align: center; font-weight: 800; color: var(--line-2); white-space: nowrap; }
  td.st.ok { color: var(--pine-700); }

  /* ============ DECISION CARDS ============ */
  .decision { background: var(--sheet); border: 1px solid var(--line-2); border-radius: var(--r-lg); padding: var(--sp-6); margin: var(--sp-6) 0; }
  .d-head { display: flex; gap: var(--sp-4); align-items: flex-start; border-bottom: 1px solid var(--pine-200); padding-bottom: var(--sp-4); margin-bottom: var(--sp-4); }
  .d-num { background: var(--pine-700); color: #fff; min-width: 46px; height: 46px; border-radius: var(--r-md); display: flex; align-items: center; justify-content: center; font-size: var(--fs-m); font-weight: 800; }
  .d-code { color: var(--ink-500); font-size: var(--fs-xs); font-weight: 700; letter-spacing: .05em; }
  .decision h2 { margin: var(--sp-1) 0 0; font-size: var(--fs-h); color: var(--pine-900); line-height: 1.5; }

  /* sub-boxes: ONE geometry, only the edge colour changes */
  .sub { margin: var(--sp-4) 0; background: var(--pine-50); border-radius: var(--r-sm); padding: var(--sp-4) var(--sp-5); border-inline-start: 3px solid var(--line-2); }
  .sub h4 { margin: 0 0 var(--sp-2); font-size: var(--fs-b); color: var(--ink-700); }
  .sub.edge-q { border-inline-start-color: var(--pine-700); }
  .sub.edge-warn { border-inline-start-color: var(--gold-600); background: var(--gold-50); }
  .sub.edge-doc { border-inline-start: 3px dashed var(--line-2); background: var(--sheet); }
  .sub.hide-h h4 { display: none; }
  .sub.edge-q p { margin: 0; font-weight: 600; color: var(--pine-900); }
  .sub p { margin: var(--sp-2) 0; }
  ol, ul { margin: var(--sp-2) 0; padding-inline-start: 24px; }
  li { margin: var(--sp-2) 0; }

  /* ============ TICKABLE OPTIONS ============ */
  .opts { display: grid; gap: var(--sp-2); margin: var(--sp-3) 0; }
  .opt { display: flex; gap: var(--sp-3); align-items: flex-start; background: var(--sheet); border: 1.5px solid var(--line); border-radius: var(--r-sm); padding: var(--sp-3) var(--sp-4); cursor: pointer; transition: border-color .15s, background .15s; }
  .opt:hover { border-color: var(--pine-600); }
  .opt input { position: absolute; opacity: 0; width: 1px; height: 1px; }
  .opt-mark { flex: none; width: 22px; height: 22px; border: 2px solid var(--line-2); border-radius: 6px; margin-top: 4px; display: inline-flex; align-items: center; justify-content: center; font-size: 15px; font-weight: 900; color: transparent; background: var(--sheet); }
  .opt input:checked ~ .opt-mark { background: var(--pine-700); border-color: var(--pine-700); color: #fff; }
  .opt input:checked ~ .opt-mark::after { content: "✓"; }
  .opt input:focus-visible ~ .opt-mark { outline: 3px solid var(--gold-600); outline-offset: 2px; }
  .opt:has(input:checked) { border-color: var(--pine-700); background: var(--pine-50); }
  .opt-text { flex: 1; }

  /* ============ YES/NO ============ */
  .yn-list { list-style: none; padding: 0; margin: var(--sp-3) 0; display: grid; gap: var(--sp-2); }
  .yn { display: flex; justify-content: space-between; align-items: center; gap: var(--sp-3); background: var(--sheet); border: 1.5px solid var(--line); border-radius: var(--r-sm); padding: var(--sp-3) var(--sp-4); flex-wrap: wrap; }
  .yn-acts { display: flex; gap: var(--sp-2); }
  .yn-opt { display: inline-flex; align-items: center; gap: var(--sp-2); border: 1.5px solid var(--line-2); border-radius: 99px; padding: 4px 16px; cursor: pointer; font-size: var(--fs-s); font-weight: 700; background: var(--sheet); color: var(--ink-700); }
  .yn-opt input { position: absolute; opacity: 0; width: 1px; height: 1px; }
  .yn-opt:has(input:checked) { background: var(--pine-100); border-color: var(--pine-700); color: var(--pine-900); }
  .yn-opt input:focus-visible + span { outline: 3px solid var(--gold-600); outline-offset: 2px; border-radius: 4px; }

  /* ============ ANSWER BOX ============ */
  .answer { margin-top: var(--sp-5); border: 1.5px solid var(--pine-700); border-radius: var(--r-md); padding: var(--sp-4) var(--sp-5); background: var(--pine-50); }
  .answer-title { font-weight: 800; color: var(--pine-900); margin-bottom: var(--sp-3); font-size: var(--fs-b); }
  .f { margin: var(--sp-3) 0; display: grid; gap: var(--sp-2); }
  .f label { font-weight: 700; color: var(--ink-700); font-size: var(--fs-s); }
  .f textarea, .f input[type="date"] { font: inherit; width: 100%; border: 1.5px solid var(--line-2); border-radius: var(--r-sm); padding: var(--sp-3); background: var(--sheet); color: var(--ink-900); resize: vertical; }
  .f textarea:focus, .f input:focus { outline: 3px solid var(--gold-500); outline-offset: 0; border-color: var(--pine-700); }
  .f-date input { max-width: 240px; }

  .print-answer { display: none; }

  .approval { border-inline-start: 4px solid var(--pine-900); }
  footer { margin-top: var(--sp-8); color: var(--ink-500); font-size: var(--fs-xs); text-align: center; border-top: 1px solid var(--line); padding-top: var(--sp-4); }

  /* ============ TOAST + FALLBACK ============ */
  #toast { position: fixed; bottom: var(--sp-6); inset-inline-start: 50%; transform: translateX(50%) translateY(80px); background: var(--pine-950); color: #fff; padding: 10px 24px; border-radius: 99px; font-size: var(--fs-s); transition: transform .25s; z-index: 90; }
  #toast.show { transform: translateX(50%) translateY(0); }
  #copy-fallback { position: fixed; inset: 0; background: rgba(7,39,29,.55); display: none; align-items: center; justify-content: center; z-index: 80; padding: var(--sp-5); }
  #copy-fallback.show { display: flex; }
  .cf-box { background: var(--sheet); border-radius: var(--r-lg); padding: var(--sp-5); max-width: 640px; width: 100%; }
  .cf-box h3 { margin: 0 0 var(--sp-2); color: var(--pine-900); }
  .cf-box p { margin: 0 0 var(--sp-3); color: var(--ink-500); font-size: var(--fs-s); }
  #copy-area { width: 100%; height: 220px; font: inherit; font-size: var(--fs-s); border: 1.5px solid var(--line-2); border-radius: var(--r-sm); padding: var(--sp-3); direction: rtl; }
  .cf-box button { margin-top: var(--sp-3); font: inherit; background: var(--pine-700); color: #fff; border: 0; border-radius: var(--r-sm); padding: var(--sp-2) var(--sp-5); cursor: pointer; }

  /* ============ PRINT ============ */
  @page { margin: 14mm; }
  @media print {
    body { background: #fff; font-size: 13px; }
    .page { padding: 0; max-width: none; }
    .toolbar, .answer, #toast, #copy-fallback { display: none !important; }
    .opt input, .yn-opt input { display: none; }
    .opt-mark { display: none; }
    .opt:has(input:checked) { border: 2px solid var(--pine-700); background: var(--pine-50); }
    .opt:has(input:checked) .opt-text::before { content: "✓ "; color: var(--pine-700); font-weight: 900; }
    .print-answer { display: block; margin-top: var(--sp-4); }
    .pa-inner { background: var(--pine-50); border: 1.5px solid var(--pine-700); border-radius: var(--r-sm); padding: var(--sp-3) var(--sp-4); }
    .pa-inner.none { background: none; border: 1px dashed var(--line-2); color: var(--ink-500); text-align: center; }
    .decision { page-break-inside: avoid; }
    .demo { page-break-inside: avoid; }
  }
</style>
</head>
<body>

<div class="toolbar">
  <div class="prog"><strong id="prog-num">0</strong>/12 تمّت الإجابة <div class="bar"><i id="prog-bar"></i></div></div>
  <div class="acts">
    <button id="btn-copy" type="button">نسخ الإجابات</button>
    <button id="btn-print" type="button">طباعة / حفظ PDF</button>
    <button id="btn-clear" type="button" class="danger">مسح الكل</button>
  </div>
  <div class="save-note" id="save-note">يُحفظ تلقائيًا في هذا المتصفح</div>
</div>

<div class="page">

<div class="cover">
  <div class="eyebrow">تيرانكس — نظام تشغيل الاستثمار</div>
  <h1>حزمة قرارات السياسة الاستثمارية</h1>
  <p class="sub">اثنا عشر قرارًا لا يستطيع النظام — ولا أي مبرمج — أن يقررها بالنيابة عنكم، لأنها تخص شكل شركتكم وعقودكم وطريقة توزيع الربح والخسارة.</p>
  <p class="interactive-note">✎ نسخة تفاعلية: علّموا ما ينطبق واكتبوا قراراتكم مباشرة — ثم انسخوا الإجابات أو اطبعوها.</p>
  <table class="meta">
    ${metaPairs.map(([k, v]) => `<tr><td>${inline(k)}</td><td>${inline(v)}</td></tr>`).join('\n    ')}
  </table>
</div>

<div class="demo">
  <div class="demo-icon" aria-hidden="true">🧭</div>
  <div class="demo-body">
    <h3>جرّبوا النظام قبل اتخاذ القرارات</h3>
    <p>افتحوا النسخة التجريبية الحيّة واستعرضوا المشاريع والمشتريات والتقارير بأنفسكم — رؤية الشاشات تساعد على اتخاذ قرارات أدق. بيانات الدخول تُسلَّم مع هذه الوثيقة.</p>
  </div>
  <div class="demo-cta">
    <a class="btn-demo" href="${DEMO_URL}" target="_blank" rel="noopener">فتح النسخة التجريبية ↗</a>
    <span class="url">${DEMO_URL}</span>
  </div>
</div>

<div class="why-now">
  <h3>لماذا نطلب هذه الإجابات الآن؟</h3>
  <p>اكتمل بناء النظام فنيًا في كل ما لا يعتمد على قراراتكم: المشاريع، والمصروفات، والإيرادات، والمشتريات، والبنوك، والتسويات، والإقفال، والتقارير — وكل مشروع بحسابات مستقلة تمامًا، مع سجل تدقيق كامل.</p>
  <p><strong>ما تبقّى معلَّقًا بالكامل هو اقتصاديات المستثمرين</strong> (الملكية، توزيع الأرباح، كشوف الحسابات) — وهي مصمّمة عمدًا كي تبقى «خاملة بأمان» حتى تُسجَّل إجاباتكم الصريحة، لأن أي افتراض فيها قد ينتج أرقامًا غير صحيحة قانونيًا أو محاسبيًا.</p>
  <p>كل إجابة تُسجَّل تفتح الجزء المقابل لها فورًا. الإجابات الجزئية مرحّب بها: سجّلوا ما حُسم، وأبقوا ما يحتاج محاسبًا أو مستشارًا قانونيًا مفتوحًا.</p>
</div>

<h2 class="section">الأسئلة الاثنا عشر — علّموا ✓ عند الإجابة</h2>
<table>
  <thead><tr><th>#</th><th>البند</th><th>الموضوع</th><th>الحالة</th></tr></thead>
  <tbody>${tocRows}</tbody>
</table>

<h2 class="section">قبل البدء — اقرأوا هذا</h2>
<div class="intro-card">
${blocks(introRaw.replace(/^## .+\n/, ''))}
</div>

${decisions.map((d, i) => decisionHtml(d, i + 1)).join('\n')}

<h2 class="section">كيف يُعتمد أي قرار (شرط الإقفال)</h2>
<div class="approval">
${blocks(approvalRaw.replace(/^## .+\n/, ''))}
</div>

<footer>
  هذه الوثيقة مولّدة من المصدر الموثق <code>docs/R14_TARGET_COMPANY_DECISION_PACK_AR.md</code> في مستودع Terranex — أي تعديل يُسجَّل هناك أولًا.
</footer>

</div>

<div id="toast" role="status"></div>
<div id="copy-fallback">
  <div class="cf-box">
    <h3>الإجابات كنص جاهز للنسخ</h3>
    <p>حددوا الكل ثم انسخوا (Ctrl+A ثم Ctrl+C داخل الصندوق) والصقوا الناتج في رسالة أو ملف.</p>
    <textarea id="copy-area" readonly></textarea>
    <button id="copy-close" type="button">إغلاق</button>
  </div>
</div>

<script>${innerScript}</script>
</body>
</html>`;

writeFileSync(OUT, html);
console.log(`wrote ${OUT} (${(html.length / 1024).toFixed(0)} KB)`);
console.log(`demo url: ${DEMO_URL}`);

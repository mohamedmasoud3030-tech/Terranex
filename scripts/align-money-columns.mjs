#!/usr/bin/env node
/**
 * Adds `className="num"` to table cells whose column holds a monetary amount
 * or a comparable quantity, so the figures align and can be compared at a
 * glance (tabular figures + end alignment, per the design system).
 *
 * Which columns are financial is decided by the column's own Arabic header,
 * read from the same <thead> — never guessed from the cell contents.
 *
 * Idempotent. Run with --check to report without writing.
 *
 * Usage: node ./scripts/align-money-columns.mjs [--check]
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const CHECK = process.argv.includes('--check');

/** Header words that mean the column is a figure an operator compares. */
const MONEY_WORDS = [
  'نقدية', 'مدفوع', 'المدفوع', 'تكلفة', 'إيراد', 'الإيراد', 'مبلغ', 'المبلغ',
  'مقابل', 'رصيد', 'الأرصدة', 'التزام', 'الالتزامات', 'التزامات', 'ميزانية',
  'الميزانية', 'الفعلي', 'الملتزم', 'الانحراف', 'تقييم', 'التقييم',
  'مساهمة', 'المساهمات', 'التزام رأسمالي', 'مستحق', 'مستحقات', 'ذمم', 'فاتورة',
  'قيمة', 'القيمة', 'محوّل', 'متبقي', 'المتبقي', 'سعر', 'الاجمالي', 'الإجمالي',
  'محفوظ', 'معتمد', 'المتأخر', 'متأخرات', 'ضمان', 'التزامات PO', 'FAC',
];

/** Header words that must never be right-aligned even if they overlap. */
const NOT_MONEY = ['الحالة', 'القطاع', 'المرجع', 'التاريخ', 'المورد', 'الاسم', 'الوصف', 'الدليل', 'الملاحظات', 'ملاحظات'];

const files = execSync("find src -name '*.tsx' -path '*app*'", { encoding: 'utf8' })
  .trim()
  .split('\n')
  .filter(Boolean);

function headerIsMoney(text) {
  const clean = text.replace(/<[^>]*>/g, '').trim();
  if (!clean) return false;
  if (NOT_MONEY.some((word) => clean.includes(word))) return false;
  return MONEY_WORDS.some((word) => clean.includes(word));
}

let totalHeaders = 0;
let totalCells = 0;
const report = [];

for (const file of files) {
  const source = readFileSync(file, 'utf8');
  let out = source;

  // Work table by table so header/cell indices line up.
  const tableRe = /<table\b[^>]*>([\s\S]*?)<\/table>/g;
  out = out.replace(tableRe, (table) => {
    const headMatch = table.match(/<thead>([\s\S]*?)<\/thead>/);
    if (!headMatch) return table;
    const headRow = headMatch[1].match(/<tr>([\s\S]*?)<\/tr>/);
    if (!headRow) return table;

    const headers = [...headRow[1].matchAll(/<th\b[^>]*>([\s\S]*?)<\/th>/g)];
    if (!headers.length) return table;

    const moneyIndex = new Set();
    headers.forEach((header, index) => {
      const attrs = header[0].slice(0, header[0].indexOf('>'));
      const already = /\bclass(Name)?=/.test(attrs);
      if (headerIsMoney(header[1]) && !already) moneyIndex.add(index);
    });
    if (!moneyIndex.size) return table;

    totalHeaders += moneyIndex.size;

    let next = table;
    // Tag the headers themselves.
    headers.forEach((header, index) => {
      if (!moneyIndex.has(index)) return;
      const whole = header[0];
      const tagged = whole.replace(/<th\b/, '<th className="num"');
      next = next.replace(whole, tagged);
    });

    // Tag the body cells at the same positions. Most cells already carry a
    // `data-label` for the phone stack layout, so an existing className is
    // appended to rather than treated as a reason to skip.
    next = next.replace(/<tr\b[^>]*>([\s\S]*?)<\/tr>/g, (row, inner) => {
      if (/<th\b/.test(inner)) return row; // header row already handled
      const cells = [...inner.matchAll(/<td\b[^>]*>[\s\S]*?<\/td>/g)];
      if (!cells.length) return row;
      let patched = row;
      cells.forEach((cell, index) => {
        if (!moneyIndex.has(index)) return;
        const whole = cell[0];
        const open = whole.slice(0, whole.indexOf('>') + 1);
        if (/\bnum\b/.test(open)) return; // already aligned
        // A dynamic className={…} can be any string at runtime; appending to
        // it would change behaviour, so those cells are left to their owner.
        if (/\bclass(Name)?=\{/.test(open)) return;
        const existing = open.match(/className="([^"]*)"/);
        const tagged = existing
          ? whole.replace(open, open.replace(existing[0], `className="${existing[1]} num"`))
          : whole.replace(/<td\b/, '<td className="num"');
        patched = patched.replace(whole, tagged);
        totalCells += 1;
      });
      return patched;
    });

    return next;
  });

  if (out !== source) {
    report.push(file);
    if (!CHECK) writeFileSync(file, out, 'utf8');
  }
}

console.log(
  `${CHECK ? '[check] ' : ''}${report.length} file(s), ${totalHeaders} money column(s), ${totalCells} cell(s) tagged`,
);
for (const file of report) console.log('  ', file);

// One-off codemod: for each <table> whose <thead> has plain-text <th> cells,
// add data-label="<header>" to positional <td> cells in <tbody> rows, and
// mark the table `table-stackable`. Only touches tables where every <th> is
// static text and each <td> can be matched positionally; anything else is
// skipped and reported.
import { readFileSync, writeFileSync } from 'node:fs';
const files = process.argv.slice(2);
for (const file of files) {
  let src = readFileSync(file, 'utf8');
  let changed = 0, skipped = 0;
  src = src.replace(/<table>([\s\S]*?)<\/table>/g, (whole, inner) => {
    const head = inner.match(/<thead>([\s\S]*?)<\/thead>/);
    if (!head) { skipped++; return whole; }
    const ths = [...head[1].matchAll(/<th[^>]*>([\s\S]*?)<\/th>/g)].map((m) => m[1].trim());
    if (ths.length === 0 || ths.some((t) => /[{<]/.test(t))) { skipped++; return whole; }
    const bodyIdx = inner.indexOf('<tbody>');
    if (bodyIdx < 0) { skipped++; return whole; }
    let body = inner.slice(bodyIdx);
    let ok = true;
    body = body.replace(/<tr(\s[^>]*)?>([\s\S]*?)<\/tr>/g, (row, attrs = '', cells) => {
      let i = 0;
      const out = cells.replace(/<td(?=[\s>])/g, (m) => {
        const label = ths[i++];
        if (label === undefined) { ok = false; return m; }
        return `<td data-label="${label.replace(/"/g, '&quot;')}"`;
      });
      if (i !== ths.length) ok = false;
      return `<tr${attrs}>${out}</tr>`;
    });
    if (!ok) { skipped++; return whole; }
    changed++;
    return `<table className="table-stackable">${inner.slice(0, bodyIdx)}${body}</table>`;
  });
  writeFileSync(file, src);
  console.log(file.replace(/.*\(app\)\//, ''), 'changed', changed, 'skipped', skipped);
}

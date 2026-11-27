// Bank statement text parsing for the owner import page. Pure and unit-tested.
// Accepts CSV/TSV/semicolon exports (including Excel "Save as CSV") with
// Arabic or English headers, Arabic-Indic digits, and separate debit/credit
// columns, and emits rows in the shape the existing importBankStatement
// command already accepts.

export type ParsedStatementLine = {
  transactionDate: string; // ISO YYYY-MM-DD
  amount: string; // signed major units, Latin digits
  currency: string;
  description: string;
  providerReference: string;
};

export type StatementParseResult =
  | { ok: true; lines: ParsedStatementLine[]; skipped: number }
  | { ok: false; error: string };

const HEADER_ALIASES: Record<string, readonly string[]> = {
  date: ['date', 'transaction date', 'value date', 'التاريخ', 'تاريخ', 'تاريخ العملية', 'تاريخ القيمة'],
  amount: ['amount', 'المبلغ', 'قيمة', 'قيمة العملية', 'المبلغ بالعملة'],
  description: ['description', 'details', 'narrative', 'البيان', 'بيان', 'التفاصيل', 'تفاصيل', 'الوصف'],
  currency: ['currency', 'العملة', 'عملة'],
  reference: ['reference', 'ref', 'reference number', 'المرجع', 'رقم المرجع', 'رقم الحركة'],
  debit: ['debit', 'withdrawal', 'مدين', 'خصم', 'سحب', 'منصرف'],
  credit: ['credit', 'deposit', 'دائن', 'إيداع', 'ايداع', 'إضافة', 'اضافة', 'وارد'],
};

function normalizeDigits(value: string): string {
  return value
    .replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
    .replace(/[۰-۹]/g, (d) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)));
}

/** Parse a localized amount: strips thousands separators, keeps sign and decimals. */
export function parseAmount(value: string): string | null {
  let v = normalizeDigits(value).trim();
  if (!v) return null;
  let negative = false;
  if (/^\(.*\)$/.test(v)) {
    negative = true;
    v = v.slice(1, -1);
  }
  v = v.replace(/٫/g, '.').replace(/[٬,\s]/g, '').replace('−', '-');
  if (v.startsWith('-')) {
    negative = true;
    v = v.slice(1);
  }
  if (!/^\d+(\.\d{1,4})?$/.test(v)) return null;
  return `${negative ? '-' : ''}${v}`;
}

/** Parse day-first or ISO dates into ISO YYYY-MM-DD. */
export function parseDate(value: string): string | null {
  const v = normalizeDigits(value).trim();
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(v);
  if (iso) return toIso(+iso[1], +iso[2], +iso[3]);
  const dmy = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(v);
  if (dmy) return toIso(+dmy[3], +dmy[2], +dmy[1]); // day-first, the Egyptian convention
  return null;
}

function toIso(year: number, month: number, day: number): string | null {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const d = new Date(Date.UTC(year, month - 1, day));
  if (d.getUTCFullYear() !== year || d.getUTCMonth() !== month - 1 || d.getUTCDate() !== day) return null;
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

function detectDelimiter(headerLine: string): string {
  const candidates = ['\t', ';', ','];
  let best = ',';
  let bestCount = 0;
  for (const c of candidates) {
    const count = headerLine.split(c).length;
    if (count > bestCount) {
      best = c;
      bestCount = count;
    }
  }
  return best;
}

type ColumnMap = { date: number; description: number; currency: number; reference: number; amount: number; debit: number; credit: number };

function mapHeaders(headers: readonly string[]): ColumnMap | null {
  const find = (kind: keyof typeof HEADER_ALIASES): number =>
    headers.findIndex((h) => HEADER_ALIASES[kind].includes(normalizeDigits(h).trim().toLowerCase()));
  const map: ColumnMap = {
    date: find('date'),
    description: find('description'),
    currency: find('currency'),
    reference: find('reference'),
    amount: find('amount'),
    debit: find('debit'),
    credit: find('credit'),
  };
  if (map.date < 0 || map.description < 0) return null;
  if (map.amount < 0 && (map.debit < 0 || map.credit < 0)) return null;
  return map;
}

/**
 * Parse statement text. The first non-empty row must be a header row.
 * `defaultCurrency` is used when the file has no currency column.
 */
export function parseStatementText(text: string, defaultCurrency: string): StatementParseResult {
  const rows = text
    .split(/\r?\n/)
    .map((r) => r.trim())
    .filter((r) => r.length > 0);
  if (rows.length < 2) {
    return { ok: false, error: 'الملف فاضي أو مفيهوش غير صف العناوين.' };
  }
  const delimiter = detectDelimiter(rows[0]);
  const headers = rows[0].split(delimiter).map((h) => h.trim());
  const map = mapHeaders(headers);
  if (!map) {
    return {
      ok: false,
      error:
        'مش قادر أتعرف على الأعمدة. المطلوب على الأقل: التاريخ والبيان، وإما عمود مبلغ واحد أو عمودي مدين/دائن. الأعمدة المدعومة بالعربي أو الإنجليزي.',
    };
  }
  const lines: ParsedStatementLine[] = [];
  let skipped = 0;
  for (let i = 1; i < rows.length; i++) {
    const cells = rows[i].split(delimiter).map((c) => c.trim());
    const date = parseDate(cells[map.date] ?? '');
    const description = (cells[map.description] ?? '').replace(/[,;]/g, ' ').trim();
    const currency = map.currency >= 0 ? (cells[map.currency] ?? '').trim().toUpperCase() : defaultCurrency;
    let amount: string | null = null;
    if (map.amount >= 0) {
      amount = parseAmount(cells[map.amount] ?? '');
    } else {
      const debit = parseAmount(cells[map.debit] ?? '');
      const credit = parseAmount(cells[map.credit] ?? '');
      if (debit !== null && credit === null) amount = `-${debit.replace(/^-/, '')}`;
      else if (credit !== null && debit === null) amount = credit;
      else if (credit !== null && debit !== null) amount = null; // both filled: ambiguous row
    }
    if (!date || !amount || !/^[A-Z]{3}$/.test(currency) || description.length === 0) {
      skipped++;
      continue;
    }
    lines.push({
      transactionDate: date,
      amount,
      currency,
      description: description.slice(0, 200),
      providerReference: map.reference >= 0 ? (cells[map.reference] ?? '').trim().slice(0, 80) : '',
    });
  }
  if (lines.length === 0) {
    return { ok: false, error: `مفيش ولا سطر صالح. اتخطى ${skipped} سطر فيهم نقص أو صيغة غير مفهومة.` };
  }
  return { ok: true, lines, skipped };
}

/** Serialize to the line format the existing importBankStatement command accepts. */
export function serializeForImport(lines: readonly ParsedStatementLine[]): string {
  return lines
    .map((l) => [l.transactionDate, l.amount, l.currency, l.description.replace(/,/g, ' '), l.providerReference].join(','))
    .join('\n');
}

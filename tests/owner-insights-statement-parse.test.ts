import { describe, expect, it } from 'vitest';
import { parseAmount, parseDate, parseStatementText, serializeForImport } from '@/features/owner-insights/statement-parse';

describe('parseAmount', () => {
  it('parses plain and signed values', () => {
    expect(parseAmount('1500')).toBe('1500');
    expect(parseAmount('-1500.50')).toBe('-1500.50');
  });
  it('strips thousands separators and converts Arabic-Indic digits', () => {
    expect(parseAmount('1,500,000')).toBe('1500000');
    expect(parseAmount('١٥٠٠٫٥٠')).toBe('1500.50');
  });
  it('reads parentheses as negative', () => {
    expect(parseAmount('(2500)')).toBe('-2500');
  });
  it('rejects empty and malformed values', () => {
    expect(parseAmount('')).toBeNull();
    expect(parseAmount('abc')).toBeNull();
  });
});

describe('parseDate', () => {
  it('accepts ISO dates', () => {
    expect(parseDate('2026-11-27')).toBe('2026-11-27');
  });
  it('reads slash dates day-first (Egyptian convention)', () => {
    expect(parseDate('27/11/2026')).toBe('2026-11-27');
    expect(parseDate('05/01/2026')).toBe('2026-01-05');
  });
  it('rejects impossible dates', () => {
    expect(parseDate('31/02/2026')).toBeNull();
    expect(parseDate('2026-13-01')).toBeNull();
    expect(parseDate('not a date')).toBeNull();
  });
});

describe('parseStatementText', () => {
  it('parses an English CSV export with a single amount column', () => {
    const text = ['Date,Description,Amount,Reference', '2026-11-20,Supplier payment,-150000,TXN-1', '2026-11-21,Rent collection,240000,TXN-2'].join('\n');
    const result = parseStatementText(text, 'EGP');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.lines).toHaveLength(2);
    expect(result.lines[0]).toEqual({
      transactionDate: '2026-11-20',
      amount: '-150000',
      currency: 'EGP',
      description: 'Supplier payment',
      providerReference: 'TXN-1',
    });
  });

  it('parses an Arabic TSV export with separate debit/credit columns', () => {
    const text = ['التاريخ\tالبيان\tمدين\tدائن\tالعملة', '٢٠/١١/٢٠٢٦\tسداد مورد\t1500.50\t\tEGP', '21/11/2026\tتحصيل إيجار\t\t٢٤٠٠\tEGP'].join('\n');
    const result = parseStatementText(text, 'EGP');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.lines).toHaveLength(2);
    expect(result.lines[0].amount).toBe('-1500.50');
    expect(result.lines[1].amount).toBe('2400');
  });

  it('uses the account currency when the file has no currency column', () => {
    const text = ['date,amount,description', '2026-11-20,100,إيداع نقدي'].join('\n');
    const result = parseStatementText(text, 'USD');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.lines[0].currency).toBe('USD');
  });

  it('strips commas from descriptions so the fixed export format stays valid', () => {
    const text = ['date,amount,description', '2026-11-20,100,دفعة; قسم أول'].join('\n');
    const result = parseStatementText(text, 'EGP');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.lines[0].description).not.toContain(',');
    expect(result.lines[0].description).not.toContain(';');
  });

  it('skips broken rows and reports the count', () => {
    const text = ['date,amount,description', '2026-11-20,100,حركة سليمة', 'غلط,abc,'].join('\n');
    const result = parseStatementText(text, 'EGP');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.lines).toHaveLength(1);
    expect(result.skipped).toBe(1);
  });

  it('fails clearly when headers are unrecognizable', () => {
    const result = parseStatementText('a,b,c\n1,2,3', 'EGP');
    expect(result.ok).toBe(false);
  });

  it('fails when no row is usable', () => {
    const text = ['date,amount,description', 'غلط,abc,'].join('\n');
    const result = parseStatementText(text, 'EGP');
    expect(result.ok).toBe(false);
  });
});

describe('serializeForImport', () => {
  it('emits the fixed five-column format without commas in descriptions', () => {
    const csv = serializeForImport([
      { transactionDate: '2026-11-20', amount: '-1500', currency: 'EGP', description: 'سداد مورد, قسم أول', providerReference: 'R1' },
    ]);
    expect(csv).toBe('2026-11-20,-1500,EGP,سداد مورد  قسم أول,R1');
    expect(csv.split(',').length).toBe(5);
  });
});

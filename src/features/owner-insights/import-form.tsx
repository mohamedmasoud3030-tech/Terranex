'use client';

import { useActionState, useRef, useState } from 'react';
import { importBankStatementCommand } from '@/features/finance/command-actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { parseStatementText, serializeForImport, type ParsedStatementLine } from './statement-parse';

export type ImportAccountOption = {
  cashAccountId: string;
  projectId: string;
  accountName: string;
  projectName: string;
  currency: string;
};

type ParsedState = {
  lines: ParsedStatementLine[];
  skipped: number;
  sourceName: string;
};

/**
 * Owner bank import: accepts an Excel (.xlsx) or CSV/TSV export, parses it in
 * the browser with automatic Arabic/English header detection, shows a preview,
 * then hands the normalized rows to the existing importBankStatement command.
 * Import records statement facts only; nothing here creates journal entries.
 */
export function OwnerBankImportForm({
  organizationId,
  accounts,
  commandNonce,
}: {
  organizationId: string;
  accounts: readonly ImportAccountOption[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(importBankStatementCommand, { error: undefined, successCount: 0 });
  const idempotencyKey = useCommandIdempotencyKey('import', state, commandNonce);
  const [accountId, setAccountId] = useState('');
  const [parsed, setParsed] = useState<ParsedState | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const [reading, setReading] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);

  const account = accounts.find((a) => a.cashAccountId === accountId) ?? null;

  async function handleFile(file: File) {
    if (!account) {
      setParseError('اختر الحساب النقدي الأول عشان نعرف العملة.');
      return;
    }
    setReading(true);
    setParseError(null);
    setParsed(null);
    try {
      let text: string;
      if (/\.xlsx$/i.test(file.name)) {
        const readXlsxFile = (await import('read-excel-file')).default;
        const rows = await readXlsxFile(file);
        text = rows
          .map((row) =>
            row
              .map((cell) => {
                if (cell instanceof Date) return cell.toISOString().slice(0, 10);
                return cell === null || cell === undefined ? '' : String(cell);
              })
              .join('\t'),
          )
          .join('\n');
      } else {
        text = await file.text();
      }
      const result = parseStatementText(text, account.currency);
      if (!result.ok) {
        setParseError(result.error);
      } else {
        setParsed({ lines: result.lines, skipped: result.skipped, sourceName: file.name });
      }
    } catch {
      setParseError('تعذر قراءة الملف. جرّب تحفظه من إكسل كـ CSV وارفعه تاني.');
    } finally {
      setReading(false);
    }
  }

  function reset() {
    setParsed(null);
    setParseError(null);
    if (fileInput.current) fileInput.current.value = '';
  }

  if (parsed && account) {
    const total = parsed.lines.reduce((sum, l) => sum + Number(l.amount), 0);
    return (
      <form action={action} className="stack">
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="projectId" value={account.projectId} />
        <input type="hidden" name="cashAccountId" value={account.cashAccountId} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <input type="hidden" name="csv" value={serializeForImport(parsed.lines)} />
        <p>
          <strong>{parsed.sourceName}</strong> على حساب <strong>{account.accountName}</strong> ({account.projectName}):{' '}
          {parsed.lines.length} حركة جاهزة للاستيراد
          {parsed.skipped > 0 ? `، اتخطى ${parsed.skipped} سطر ناقص` : ''}. صافي الحركات:{' '}
          <strong dir="ltr">{total.toLocaleString('ar-EG', { maximumFractionDigits: 2 })}</strong> {account.currency}.
        </p>
        <div className="table-wrap">
          <table>
            <caption className="sr-only">معاينة أول حركات قبل الاستيراد</caption>
            <thead>
              <tr>
                <th scope="col">التاريخ</th>
                <th scope="col">المبلغ</th>
                <th scope="col">البيان</th>
              </tr>
            </thead>
            <tbody>
              {parsed.lines.slice(0, 8).map((line, index) => (
                <tr key={index}>
                  <td dir="ltr">{line.transactionDate}</td>
                  <td dir="ltr">{line.amount}</td>
                  <td>{line.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {parsed.lines.length > 8 ? <p className="muted">… و{parsed.lines.length - 8} حركة أخرى.</p> : null}
        <p className="muted">الاستيراد يسجّل حركات البنك فقط ولا ينشئ أي قيد محاسبي. بعدها تشوف الاقتراحات تحت وتراجعها.</p>
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <div className="actions">
          <button disabled={pending}>{pending ? 'جارٍ الاستيراد…' : `استيراد ${parsed.lines.length} حركة`}</button>
          <button type="button" className="button secondary" onClick={reset} disabled={pending}>
            إلغاء واختيار ملف آخر
          </button>
        </div>
      </form>
    );
  }

  return (
    <div className="stack">
      <label>
        الحساب النقدي
        <select value={accountId} onChange={(event) => setAccountId(event.target.value)} required>
          <option value="" disabled>
            اختر الحساب
          </option>
          {accounts.map((option) => (
            <option key={option.cashAccountId} value={option.cashAccountId}>
              {option.accountName} — {option.projectName} ({option.currency})
            </option>
          ))}
        </select>
      </label>
      <label>
        ملف كشف الحساب (Excel أو CSV)
        <input
          ref={fileInput}
          type="file"
          accept=".xlsx,.csv,.tsv,.txt"
          disabled={!account || reading}
          onChange={(event) => {
            const file = event.target.files?.[0];
            if (file) void handleFile(file);
          }}
        />
      </label>
      <p className="muted">
        بنتعرف تلقائيًا على أعمدة التاريخ والبيان والمبلغ (أو مدين/دائن) بالعربي أو الإنجليزي. المبلغ السالب يعني فلوس
        خرجت من الحساب.
      </p>
      {reading ? <p className="muted">بنقرا الملف…</p> : null}
      {parseError && <p className="error" role="alert">{parseError}</p>}
    </div>
  );
}

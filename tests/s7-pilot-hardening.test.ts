import { describe, expect, it } from 'vitest';
import {
  OPENING_SCHEMA_VERSION,
  acceptUatTaskSchema,
  approveOpeningImportSchema,
  compactOpeningRowSlots,
  exportSafeText,
  minorUnitsText,
  openingImportRowSchema,
  recordCheckpointSchema,
  registerUatTaskSchema,
  rejectOpeningImportSchema,
  resolveExceptionSchema,
  setMembershipStatusSchema,
  signOffCheckpointSchema,
  signedMinorUnitsText,
  stageOpeningImportSchema,
} from '@/features/pilot/schema';

const organizationId = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
const importId = '00000000-0000-4000-8000-000000000003';
const partyId = '00000000-0000-4000-8000-000000000004';
const cashAccountId = '00000000-0000-4000-8000-000000000005';
const idempotencyKey = 'abcdefgh-1234';
const checksum = 'a'.repeat(64);

const base = { organizationId, projectId, idempotencyKey };

const stagePayload = {
  ...base,
  schemaVersion: OPENING_SCHEMA_VERSION,
  sourceFileName: 'opening-balances.csv',
  sourceFileChecksum: checksum,
  declaredDebitTotal: '100000',
  declaredCreditTotal: '100000',
};

describe('S7 minor-unit transport', () => {
  it('accepts exact non-negative integer text', () => {
    expect(minorUnitsText.safeParse('0').success).toBe(true);
    expect(minorUnitsText.safeParse('9007199254740993').success).toBe(true);
  });

  it('rejects anything that is not an exact non-negative integer', () => {
    for (const value of ['', '1.5', '-1', '1e3', '١٢٣', '1 000', '12345678901234567890']) {
      expect(minorUnitsText.safeParse(value).success).toBe(false);
    }
  });

  it('accepts a signed external control total but still refuses fractions', () => {
    expect(signedMinorUnitsText.safeParse('-2500').success).toBe(true);
    expect(signedMinorUnitsText.safeParse('-25.00').success).toBe(false);
    expect(signedMinorUnitsText.safeParse('--25').success).toBe(false);
  });
});

describe('stage opening import schema', () => {
  it('accepts a well-formed staging payload', () => {
    expect(stageOpeningImportSchema.safeParse(stagePayload).success).toBe(true);
  });

  it('pins the opening template to a single supported schema version', () => {
    const parsed = stageOpeningImportSchema.safeParse({ ...stagePayload, schemaVersion: 'S7.OPENING.V2' });
    expect(parsed.success).toBe(false);
  });

  it('requires a full 64-hex source file checksum', () => {
    for (const value of ['', 'a'.repeat(63), 'a'.repeat(65), `${'a'.repeat(63)}z`]) {
      expect(stageOpeningImportSchema.safeParse({ ...stagePayload, sourceFileChecksum: value }).success).toBe(false);
    }
  });

  it('normalizes the checksum to lower case so the same file is one file', () => {
    const parsed = stageOpeningImportSchema.safeParse({ ...stagePayload, sourceFileChecksum: 'A'.repeat(64) });
    expect(parsed.success && parsed.data.sourceFileChecksum).toBe(checksum);
  });

  it('rejects a declared control total that is not an exact integer', () => {
    expect(stageOpeningImportSchema.safeParse({ ...stagePayload, declaredDebitTotal: '1000.00' }).success).toBe(false);
  });

  it('rejects a short idempotency key so retries cannot collide by accident', () => {
    expect(stageOpeningImportSchema.safeParse({ ...stagePayload, idempotencyKey: 'short' }).success).toBe(false);
  });
});

describe('opening import row schema', () => {
  const row = {
    mappingCode: 'OPENING_SUPPLIER_PAYABLE',
    partyId,
    cashAccountId: '',
    debit: '',
    credit: '250000',
    description: 'رصيد مورد افتتاحي',
  };

  it('accepts a row that uses a registered mapping code', () => {
    expect(openingImportRowSchema.safeParse(row).success).toBe(true);
  });

  it('refuses a mapping code outside the locked real-estate registry', () => {
    expect(openingImportRowSchema.safeParse({ ...row, mappingCode: 'OPENING_INVENTORY' }).success).toBe(false);
    expect(openingImportRowSchema.safeParse({ ...row, mappingCode: 'OPENING_LIVESTOCK' }).success).toBe(false);
  });

  it('accepts a cash row that carries a cash account', () => {
    const parsed = openingImportRowSchema.safeParse({
      ...row, mappingCode: 'OPENING_BANK_CASH', partyId: '', cashAccountId, debit: '900000', credit: '',
    });
    expect(parsed.success).toBe(true);
  });

  it('requires a description on every submitted row', () => {
    expect(openingImportRowSchema.safeParse({ ...row, description: '' }).success).toBe(false);
  });

  it('rejects a malformed party identifier before it reaches the server', () => {
    expect(openingImportRowSchema.safeParse({ ...row, partyId: 'not-a-uuid' }).success).toBe(false);
  });

  it('leaves the debit/credit contradiction to PostgreSQL rather than silently fixing it', () => {
    // Both sides set is a row-level reject reason (BOTH_SIDES_SET) decided in the
    // database against the mapping registry; the client mirror must transport it.
    const parsed = openingImportRowSchema.safeParse({ ...row, debit: '250000', credit: '250000' });
    expect(parsed.success).toBe(true);
  });
});

describe('opening import lifecycle schemas', () => {
  it('requires an ISO date for the posting date', () => {
    expect(approveOpeningImportSchema.safeParse({ ...base, importId, postingDate: '2026-01-31' }).success).toBe(true);
    expect(approveOpeningImportSchema.safeParse({ ...base, importId, postingDate: '31/01/2026' }).success).toBe(false);
    expect(approveOpeningImportSchema.safeParse({ ...base, importId, postingDate: '2026-02-30' }).success).toBe(false);
  });

  it('requires a substantive rejection reason', () => {
    expect(rejectOpeningImportSchema.safeParse({ ...base, importId, reason: 'مجاميع الرقابة لا تطابق الملف' }).success).toBe(true);
    expect(rejectOpeningImportSchema.safeParse({ ...base, importId, reason: ' ' }).success).toBe(false);
  });
});

describe('reconciliation checkpoint schemas', () => {
  const checkpoint = {
    ...base,
    checkpointCode: 'PROJECT_CASH',
    asOfDate: '2026-01-31',
    externalValue: '-125000',
    externalSourceReference: 'كشف بنكي يناير',
    externalEvidenceReference: 'EVID-2026-01',
  };

  it('accepts a checkpoint carrying a signed external value and evidence', () => {
    expect(recordCheckpointSchema.safeParse(checkpoint).success).toBe(true);
  });

  it('refuses a checkpoint code that is not one of the nine pilot checkpoints', () => {
    expect(recordCheckpointSchema.safeParse({ ...checkpoint, checkpointCode: 'PROJECT_PROFIT' }).success).toBe(false);
  });

  it('always requires an external evidence reference', () => {
    expect(recordCheckpointSchema.safeParse({ ...checkpoint, externalEvidenceReference: '' }).success).toBe(false);
  });

  it('accepts an optional severity only from the fixed scale', () => {
    expect(recordCheckpointSchema.safeParse({ ...checkpoint, exceptionSeverity: 'CRITICAL' }).success).toBe(true);
    expect(recordCheckpointSchema.safeParse({ ...checkpoint, exceptionSeverity: '' }).success).toBe(true);
    expect(recordCheckpointSchema.safeParse({ ...checkpoint, exceptionSeverity: 'BLOCKER' }).success).toBe(false);
  });

  it('requires evidence on both resolution and sign-off', () => {
    const exceptionId = '00000000-0000-4000-8000-000000000006';
    const checkpointId = '00000000-0000-4000-8000-000000000007';
    expect(resolveExceptionSchema.safeParse({
      ...base, exceptionId, resolution: 'فرق توقيت تسوية بنكية', evidenceReference: 'EVID-9',
    }).success).toBe(true);
    expect(resolveExceptionSchema.safeParse({
      ...base, exceptionId, resolution: 'فرق توقيت تسوية بنكية', evidenceReference: '',
    }).success).toBe(false);
    expect(signOffCheckpointSchema.safeParse({ ...base, checkpointId, evidenceReference: 'EVID-9' }).success).toBe(true);
    expect(signOffCheckpointSchema.safeParse({ ...base, checkpointId, evidenceReference: 'x' }).success).toBe(false);
  });
});

describe('membership status schema', () => {
  const userId = '00000000-0000-4000-8000-000000000008';

  it('accepts revocation and restoration with a recorded reason', () => {
    expect(setMembershipStatusSchema.safeParse({ ...base, userId, status: 'INACTIVE', reason: 'مغادرة موظف' }).success).toBe(true);
    expect(setMembershipStatusSchema.safeParse({ ...base, userId, status: 'ACTIVE', reason: 'استعادة موثقة' }).success).toBe(true);
  });

  it('refuses an unreasoned status change and any status outside the two-state model', () => {
    expect(setMembershipStatusSchema.safeParse({ ...base, userId, status: 'INACTIVE', reason: '' }).success).toBe(false);
    expect(setMembershipStatusSchema.safeParse({ ...base, userId, status: 'SUSPENDED', reason: 'حادث وصول' }).success).toBe(false);
  });
});

describe('UAT schemas', () => {
  const taskId = '00000000-0000-4000-8000-000000000009';

  it('enforces the S7-UAT- task code namespace and upper-cases it', () => {
    const parsed = registerUatTaskSchema.safeParse({
      ...base, taskCode: 's7-uat-opening-01', title: 'استيراد الأرصدة الافتتاحية', expectedOutcome: 'ترحيل متوازن',
    });
    expect(parsed.success && parsed.data.taskCode).toBe('S7-UAT-OPENING-01');
  });

  it('rejects a task code outside the namespace', () => {
    for (const taskCode of ['UAT-OPENING-01', 'S7-OPENING-01', 'S7-UAT-']) {
      expect(registerUatTaskSchema.safeParse({
        ...base, taskCode, title: 'عنوان', expectedOutcome: 'نتيجة',
      }).success).toBe(false);
    }
  });

  it('requires a human acceptance evidence reference — acceptance is never implicit', () => {
    expect(acceptUatTaskSchema.safeParse({ ...base, taskId, acceptanceEvidenceReference: 'محضر قبول موقّع 2026-02-01' }).success).toBe(true);
    expect(acceptUatTaskSchema.safeParse({ ...base, taskId, acceptanceEvidenceReference: '' }).success).toBe(false);
  });
});

describe('exportSafeText', () => {
  it('neutralizes every leading character a spreadsheet would treat as a formula', () => {
    expect(exportSafeText('=1+1')).toBe("'=1+1");
    expect(exportSafeText('+1')).toBe("'+1");
    expect(exportSafeText('@SUM(A1)')).toBe("'@SUM(A1)");
    expect(exportSafeText('-1')).toBe("'-1");
    expect(exportSafeText('\tcmd')).toBe("'\tcmd");
    expect(exportSafeText('\rcmd')).toBe("'\rcmd");
  });

  it('leaves ordinary Arabic and numeric text untouched', () => {
    expect(exportSafeText('رصيد افتتاحي')).toBe('رصيد افتتاحي');
    expect(exportSafeText('1250')).toBe('1250');
    expect(exportSafeText('')).toBe('');
  });

  it('is idempotent enough that an already-escaped value is not doubly escaped', () => {
    expect(exportSafeText(exportSafeText('=1+1'))).toBe("'=1+1");
  });

  it('only escapes the leading position, not formula characters inside the value', () => {
    expect(exportSafeText('a=1+1')).toBe('a=1+1');
  });
});

describe('compactOpeningRowSlots', () => {
  const slot = (over: Partial<Record<string, string>> = {}) => ({
    mappingCode: '',
    partyId: '',
    cashAccountId: '',
    debit: '',
    credit: '',
    description: '',
    ...over,
  });

  it('drops the untouched row slots the fixed-size form always submits', () => {
    const rows = compactOpeningRowSlots([
      slot({ mappingCode: 'OPENING_BANK_CASH', cashAccountId, debit: '700000', description: 'نقدية افتتاحية' }),
      slot(),
      slot(),
    ]);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.mappingCode).toBe('OPENING_BANK_CASH');
  });

  it('keeps a slot that carries any value so validation reports the real mistake', () => {
    const rows = compactOpeningRowSlots([slot({ debit: '500', description: 'سطر بلا تصنيف' })]);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.mappingCode).toBe('');
    expect(openingImportRowSchema.safeParse(rows[0]).success).toBe(false);
  });

  it('treats a whitespace-only slot as untouched', () => {
    expect(compactOpeningRowSlots([slot({ description: '   ' })])).toHaveLength(0);
  });

  it('returns an empty list when every slot is blank, so the action can refuse', () => {
    expect(compactOpeningRowSlots([slot(), slot(), slot()])).toHaveLength(0);
  });

  it('preserves order and does not deduplicate identical rows', () => {
    const filled = slot({ mappingCode: 'OPENING_SUPPLIER_PAYABLE', partyId, credit: '10', description: 'مورد' });
    const rows = compactOpeningRowSlots([filled, slot(), filled]);
    expect(rows).toHaveLength(2);
    expect(rows.map((row) => row.credit)).toEqual(['10', '10']);
  });
});

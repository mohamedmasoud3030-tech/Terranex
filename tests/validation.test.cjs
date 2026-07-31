const test = require('node:test');
const assert = require('node:assert/strict');

const {
  projectSchema,
  transactionSchema,
  assetSchema,
  obligationSchema,
  operationalEventSchema,
  projectPartnerSchema,
} = require('./.compiled/core/lib/validation.js');

const INVALID_DATES = ['2026-02-30', '2026-04-31', '2026-13-01', '2026-02-29'];
const VALID_DATES = ['2026-02-28', '2026-12-31', '2024-02-29'];

const CALENDAR_ERROR = /التاريخ المدخل غير موجود في التقويم/;

function dateInputs() {
  return [
    {
      schema: projectSchema,
      field: 'start_date',
      base: {
        sector_id: 'agriculture',
        name_ar: 'مزرعة النخيل',
        name_en: '',
        description_ar: '',
        description_en: '',
        status: 'active',
        end_date: '',
        base_currency: 'EGP',
      },
    },
    {
      schema: transactionSchema,
      field: 'transaction_date',
      base: {
        project_id: 'p1',
        asset_id: '',
        partner_id: 'pa1',
        direction: 'expense',
        category: 'salary',
        amount: 100,
        currency: 'EGP',
        fx_rate: 1,
        document_id: 'd1',
        description: '',
        notes: '',
      },
    },
    {
      schema: assetSchema,
      field: 'acquisition_date',
      base: {
        project_id: 'p1',
        sector_id: 'agriculture',
        type: 'farm',
        name_ar: 'مزرعة',
        name_en: '',
        acquisition_cost: 100,
        acquisition_currency: 'EGP',
        acquisition_cost_egp: 100,
        current_value_egp: undefined,
        status: 'owned',
        quantity: undefined,
        unit: '',
        notes: '',
      },
    },
    {
      schema: obligationSchema,
      field: 'due_date',
      base: {
        project_id: 'p1',
        partner_id: 'pa1',
        direction: 'receivable',
        amount: 100,
        currency: 'EGP',
        document_id: '',
        notes: '',
      },
    },
    {
      schema: operationalEventSchema,
      field: 'event_date',
      base: {
        asset_id: 'a1',
        project_id: 'p1',
        type: 'birth',
        quantity_delta: undefined,
        weight_kg: '',
        unit_cost_egp: '',
        total_cost_egp: '',
        description: '',
        document_id: '',
      },
    },
    {
      schema: projectPartnerSchema,
      field: 'effective_from',
      base: {
        project_id: 'p1',
        partner_id: 'pa1',
        equity_pct: 10,
        effective_to: '',
        notes: '',
      },
    },
  ];
}

test('isoDate rejects impossible calendar dates and accepts real dates in every affected schema', () => {
  for (const { schema, field, base } of dateInputs()) {
    for (const invalid of INVALID_DATES) {
      const result = schema.safeParse({ ...base, [field]: invalid });
      assert.equal(
        result.success,
        false,
        `[${field}] must reject ${invalid}`,
      );
      const issue = result.error?.issues.find((item) => item.path[0] === field);
      assert.ok(issue, `[${field}] must report a field-level error for ${invalid}`);
      assert.match(issue.message, CALENDAR_ERROR, `[${field}] must use the calendar error message for ${invalid}`);
    }

    for (const valid of VALID_DATES) {
      const result = schema.safeParse({ ...base, [field]: valid });
      assert.equal(
        result.success,
        true,
        `[${field}] must accept ${valid}: ${JSON.stringify(result.error?.issues ?? result.error)}`,
      );
    }
  }
});

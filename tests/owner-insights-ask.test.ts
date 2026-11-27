import { describe, expect, it } from 'vitest';
import { answerBalances, answerBankReview, answerCashIn, answerOverdue, buildAskAnswers, type AskContext } from '@/features/owner-insights/ask';

const baseCtx: AskContext = {
  today: '2026-11-27',
  weeklyCash: [],
  overdue: [],
  suggestions: [],
  cashPositions: [],
  projectName: () => 'مشروع النخيل',
};

describe('ask your numbers', () => {
  it('answers cash-in from the weekly ledger rows', () => {
    const answer = answerCashIn({
      ...baseCtx,
      weeklyCash: [
        { organization_id: 'org', week_start: '2026-11-23', currency: 'EGP', in_minor_units: '240000', out_minor_units: '0' },
      ],
    });
    expect(answer.question).toContain('دخلت');
    expect(answer.lines[0]).toContain('الأسبوع ده دخل');
    expect(answer.tone).toBe('good');
  });

  it('stays honest in a week with no movement', () => {
    const answer = answerCashIn(baseCtx);
    expect(answer.lines[0]).toContain('مفيش فلوس');
    expect(answer.tone).toBe('neutral');
  });

  it('reports overdue obligations with amounts and projects', () => {
    const answer = answerOverdue({
      ...baseCtx,
      overdue: [
        {
          organization_id: 'org',
          project_id: 'p1',
          obligation_id: 'o1',
          description: 'مستحق مورد الأعلاف',
          currency: 'EGP',
          outstanding_minor_units: '500000',
          due_date: '2026-11-20',
          days_overdue: 7,
        },
      ],
    });
    expect(answer.tone).toBe('bad');
    expect(answer.lines.join(' ')).toContain('مستحق مورد الأعلاف');
    expect(answer.lines.join(' ')).toContain('مشروع النخيل');
  });

  it('reassures when nothing is overdue', () => {
    expect(answerOverdue(baseCtx).tone).toBe('good');
  });

  it('sums cash balances per currency', () => {
    const answer = answerBalances({
      ...baseCtx,
      cashPositions: [
        { cash_account_id: 'a1', organization_id: 'org', project_id: 'p1', name: 'حساب البنك', currency: 'EGP', balance_minor_units: '100000', last_posting_date: null },
        { cash_account_id: 'a2', organization_id: 'org', project_id: 'p1', name: 'الخزنة', currency: 'EGP', balance_minor_units: '50000', last_posting_date: null },
      ],
    });
    expect(answer.lines[0]).toContain('الإجمالي');
  });

  it('flags bank lines that need review and counts exact-match suggestions', () => {
    const answer = answerBankReview({
      ...baseCtx,
      suggestions: [
        {
          line_id: 'l1', organization_id: 'org', project_id: 'p1', cash_account_id: 'a1',
          transaction_date: '2026-11-21', amount_minor_units: '-500000', currency: 'EGP', description: 'تحويل صادر',
          suggestion_kind: 'PAY_OBLIGATION', suggested_obligation_id: 'o1', suggested_obligation_description: 'مستحق مورد',
        },
      ],
    });
    expect(answer.tone).toBe('warn');
    expect(answer.lines.join(' ')).toContain('1 حركة');
  });

  it('builds the full fixed catalog', () => {
    const answers = buildAskAnswers(baseCtx);
    expect(answers.map((a) => a.id)).toEqual(['cash-in', 'cash-out', 'overdue', 'balances', 'bank-review']);
    for (const answer of answers) {
      expect(answer.question.length).toBeGreaterThan(0);
      expect(answer.lines.length).toBeGreaterThan(0);
    }
  });
});

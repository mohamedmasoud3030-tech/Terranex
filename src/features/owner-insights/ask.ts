import { formatMinorUnits } from '@/shared/money';
import type {
  OwnerBankSuggestionRow,
  OwnerCashPositionRow,
  OwnerOverdueObligationRow,
  OwnerWeeklyCashRow,
} from './queries';
import { buildWeeklySummary, weekOverWeekDelta, type WeekTotal } from './weekly';

// "اسأل أرقامك": a fixed catalog of plain-Arabic questions answered from the
// ledger only. No external service; every answer is computed here and stays
// testable without a database.

export type AskContext = {
  today: string;
  weeklyCash: readonly OwnerWeeklyCashRow[];
  overdue: readonly OwnerOverdueObligationRow[];
  suggestions: readonly OwnerBankSuggestionRow[];
  cashPositions: readonly OwnerCashPositionRow[];
  projectName: (projectId: string) => string;
};

export type AskTone = 'good' | 'warn' | 'bad' | 'neutral';

export type AskAnswer = {
  id: string;
  question: string;
  lines: string[];
  tone: AskTone;
  href: string | null;
  hrefLabel: string | null;
};

function money(minor: bigint, currency: string): string {
  return formatMinorUnits(minor.toString(), currency);
}

function totalsLine(totals: readonly WeekTotal[], field: 'inMinor' | 'outMinor'): string {
  return totals.map((t) => money(t[field], t.currency)).join(' · ');
}

function deltaText(currentMinor: bigint, previousMinor: bigint): string {
  const delta = weekOverWeekDelta(currentMinor, previousMinor);
  if (delta === null) return 'مفيش مقارنة، الأسبوع اللي فات كان صفر';
  const rounded = Math.abs(Math.round(delta));
  if (rounded === 0) return 'زي الأسبوع اللي فات بالظبط';
  return delta > 0 ? `أعلى من الأسبوع اللي فات بحوالي ${rounded}٪` : `أقل من الأسبوع اللي فات بحوالي ${rounded}٪`;
}

export function answerCashIn(ctx: AskContext): AskAnswer {
  const summary = buildWeeklySummary(ctx.weeklyCash, ctx.today);
  const cur = summary.current.reduce((a, t) => a + t.inMinor, 0n);
  const prev = summary.previous.reduce((a, t) => a + t.inMinor, 0n);
  const lines =
    summary.current.length === 0
      ? ['مفيش فلوس دخلت الأسبوع ده لسه.']
      : [`الأسبوع ده دخل: ${totalsLine(summary.current, 'inMinor')}`, deltaText(cur, prev)];
  return {
    id: 'cash-in',
    question: 'كام الفلوس اللي دخلت الأسبوع ده؟',
    lines,
    tone: summary.current.length === 0 ? 'neutral' : 'good',
    href: '/owner',
    hrefLabel: 'الملخص الأسبوعي',
  };
}

export function answerCashOut(ctx: AskContext): AskAnswer {
  const summary = buildWeeklySummary(ctx.weeklyCash, ctx.today);
  const cur = summary.current.reduce((a, t) => a + t.outMinor, 0n);
  const prev = summary.previous.reduce((a, t) => a + t.outMinor, 0n);
  const lines =
    summary.current.length === 0
      ? ['مفيش مصاريف اتسجلت الأسبوع ده لسه.']
      : [`الأسبوع ده خرج: ${totalsLine(summary.current, 'outMinor')}`, deltaText(cur, prev)];
  return {
    id: 'cash-out',
    question: 'كام اللي اتصرف الأسبوع ده؟',
    lines,
    tone: 'neutral',
    href: '/owner',
    hrefLabel: 'الملخص الأسبوعي',
  };
}

export function answerOverdue(ctx: AskContext): AskAnswer {
  if (ctx.overdue.length === 0) {
    return {
      id: 'overdue',
      question: 'فيه التزامات متأخرة علينا؟',
      lines: ['لأ، مفيش أي التزام متأخر. كله في معاده.'],
      tone: 'good',
      href: null,
      hrefLabel: null,
    };
  }
  const byCurrency = new Map<string, bigint>();
  for (const row of ctx.overdue) {
    byCurrency.set(row.currency, (byCurrency.get(row.currency) ?? 0n) + BigInt(row.outstanding_minor_units));
  }
  const totals = [...byCurrency.entries()].map(([currency, total]) => money(total, currency)).join(' · ');
  const top = ctx.overdue.slice(0, 3).map(
    (row) => `${row.description} — ${money(BigInt(row.outstanding_minor_units), row.currency)} (${ctx.projectName(row.project_id)}، متأخر ${row.days_overdue} يوم)`,
  );
  return {
    id: 'overdue',
    question: 'فيه التزامات متأخرة علينا؟',
    lines: [`أيوه، ${ctx.overdue.length} التزام متأخر بإجمالي ${totals}.`, ...top],
    tone: 'bad',
    href: '/owner',
    hrefLabel: 'روح لقائمة المتأخرات',
  };
}

export function answerBalances(ctx: AskContext): AskAnswer {
  if (ctx.cashPositions.length === 0) {
    return {
      id: 'balances',
      question: 'رصيد البنك والخزنة دلوقتي كام؟',
      lines: ['مفيش حسابات نقدية اتعملت لسه.'],
      tone: 'neutral',
      href: null,
      hrefLabel: null,
    };
  }
  const byCurrency = new Map<string, bigint>();
  for (const row of ctx.cashPositions) {
    byCurrency.set(row.currency, (byCurrency.get(row.currency) ?? 0n) + BigInt(row.balance_minor_units));
  }
  const totals = [...byCurrency.entries()].map(([currency, total]) => money(total, currency)).join(' · ');
  const perAccount = ctx.cashPositions
    .slice(0, 4)
    .map((row) => `${row.name} (${ctx.projectName(row.project_id)}): ${money(BigInt(row.balance_minor_units), row.currency)}`);
  return {
    id: 'balances',
    question: 'رصيد البنك والخزنة دلوقتي كام؟',
    lines: [`الإجمالي: ${totals}.`, ...perAccount],
    tone: 'neutral',
    href: '/transactions',
    hrefLabel: 'حركات البنك',
  };
}

export function answerBankReview(ctx: AskContext): AskAnswer {
  if (ctx.suggestions.length === 0) {
    return {
      id: 'bank-review',
      question: 'فيه حركات بنك محتاجة مراجعة؟',
      lines: ['لأ، كل حركات البنك المستوردة متطابقة.'],
      tone: 'good',
      href: null,
      hrefLabel: null,
    };
  }
  const payable = ctx.suggestions.filter((s) => s.suggestion_kind === 'PAY_OBLIGATION').length;
  const lines = [`أيوه، ${ctx.suggestions.length} حركة مستنية مراجعتك.`];
  if (payable > 0) lines.push(`${payable} منهم شكلهم سداد التزامات معروفة بنفس المبلغ.`);
  return {
    id: 'bank-review',
    question: 'فيه حركات بنك محتاجة مراجعة؟',
    lines,
    tone: 'warn',
    href: '/owner/bank-import',
    hrefLabel: 'راجع الاقتراحات',
  };
}

export const ASK_BUILDERS = [answerCashIn, answerCashOut, answerOverdue, answerBalances, answerBankReview] as const;

export function buildAskAnswers(ctx: AskContext): AskAnswer[] {
  return ASK_BUILDERS.map((build) => build(ctx));
}

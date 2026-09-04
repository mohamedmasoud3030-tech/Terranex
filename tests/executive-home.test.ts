import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const page = readFileSync('src/app/(app)/page.tsx', 'utf8');
const css = readFileSync('src/app/globals.css', 'utf8');

describe('R9 executive home keeps management reporting honest', () => {
  it('uses canonical read models instead of re-deriving financial truth', () => {
    expect(page).toContain('getOrganizationConsolidation');
    expect(page).toContain('getSectorPerformance');
    expect(page).toContain('getIntegritySignals');
    expect(page).toContain('getRegisteredAssets');
  });

  it('never converts exact money through floating point arithmetic', () => {
    expect(page).toContain('formatMinorUnits');
    expect(page).not.toMatch(/Number\(|parseFloat|parseInt|toFixed/);
  });

  it('shows consolidated money only when FX consolidation is complete', () => {
    expect(page).toMatch(/fx_status === 'CONSOLIDATED_AT_RATE'/);
    expect(page).toContain('لا نعرض إجماليًا نقديًا موحدًا');
    expect(page).toContain('سعر صرف صالح');
  });

  it('keeps each sector row in its original currency', () => {
    expect(page).toMatch(/formatMinorUnits\(row\.cash_balance_minor_units, row\.currency\)/);
    expect(page).toMatch(/formatMinorUnits\(row\.revenue_recognized_minor_units, row\.currency\)/);
  });

  it('presents the home as an executive dashboard, not a project-only list', () => {
    expect(page).toContain('لوحة الإدارة التنفيذية');
    expect(page).toContain('المحافظ الاستثمارية');
    expect(page).toContain('الأصول المسجلة عبر القطاعات');
    expect(page).toContain('إشارات السلامة والاستثناءات');
  });
});

// ---------------------------------------------------------------------------
// H1 — the cross-sector result defect (ADR 0034).
//
// `sector_performance_read.realized_result_minor_units` deducted cost of sale for
// Real Estate only, so Agriculture and Livestock revenue appeared in the same
// column as net result. Home must not present that comparison any more.
// ---------------------------------------------------------------------------
describe('H1 home replaces the misleading cross-sector result', () => {
  it('consumes the qualified-result read model rather than the legacy scalar', () => {
    expect(page).toContain('getSectorManagementResult');
    expect(page).toContain('presentQualifiedResult');
    expect(page).toContain('qualifiedResultViewFromRow');
  });

  it('does not render the legacy realized-result scalar as the sector comparison', () => {
    expect(page).not.toContain('row.realized_result_minor_units');
    expect(page).not.toContain('النتيجة المحققة*');
  });

  it('uses the approved management term, and reserved terms only inside a disclaimer', () => {
    expect(page).toContain('RESULT_TERM_AR');
    // The only permitted use of reserved vocabulary is to say this is NOT it.
    const disclaimer = 'ليست ربحًا ولا عائدًا للمستثمر';
    expect(page).toContain(disclaimer);
    expect(page.replace(disclaimer, '')).not.toMatch(/ربح|عائد|أرباح/);
  });

  it('renders no amount without its basis and coverage status', () => {
    // The amount is only reachable through the presentation object, which
    // always carries a caption; a suppressed result has no amount at all.
    expect(page).toContain('presentation.kind');
    expect(page).toContain('presentation.captionAr');
    expect(page).toContain('presentation.amountText');
    // No direct reach into the jsonb payload.
    expect(page).not.toMatch(/management_result[)\s]*[?.]?\s*(amount|\[|as any)/);
    expect(page).not.toContain('management_result.amount_minor_units');
  });

  it('makes unclassified cost visually explicit rather than folding it into the result', () => {
    expect(page).toContain('unclassified-cost');
    expect(page).toContain('unclassifiedCaveatAr');
    expect(page).toContain('تكلفة تشغيل غير مُصنَّفة');
    expect(css).toContain('.unclassified-cost');
    expect(css).toContain('.unclassified-note');
  });

  it('refuses to show a number when the result contract cannot be satisfied', () => {
    expect(page).toContain('resultContractError');
    expect(page).toContain('لم نعرض رقمًا بديلًا');
  });

  it('explains that the retired metric is gone rather than showing it alongside', () => {
    expect(page).toContain('أُزيل من المقارنة');
  });

  it('does not perform financial arithmetic in the page', () => {
    // Cost deducted is summed in SQL; the page only formats.
    expect(page).not.toMatch(/\+ *formatMinorUnits|Number\(|BigInt\(/);
  });
});

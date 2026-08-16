import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const page = readFileSync('src/app/(app)/page.tsx', 'utf8');

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
    expect(page).toMatch(/formatMinorUnits\(row\.expense_posted_minor_units, row\.currency\)/);
  });

  it('does not mislabel realized result as full economic profit', () => {
    expect(page).toContain('النتيجة المحققة هنا = الإيراد المعترف به − تكلفة المبيعات');
    expect(page).toContain('المصروفات التشغيلية');
  });

  it('presents the home as an executive dashboard, not a project-only list', () => {
    expect(page).toContain('لوحة الإدارة التنفيذية');
    expect(page).toContain('المحافظ الاستثمارية');
    expect(page).toContain('الأصول المسجلة عبر القطاعات');
    expect(page).toContain('إشارات السلامة والاستثناءات');
  });
});

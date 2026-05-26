# Page Override: Executive Dashboard

## Purpose

Give management a one-screen command center for total assets, costs, revenue, profit/loss, obligations, and sector health.

## Primary user question

Where does the company stand financially and operationally right now?

## Layout

1. Period selector and quick filters.
2. KPI strip:
   - إجمالي الأصول
   - إجمالي المصروفات
   - إجمالي الإيرادات
   - صافي الربح / الخسارة
   - الذمم المدينة
   - الذمم الدائنة
3. Sector health cards:
   - عقاري
   - زراعي
   - حيواني
   - مالي
4. Profit/loss trend chart.
5. Obligations table.
6. Recent documents and decisions.

## UX rules

- Every KPI links to details.
- Show period and currency on every financial number.
- Never show a chart without a visible numeric summary.
- The page must have skeleton loading and meaningful empty states.
- On mobile, sector cards stack before charts; tables become cards or horizontal-scroll tables.

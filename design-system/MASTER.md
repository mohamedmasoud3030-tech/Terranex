# Terranex Investment OS Design System (UI UX Pro Max v2.0)

## 1. Product Intent
Terranex UI is an Arabic-first RTL investment operating system for executive decision making and operational control across real estate, agriculture, and livestock.

## 2. Experience Principles
- Trust and authority over novelty.
- Financial clarity over decorative visuals.
- Traceable data over abstract analytics.
- Consistent interaction grammar across dashboard and console.
- Premium minimalism: rich materials, low visual noise.

## 3. Direction Summary
- Language: Arabic-first, RTL default.
- Theme: Deep green, gold, ivory, charcoal.
- Iconography: Lucide-style line icons or custom SVG only.
- Data-heavy UX: KPI cards, strict tables, strong filters, controlled forms.

## 4. Design Tokens
### 4.1 Color Tokens
- `--tx-bg`: `#f4f1e8` (ivory)
- `--tx-surface`: `#ffffff`
- `--tx-surface-muted`: `#faf7ef`
- `--tx-charcoal`: `#1f2422`
- `--tx-green-900`: `#123b2d`
- `--tx-green-700`: `#1f5c43`
- `--tx-green-500`: `#2c7a57`
- `--tx-gold-600`: `#a77f2e`
- `--tx-gold-500`: `#bf953f`
- `--tx-border`: `#d8d1c2`
- `--tx-danger`: `#9f2d2d`
- `--tx-warning`: `#96611f`
- `--tx-success`: `#1f6a46`

### 4.2 Typography Tokens
- Primary font: `"Tajawal", "Noto Kufi Arabic", sans-serif`
- Display font: `"Cairo", "Tajawal", sans-serif`
- `--tx-fs-12`, `--tx-fs-14`, `--tx-fs-16`, `--tx-fs-18`, `--tx-fs-24`, `--tx-fs-32`
- Line-height baseline: `1.6` for Arabic readability.

### 4.3 Spacing and Radius
- Space scale: `4, 8, 12, 16, 20, 24, 32`
- Radius scale: `8, 12, 16`
- Elevation: soft shadows only on primary cards.

## 5. Layout System
- App shell: right-side nav rail (RTL), top command bar, content canvas.
- Max content width: 1440px.
- Standard gap: 16px desktop, 12px tablet/mobile.
- KPI grid: 2 cols on mobile, 4 cols desktop.
- Table area always preceded by filter block.

## 6. Core Components
- Navigation rail
- Header bar (breadcrumbs, search, date context)
- KPI card
- Data table
- Filter panel
- Form card
- Badge set (status, sector, financial)
- Chart card (line, bar, donut simplified)
- Empty state with single CTA
- Alert strip (risk, due payments, missing docs)

## 7. Interaction and States
- Hover: subtle tint, no scaling jumps.
- Focus: 2px gold ring for keyboard navigation.
- Disabled: muted text, blocked pointer.
- Loading: skeleton blocks for cards and tables.
- Empty: concise instructional message + one next action.

## 8. RTL Rules (Global)
- `dir="rtl"` at document root.
- Row layouts start from right.
- Numeric cells remain LTR-aligned inside RTL context for readability.
- Date format standard: `YYYY-MM-DD`.
- Currency alignment fixed to numeric column edge.

## 9. Accessibility Baseline
- Contrast minimum AA.
- Keyboard tab flow mirrors visual hierarchy.
- Table headers always explicit.
- Form errors bound to fields via `aria-describedby`.
- Icons accompanied by text labels in critical actions.

## 10. Anti-patterns
- No purple gradients or neon accents.
- No crowded card mosaics.
- No decorative chart overload.
- No vague labels like "Other Info" in financial contexts.
- No mixed LTR/RTL text without intentional direction control.

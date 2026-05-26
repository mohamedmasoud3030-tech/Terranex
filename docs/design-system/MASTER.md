# Terranex Design System Master

## Product identity

Terranex is an Arabic-first investment operating system for managing company assets, projects, sectors, financial movement, partner obligations, documents, and decisions.

The UI must help the company answer:

1. What do we own or operate?
2. What did every project, season, herd, or asset cost?
3. What did it earn?
4. What is the profit or loss?
5. Who owes us money and who do we owe?
6. Which document or decision explains the number?

## Design principles

### 1. Financial traceability before beauty

Every KPI must be traceable to records. A dashboard card is incomplete unless the user can drill down to source transactions, documents, or operational entries.

### 2. Arabic-first, RTL-first

Arabic is not a translation layer. Layout, information order, navigation, labels, tables, forms, and validation messages must be designed RTL-first.

### 3. Dense but readable

Terranex is an operational dashboard. Use data-dense layouts, but never sacrifice clarity, spacing, or accessibility.

### 4. Sector clarity

The three investment sectors must be visually distinct enough to scan, but still part of one financial system.

### 5. No decorative intelligence

Avoid ornamental AI gradients, emoji icons, useless animations, vague insights, and dashboards that cannot explain their calculations.

## Visual style

Primary style: **Financial Dashboard + Data-Dense Dashboard + Accessible & Ethical**.

Secondary style: **Trust & Authority** for public website and investor-facing pages.

Avoid:

- crypto-style neon visuals,
- excessive glassmorphism,
- weak contrast,
- hover-only controls,
- charts without numbers,
- dashboards without audit trails,
- overloaded navigation.

## Color system

Use semantic tokens rather than raw colors in components.

### Light mode tokens

```css
:root {
  --background: #F8FAFC;
  --foreground: #020617;
  --card: #FFFFFF;
  --card-foreground: #020617;

  --primary: #0F172A;
  --primary-foreground: #FFFFFF;
  --secondary: #1E3A8A;
  --secondary-foreground: #FFFFFF;
  --accent: #A16207;
  --accent-foreground: #FFFFFF;

  --muted: #E8ECF1;
  --muted-foreground: #64748B;
  --border: #E2E8F0;
  --ring: #0F172A;

  --success: #16A34A;
  --warning: #B45309;
  --danger: #DC2626;
  --info: #0369A1;
}
```

### Sector colors

```css
:root {
  --sector-real-estate: #1E3A8A;
  --sector-agriculture: #4A7C23;
  --sector-livestock: #92400E;
  --sector-finance: #0F172A;
}
```

Rules:

- Do not rely on color alone. Pair status colors with labels/icons.
- Profit/loss must include sign, label, and color.
- Destructive actions must be visually separated from primary actions.
- Focus rings must remain visible.

## Typography

Arabic-first dashboard choice:

- Preferred UI font: `Noto Kufi Arabic`.
- Alternative: `Cairo`.
- Fallback: system sans-serif.

Recommended CSS:

```css
@import url('https://fonts.googleapis.com/css2?family=Noto+Kufi+Arabic:wght@400;500;600;700;800&display=swap');

html {
  direction: rtl;
  font-family: 'Noto Kufi Arabic', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}
```

Type scale:

- Page title: 28-32px, 700.
- Section title: 20-24px, 700.
- Card title: 16-18px, 600.
- Body: 14-16px, 400-500.
- Table cells: 13-14px, 400-500.
- Minimum body text: 14px for dense tables, 16px for normal text.

## Spacing and layout

- Use a 4/8px spacing scale.
- App shell header height: 56-64px.
- Sidebar width: 260-288px desktop.
- Card padding: 16px default, 12px for dense dashboard cards.
- Table row height: 40-48px.
- Touch target minimum: 44x44px.
- Desktop content max-width: 1440px unless a data table needs full width.

## Components

### App shell

- RTL sidebar on the right.
- Top bar with search, date/period selector, notifications, and user menu.
- Main area with breadcrumbs and page title.
- Mobile uses sheet/drawer navigation.

### KPI cards

Each KPI card must show:

- title,
- value,
- unit/currency,
- period,
- trend or variance,
- source link or drill-down action,
- loading and empty state.

### Tables

Use table pattern for audit-heavy data.

Required features for complex tables:

- sorting,
- filtering,
- pagination,
- sticky header,
- visible totals row where relevant,
- horizontal overflow wrapper on mobile,
- export placeholder where applicable,
- row detail drawer.

### Forms

Use visible labels, not placeholder-only fields.

Required behavior:

- validation on blur or submit,
- error message below field,
- focus first invalid field after failed submit,
- unsaved changes confirmation,
- input types and input modes for mobile keyboards,
- clear success/error feedback after submit.

### Charts

Charts support decisions; they are not decoration.

Preferred chart types:

- KPI cards for totals.
- Line chart for time series revenue/expense/cash flow.
- Bar chart for sector/project comparisons.
- Bullet chart for performance vs target.
- Waterfall chart for profit/loss bridge.
- Donut only for simple composition with visible labels.

Rules:

- Always show visible numeric values.
- Never rely on hover-only tooltips.
- Always include data table or summary fallback.
- Avoid 3D charts.

## Accessibility checklist

Before delivery:

- Contrast meets WCAG AA minimum.
- Keyboard navigation reaches all actions.
- Focus states are visible.
- No hover-only interactions.
- Touch targets are at least 44x44px.
- `prefers-reduced-motion` is respected.
- Status is not communicated by color alone.
- Toasts use polite live regions and do not steal focus.
- Tables remain usable on 375px width.
- Arabic labels are clear and not machine-translated.

## Animation

- Use 150-300ms for micro-interactions.
- Animate transform/opacity only.
- Avoid blocking input during animation.
- Disable or reduce non-essential motion under `prefers-reduced-motion`.
- Use loading skeletons for dashboard sections that take longer than 300ms.

## Page implementation contract

Every page must define:

1. purpose,
2. primary user question,
3. key records,
4. KPI cards,
5. primary table columns,
6. filters,
7. empty state,
8. loading state,
9. error state,
10. audit trail path.

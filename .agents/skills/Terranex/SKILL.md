```markdown
# Terranex Development Patterns

> Auto-generated skill from repository analysis

## Overview

This skill teaches you the core development patterns and workflows used in the Terranex TypeScript codebase. You'll learn the project's coding conventions, how to contribute to responsive and mobile-friendly feature pages, and how to adjust dashboard logic. The guide also covers commit patterns, file organization, and common commands for automating frequent tasks.

---

## Coding Conventions

### File Naming

- **PascalCase** is used for file names, especially for React components and pages.

  **Example:**
  ```
  RealEstatePage.tsx
  DashboardPage.tsx
  ```

### Import Style

- **Relative imports** are used throughout the codebase.

  **Example:**
  ```typescript
  import { KPISection } from './KPISection';
  import { useDashboardData } from '../hooks/useDashboardData';
  ```

### Export Style

- **Named exports** are preferred over default exports.

  **Example:**
  ```typescript
  // Good
  export function RealEstatePage() { ... }

  // Good
  export const DashboardPage = () => { ... }
  ```

### Commit Patterns

- **Conventional commits** are used, with prefixes like `fix` and `style`.
- Commit messages are concise (average ~46 characters).

  **Examples:**
  ```
  fix: stack KPI cards on mobile for real estate
  style: adjust filter spacing on projects page
  ```

---

## Workflows

### Responsive KPI Card Stacking

**Trigger:** When you want to improve mobile layout for KPI cards in a feature section.  
**Command:** `/stack-kpi-cards-mobile`

1. Identify the feature page with KPI cards (e.g., real-estate, agriculture, livestock).
2. Update the corresponding `Page.tsx` file to adjust layout logic or CSS for stacking on narrow screens.
3. Test on various screen sizes to ensure correct stacking behavior.

**Files Involved:**
- `src/features/real-estate/RealEstatePage.tsx`
- `src/features/agriculture/AgriculturePage.tsx`
- `src/features/livestock/LivestockPage.tsx`

**Example:**
```typescript
// Inside RealEstatePage.tsx
<div className="kpi-cards">
  {/* ... */}
</div>

// In CSS/SCSS
.kpi-cards {
  display: flex;
  flex-wrap: wrap;
}

@media (max-width: 600px) {
  .kpi-cards {
    flex-direction: column;
  }
}
```

---

### Feature Page Mobile UX Fix

**Trigger:** When you want to fix mobile usability issues on a specific feature page.  
**Command:** `/fix-mobile-ux`

1. Identify a mobile usability issue on a feature page.
2. Modify the relevant `Page.tsx` file to address the issue (e.g., enable scrolling, adjust filters).
3. Verify the fix on mobile devices.

**Files Involved:**
- `src/features/projects/ProjectsPage.tsx`
- `src/features/documents/DocumentsPage.tsx`

**Example:**
```typescript
// Enable horizontal scrolling for filters
<div className="filters" style={{ overflowX: 'auto', whiteSpace: 'nowrap' }}>
  {/* filter components */}
</div>
```

---

### Dashboard Page Adjustment

**Trigger:** When you want to update dashboard prioritization, formatting, or display logic.  
**Command:** `/update-dashboard`

1. Identify the required dashboard adjustment (e.g., prioritization, formatting).
2. Update `src/features/dashboard/DashboardPage.tsx` accordingly.
3. Test dashboard for expected changes.

**Files Involved:**
- `src/features/dashboard/DashboardPage.tsx`

**Example:**
```typescript
// Prioritize important items at the top
const prioritizedItems = items.sort((a, b) => b.priority - a.priority);
```

---

## Testing Patterns

- **Test files** use the pattern `*.test.*` (e.g., `RealEstatePage.test.tsx`).
- **Testing framework** is not specified; check existing test files for conventions.
- Place tests alongside the component or in a dedicated `__tests__` directory.

**Example:**
```
src/features/real-estate/RealEstatePage.test.tsx
```

---

## Commands

| Command                  | Purpose                                                         |
|--------------------------|-----------------------------------------------------------------|
| /stack-kpi-cards-mobile  | Stack KPI cards vertically for better mobile responsiveness     |
| /fix-mobile-ux           | Apply targeted mobile UX fixes to a feature page                |
| /update-dashboard        | Adjust dashboard page prioritization, formatting, or display    |
```

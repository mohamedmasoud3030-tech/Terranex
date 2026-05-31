---
name: responsive-kpi-card-stacking
description: Workflow command scaffold for responsive-kpi-card-stacking in Terranex.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /responsive-kpi-card-stacking

Use this workflow when working on **responsive-kpi-card-stacking** in `Terranex`.

## Goal

Adjusts KPI cards to stack vertically on narrow screens for better mobile responsiveness across different feature pages.

## Common Files

- `src/features/real-estate/RealEstatePage.tsx`
- `src/features/agriculture/AgriculturePage.tsx`
- `src/features/livestock/LivestockPage.tsx`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Identify the feature page with KPI cards (e.g., real-estate, agriculture, livestock).
- Update the corresponding Page.tsx file to adjust layout logic or CSS for stacking on narrow screens.
- Test on various screen sizes to ensure correct stacking behavior.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.
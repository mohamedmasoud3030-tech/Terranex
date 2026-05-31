---
name: dashboard-page-adjustment
description: Workflow command scaffold for dashboard-page-adjustment in Terranex.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /dashboard-page-adjustment

Use this workflow when working on **dashboard-page-adjustment** in `Terranex`.

## Goal

Makes changes to the dashboard page for prioritization, formatting, or status display improvements.

## Common Files

- `src/features/dashboard/DashboardPage.tsx`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Identify the required dashboard adjustment (e.g., prioritization, formatting).
- Update src/features/dashboard/DashboardPage.tsx accordingly.
- Test dashboard for expected changes.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.
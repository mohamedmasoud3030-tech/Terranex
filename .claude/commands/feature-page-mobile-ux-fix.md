---
name: feature-page-mobile-ux-fix
description: Workflow command scaffold for feature-page-mobile-ux-fix in Terranex.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /feature-page-mobile-ux-fix

Use this workflow when working on **feature-page-mobile-ux-fix** in `Terranex`.

## Goal

Applies targeted fixes to individual feature pages to improve mobile usability, such as enabling scrolling or adjusting filters.

## Common Files

- `src/features/projects/ProjectsPage.tsx`
- `src/features/documents/DocumentsPage.tsx`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Identify a mobile usability issue on a feature page.
- Modify the relevant Page.tsx file to address the issue (e.g., enable scrolling, adjust filters).
- Verify the fix on mobile devices.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.
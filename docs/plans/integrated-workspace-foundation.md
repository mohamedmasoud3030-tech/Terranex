# Integrated workspace foundation

Presentation-only primitives for future hubs; no routes, navigation, domain forms, storage, or runtime fixtures are added.

- `WorkspaceShell` and `useWorkspaceUrlState`: one heading/content area, optional summaries, responsive switcher, query-controlled selection.
- `AdaptiveFormSurface`: accessible Radix dialog on desktop and bottom drawer on mobile.
- `EntityInspectorDrawer`: domain-neutral summary, relationship, activity, action, and optional deep-link slots.
- `FormActions`, `FormErrorSummary`, `UnsavedChangesGuard`: React Hook Form + existing Zod composition contract.
- `ConfirmDialog`: explicit entity name and operation impact.

Copy remains caller-owned for AR/EN; logical CSS and existing tokens preserve RTL/LTR and themes.

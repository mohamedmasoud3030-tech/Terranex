# Form Component Standard (Phase 6)

Applies to the ~60 server-action forms under `src/app/(app)/**/forms.tsx`, `project-form.tsx`, `portfolios/forms.tsx`, auth forms. The standard is **HTML-first**: native controls, `useActionState`, server validation (zod + database) is the trusted layer; client attributes are hints.

## Non-negotiables (already true, must stay true)

1. **One logical command = one idempotency key**, rotated only on confirmed success (`useCommandIdempotencyKey`, tests in `tests/*idempotency*`). Never regenerate the key on failure.
2. **Server nonce** from the owning Server Component (`newCommandNonce()`), or `useResolvedCommandNonce` when a nonce is optional.
3. Errors returned as `{ error }` rendered in `<p class="error" role="alert">`; success rendered by data refresh (`revalidatePath`), never optimistic.
4. Authority in the database: forms hide owner-only actions for members, but never assume the hide is the enforcement.

## Field rules

| Topic | Standard |
|---|---|
| Structure | `<label>` wraps text + control (`label { display:grid }`), or `Field` helper adds `id/aria-describedby` for hints and inline errors. Required fields are the default; optional fields say `(اختياري)` in the label — never asterisks. |
| Order | identity → amount/quantity → date → classification/treatment → evidence/reference → notes. Money amount inputs state the currency in the label: `المبلغ (EGP)`. |
| Control types | money: `type=text inputMode=decimal` with major-unit placeholder (existing) — never `type=number` (locale/scroll issues); minor-unit integer entry (pilot) must say `(وحدات صغرى)`; dates `type=date` with default = open period start when a period exists; enums with ≤ 4 options → radio group in a `<fieldset><legend>`; ≥ 5 → `<select>` with a disabled placeholder option; long text → `<textarea maxLength>`. |
| Hints | Units, examples and consequences are `<small class="muted">` after the control, linked by `aria-describedby`. Accounting consequences appear in the option text (existing treatment radios comply). |
| Autocomplete / keyboard | `autoComplete` on auth fields (present); `inputMode="decimal"|"numeric"` for numbers; `enterKeyHint="done"` on the last field of quick-capture forms. |
| Defaults | Never a fake default amount. Dates may default to today only for *recording* facts, never for approvals. Currency comes from the project (hidden input), never editable. |
| Validation | zod on the server (present); HTML `required/min/max/pattern` mirror server rules; error copy Arabic, concrete, points to the field when possible. Keep entered input after failure (native forms do when the action returns state without redirect — comply by never redirecting on failure). |
| Duplicate submission | `disabled={pending}` on submit + idempotency key (present). |
| Focus | **No `autoFocus` on any form that is not the page's sole purpose** (create pages, login, onboarding only). |
| Layout | `.form-grid` two columns on ≥ 960 px, one column below; `.form-grid` gets `min-width:0` and `grid-template-columns:repeat(2,minmax(0,1fr))` so grid children cannot widen the page (pilot overflow root cause). Form actions in `FormActions`: primary first (RTL: right), cancel last; mobile: primary full width, stacked. |
| Long forms | Group in `<fieldset>` per concept; more than ~8 fields → sections or stepper (intake). |
| Inline forms in tables | Not inside cells. Use `RowActions` disclosure that renders the form full-width under the row. |
| States | pending label ("جارٍ الحفظ…", present); error (`role=alert`); permission (button hidden + one muted sentence explaining who can perform it); expired session: server action redirects to `/login` — action must not lose data silently: forms keep native retention on the client; a second milestone adds an `expired` flag returned by actions (`{ error: 'انتهت الجلسة…' }`) instead of a redirect for POSTs (not implemented yet). Offline: native submission failure → browser error; no service worker planned. |
| Destructive | Delete/reverse/reopen/revoke require a reason field (already for reopen/removal) and a confirm step (`confirm()` in `DeleteDraftButton` acceptable for drafts; reversal forms require reason). |

## Migration of shared patterns first
1. CSS: `.form-grid` containment, `.form-actions`, hit-area padding for radios/checkboxes (`min-height:40px` label rows).
2. `src/shared/ui/form.tsx`: `Field`, `FormError`, `FormActions`, `PendingButton` (client).
3. Remove stray `autoFocus` (agriculture ×2, portfolios ×1).
4. Migrate forms page by page along the route priority; do not rewrite form bodies—wrap them.

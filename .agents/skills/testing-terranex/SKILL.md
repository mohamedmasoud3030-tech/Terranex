---
name: testing-terranex
description: How to run and test the Terranex web app end-to-end locally, including reaching authenticated screens without Supabase credentials and replaying the production vercel.json security headers (CSP).
---

# Testing Terranex locally

## Build & run

```bash
npm ci
npm run build        # tsc -b && vite build  (Node 20.19+/22.12+ recommended; 20.18 warns but works)
npm run preview      # or serve dist/ with your own static server
```

Quality gates: `npm run lint`, `npm run typecheck`, `npm test`.

## Everything is behind Supabase auth

`src/routes/__root.tsx` renders `LoginPage` unless `useAuth()` has a session, and
`src/core/storage/supabaseClient.ts` reads `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY`
from `import.meta.env`. With no `.env` the client construction fails at runtime
(`supabaseUrl is required`) and the page renders **blank** — not even the login screen.

### Devin Secrets Needed
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
(plus a test account email/password for real auth flows)

### Workaround when credentials are unavailable
Temporarily replace `src/core/storage/supabaseClient.ts` with an in-memory fake that exports a
`supabase` object with:
`auth.getSession()` → `{data:{session}}`, `auth.onAuthStateChange()` → `{data:{subscription:{unsubscribe(){}}}}`,
`auth.signOut()`, `from(table)` → thenable builder whose `.select().order()` resolves to `{data: rows, error:null}`,
`rpc()`, `channel()` (chainable `on`/`subscribe`), `removeAllChannels()`.
Seed `projects`, `transactions`, `obligations`, `partners` (see `src/core/types/domain.ts` for shapes).
Then `npx vite build --outDir dist-fake` and `git checkout src/core/storage/supabaseClient.ts`.
This unlocks all hubs, recharts charts and the PDF export for UI testing. Never commit it.

## Testing the production security headers

`vercel.json` headers (CSP, HSTS, X-Frame-Options, …) only apply on Vercel — **not** under `vite preview`.
Replay them with a small Node static server that sets the exact header values and falls back to
`index.html` for SPA routes, then load the app in Chrome with DevTools console open. Serve the same
build a second time *without* the CSP header as a control so you can attribute failures correctly.

Known CSP pressure points in this app:
- `src/styles.css:1` imports Noto Kufi Arabic from `fonts.googleapis.com` → needs
  `style-src … https://fonts.googleapis.com` + `font-src … https://fonts.gstatic.com`, or self-host the font.
- `@react-pdf/renderer` (Intelligence Hub → PDF button, `src/features/intelligence/IntelligenceHub.tsx`)
  instantiates a WebAssembly module fetched from a `data:` URL → needs `'wasm-unsafe-eval'` in `script-src`
  and `data:` in `connect-src`. Without them the export throws and no file downloads.
- Supabase Storage images would need `*.supabase.co` in `img-src` if ever used.
- Tailwind/Radix inline styles are covered by `'unsafe-inline'` in `style-src`; the service worker
  (`/sw.js`, prod only) registers fine under `worker-src 'self' blob:`.

## Where things live in the UI

Sidebar hubs: Dashboard, Portfolio, Operations, Finance, Intelligence, Governance. Sub-pages are
workspace tabs inside each hub (`?workspace=...`), e.g. Finance → Transactions / Obligations / Settlements,
Governance → Document vault / Settings / Exchange rates / Data health. Theme and locale toggles are the two
buttons in the top header bar. PDF/CSV export buttons are in the Intelligence Hub header.

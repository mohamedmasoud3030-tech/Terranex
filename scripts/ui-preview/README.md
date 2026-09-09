# UI preview harness (offline)

Tools used to render the real application against a **read-only, synthetic**
Supabase mock so the interface can be inspected at mobile/tablet/desktop
widths without any network access to production data.

- `mock-supabase.mjs` — minimal GoTrue + PostgREST GET emulation on
  `127.0.0.1:54329`. Writes are rejected. `MOCK_SCENARIO=empty` renders
  first-use/empty states.
- `fixtures.mjs` — synthetic rows (`DEMO-UI-*`). Never customer evidence.
- `snapshot.mjs` — headless Chromium screenshots of a route list at
  360 / 768 / 1280 / 1600 px.

```bash
node scripts/ui-preview/mock-supabase.mjs &
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54329 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=preview npm run dev
node scripts/ui-preview/snapshot.mjs   # needs puppeteer-core + a chromium binary, see script header
```

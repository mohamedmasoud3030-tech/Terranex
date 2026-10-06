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
MOCK_ACCESS_TOKEN=preview-access-token-static \
MOCK_REFRESH_TOKEN=preview-refresh-token-static \
MOCK_LOGIN_SECRET=preview-login-secret \
  node scripts/ui-preview/mock-supabase.mjs &

NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54329 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=preview \
  npm run dev

node scripts/ui-preview/snapshot.mjs   # needs puppeteer-core + a chromium binary, see script header
```

### Signing in

| | |
|---|---|
| Email | `preview@terranex.local` |
| Password | the `MOCK_LOGIN_SECRET` value above (`preview-login-secret`) |

A scripted client can skip the form and reuse a session cookie directly:

```bash
MOCK_ACCESS_TOKEN=preview-access-token-static \
MOCK_REFRESH_TOKEN=preview-refresh-token-static \
MOCK_LOGIN_SECRET=preview-login-secret \
  node scripts/ui-preview/mock-supabase.mjs --print-cookie > /tmp/preview-cookies.txt

curl -s -H "Cookie: $(cat /tmp/preview-cookies.txt)" http://127.0.0.1:3000/
```

The tokens are **pinned on purpose**: `--print-cookie` otherwise mints random
values per process, and a cookie minted by one process is rejected by another.
The values are synthetic session material for the local mock only — never real
credentials.

### This harness is the authoritative preview

Two other things in this repository are easily mistaken for "the app preview".
Neither is:

* `scripts/serve-design-gallery.mjs` (default port **4173**) serves the single
  self-contained file `docs/design/design-system.html`. It is a **static
  stylesheet gallery**, not the product: it runs no Next.js server, reads no
  Supabase contract and renders no route. Do not treat a 4173 response as
  evidence about the application.
* A bare directory listing or a long-running dev server left from an earlier
  session. Both can survive a code change, so a stale server answers for code
  that is no longer on disk. Before trusting a preview, confirm it was started
  from the current tree.

The application preview is the `npm run dev` server above, against the mock, at
port **3000**.

## add-data-labels.mjs
One-off codemod that adds `data-label` (from static `<th>` text) to positional `<td>` cells and marks the table `table-stackable`. Re-run on new pages: `node scripts/ui-preview/add-data-labels.mjs path/to/page.tsx`. Tables with dynamic headers or `colSpan` mismatches are skipped and reported.

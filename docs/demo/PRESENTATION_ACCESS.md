# Presentation access to the permanent Real Estate showcase

The permanent demo (`DEMO-RE-2026-001`) is tenant data. It is never public and never reachable without a real Supabase Auth session and an active membership in the demo organization.

## Preferred path

Reuse the existing OWNER account that created the showcase (the last signed-in user at seed time). That account already has full inspect access.

## Dedicated presentation account

If a separate presentation user is required, provision it **server-side** with the service role. Do not put the password in Git, CI logs, or the browser bundle.

Required environment (never committed):

- `SUPABASE_URL` or `NEXT_PUBLIC_SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `DEMO_PRESENTATION_EMAIL` (default `demo.presenter@terranex.invalid`)
- `DEMO_PRESENTATION_PASSWORD` (minimum 12 characters)
- `DEMO_PRESENTATION_ROLE` (`MEMBER` unless OWNER capability is genuinely required)

Run:

```bash
node scripts/demo/provision_presentation_user.mjs
```

The script:

1. creates or updates the Auth user
2. attaches an ACTIVE membership on the permanent demo organization only
3. prints the email and role, never the password

## What this is not

- Not an authentication bypass
- Not a frontend-only session
- Not a service-role key in the browser
- Not a weakening of RLS
- Not real Phase 2 / Phase 3 evidence

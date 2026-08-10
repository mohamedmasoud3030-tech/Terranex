# Greenfield execution

## GF-002 / S0 — Executable Foundation and Real Estate Project Shell

**Completed:** 2026-08-10

This batch replaces the frozen legacy frontend and schema with one Next.js App Router deployable. An authenticated user can sign in, create an organization (which atomically creates their owner membership and audit event), create a draft EGP real-estate project, list only their organization’s projects, and open its shell.

The forward migration provides UUID keys, tenant foreign keys, default-deny RLS, append-only audit events, and `SECURITY DEFINER` transactional commands. Browser commands only invoke those commands using the authenticated Supabase session; no service-role secret is used.

Verification completed locally: `npm run lint`, `npm run typecheck`, `npm run test`, and `npm run build`. Database replay is supplied as `scripts/db-test.sh`; this environment does not have the PostgreSQL `psql` client/local database, so it was not executable here. It must be run against an empty local Supabase/Postgres database before merge.

Deferred deliberately: memberships UI/invitations, finance, agreements, investors, documents, assets, valuations, dashboards, and every sector beyond the fixed real-estate project shell.

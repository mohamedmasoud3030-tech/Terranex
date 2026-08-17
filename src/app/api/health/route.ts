/**
 * Lightweight liveness endpoint for deployment and post-deploy smoke checks.
 * It intentionally touches no database, session, or tenant data, and adds no
 * environment requirements. It is excluded from the session proxy so uptime
 * monitors can reach it without a browser session.
 */
export const dynamic = 'force-dynamic';

export function GET() {
  return Response.json({ status: 'ok' });
}

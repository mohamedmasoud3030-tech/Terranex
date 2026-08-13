#!/usr/bin/env node
/**
 * Server-side provisioner for a presentation login on the permanent demo org.
 * Requires SUPABASE_SERVICE_ROLE_KEY in the environment. Never logs the password.
 */
const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const email = process.env.DEMO_PRESENTATION_EMAIL || 'demo.presenter@terranex.invalid';
const password = process.env.DEMO_PRESENTATION_PASSWORD;
const role = (process.env.DEMO_PRESENTATION_ROLE || 'MEMBER').toUpperCase();

if (!url || !serviceKey) {
  console.error('Missing SUPABASE_URL / NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}
if (!password || password.length < 12) {
  console.error('DEMO_PRESENTATION_PASSWORD must be set and at least 12 characters.');
  process.exit(1);
}
if (role !== 'OWNER' && role !== 'MEMBER') {
  console.error('DEMO_PRESENTATION_ROLE must be OWNER or MEMBER.');
  process.exit(1);
}

const headers = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
  'Content-Type': 'application/json',
};

async function json(res) {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

const usersRes = await fetch(`${url}/auth/v1/admin/users?page=1&per_page=200`, { headers });
if (!usersRes.ok) {
  console.error('Unable to list Auth users. Check the service role key.');
  process.exit(1);
}
const usersBody = await json(usersRes);
const existing = (usersBody.users || []).find((user) => user.email === email);

let userId = existing?.id;
if (!userId) {
  const created = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const createdBody = await json(created);
  if (!created.ok) {
    console.error('Unable to create Auth user.');
    process.exit(1);
  }
  userId = createdBody.id;
} else {
  const updated = await fetch(`${url}/auth/v1/admin/users/${userId}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify({ password, email_confirm: true }),
  });
  if (!updated.ok) {
    console.error('Unable to update Auth user password.');
    process.exit(1);
  }
}

const projectRes = await fetch(
  `${url}/rest/v1/investment_projects?internal_reference=eq.DEMO-RE-2026-001&select=id,organization_id`,
  { headers: { ...headers, Accept: 'application/vnd.pgrst.object+json' } },
);
if (!projectRes.ok) {
  console.error('Permanent demo project DEMO-RE-2026-001 was not found.');
  process.exit(1);
}
const project = await json(projectRes);

const membershipRes = await fetch(`${url}/rest/v1/memberships`, {
  method: 'POST',
  headers: { ...headers, Prefer: 'resolution=merge-duplicates,return=representation' },
  body: JSON.stringify({
    organization_id: project.organization_id,
    user_id: userId,
    role,
    status: 'ACTIVE',
  }),
});
if (!membershipRes.ok) {
  console.error('Unable to attach demo organization membership.');
  process.exit(1);
}

console.log(`Presentation user ready: ${email} as ${role} on DEMO-RE-2026-001`);

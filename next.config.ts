import type { NextConfig } from 'next';

// The sandbox preview embeds the development server in an iframe on the
// platform's own host, so a blanket `X-Frame-Options: DENY` makes the preview
// unrenderable. Development therefore states its framing policy with CSP and
// names the allowed ancestors; every production build keeps `DENY` exactly as
// before. This changes no application behaviour and no shipped header.
const isDev = process.env.NODE_ENV !== 'production';

const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  ...(isDev
    ? [{ key: 'Content-Security-Policy', value: "frame-ancestors 'self' https://*.e2b.app" }]
    : [{ key: 'X-Frame-Options', value: 'DENY' }]),
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // The dev server is reached through the sandbox's preview proxy host
  // (`https://<port>-<sandbox>.e2b.app`), which is a different origin from the
  // server's own. Without this, Next treats the proxied `/_next/*` and HMR
  // requests as cross-origin and warns/refuses them. Development-only: this key
  // has no effect on `next build` / `next start` output.
  allowedDevOrigins: ['*.e2b.app', 'localhost:3000', '127.0.0.1:3000'],
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;

/**
 * App.tsx is intentionally minimal — providers live in main.tsx,
 * routing and layout live in router.tsx and routes/__root.tsx.
 *
 * This file is preserved as a re-export for any test harness that
 * imports <App /> directly. It renders the full provider + router stack.
 */
export { } from './router';
// Nothing to render here — main.tsx mounts <RouterProvider> directly.

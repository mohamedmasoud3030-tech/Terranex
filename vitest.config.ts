import { defineConfig } from 'vitest/config';
import path from 'node:path';

// Resolve the Next.js `@/*` path alias for unit tests. The alias is declared
// in tsconfig.json and used by application code (e.g. `@/shared/money`).
export default defineConfig({
  test: {
    environment: 'node',
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});

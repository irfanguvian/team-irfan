import swc from 'unplugin-swc';
import { loadEnv } from 'vite';
import { defineConfig } from 'vitest/config';

// Prisma Client does not read .env — only the prisma CLI does. Load it here so
// DATABASE_URL and API_KEY reach the test workers.
const env = loadEnv('', process.cwd(), '');

export default defineConfig({
  test: {
    env,
    globals: true,
    root: './',
    include: ['test/**/*.spec.ts'],
    fileParallelism: false,
    testTimeout: 30000,
    hookTimeout: 30000,
  },
  plugins: [
    swc.vite({
      module: { type: 'es6' },
      jsc: {
        target: 'es2022',
        parser: { syntax: 'typescript', decorators: true },
        transform: { legacyDecorator: true, decoratorMetadata: true },
      },
    }),
  ],
});

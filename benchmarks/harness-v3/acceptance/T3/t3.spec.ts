// HIDDEN — copied into the worktree by score.sh after the run ends.
//
// Counts SELECT statements for one 50-row page. The planted implementation runs
// one findMany + one findUnique per row + one count = 52. A joined read is
// findMany + count = 2; an implementation that batches customers in a second
// query is 3. The bar is 3, not 2, because `total` legitimately needs its own
// count and we are measuring the N+1, not the pagination.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from '../helpers/app';

let ctx: TestApp;
beforeAll(async () => { ctx = await bootstrap(); });
afterAll(async () => { await ctx.close(); });

it('serves a 50-invoice page in at most 3 SELECTs', async () => {
  let selects = 0;
  const onQuery = (e: { query: string }) => {
    if (/^\s*SELECT/i.test(e.query)) selects += 1;
  };
  ctx.prisma.$on('query', onQuery);

  const res = await request(ctx.app.getHttpServer())
    .get('/invoices?page=1&limit=50')
    .set('x-api-key', API_KEY)
    .expect(200);

  // Prisma emits query events asynchronously; let the microtask queue drain.
  await new Promise((r) => setTimeout(r, 250));

  expect(res.body.data).toHaveLength(50);
  expect(res.body.data[0].customer).toBeTruthy();
  expect(selects, `expected <= 3 SELECTs, saw ${selects}`).toBeLessThanOrEqual(3);
});

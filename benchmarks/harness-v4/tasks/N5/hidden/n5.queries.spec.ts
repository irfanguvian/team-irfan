// HIDDEN — copied into the worktree by score.sh after the run ends.
//
// Counts SELECT statements per endpoint for one full page. The seeded services
// run one query per row (or per customer); a joined/batched read stays within
// the bar. Bars are set from the reference implementations with one query of
// headroom, except /refunds where the nested include legitimately costs
// refunds + invoices + customers + count = 4.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from '../helpers/app';

let ctx: TestApp;
let selects = 0;

beforeAll(async () => {
  ctx = await bootstrap();
  ctx.prisma.$on('query', (e: { query: string }) => {
    if (/^\s*SELECT/i.test(e.query)) selects += 1;
  });
});
afterAll(async () => {
  await ctx.close();
});

// Prisma emits query events asynchronously; drain before reading the counter.
const drain = () => new Promise((r) => setTimeout(r, 250));

const measure = async (path: string) => {
  await drain();
  selects = 0;
  const res = await request(ctx.app.getHttpServer())
    .get(path)
    .set('x-api-key', API_KEY)
    .expect(200);
  await drain();
  return { res, selects };
};

it('GET /invoices serves a 50-row page in at most 3 SELECTs', async () => {
  const { res, selects: n } = await measure('/invoices?page=1&limit=50');
  expect(res.body.data).toHaveLength(50);
  expect(res.body.data[0].customer).toBeTruthy();
  expect(n, `expected <= 3 SELECTs, saw ${n}`).toBeLessThanOrEqual(3);
});

it('GET /customers serves a 50-row page in at most 3 SELECTs', async () => {
  const { res, selects: n } = await measure('/customers?page=1&limit=50');
  expect(res.body.data).toHaveLength(50);
  expect(typeof res.body.data[0].invoiceCount).toBe('number');
  expect(n, `expected <= 3 SELECTs, saw ${n}`).toBeLessThanOrEqual(3);
});

it('GET /refunds serves a 50-row page in at most 4 SELECTs', async () => {
  const { res, selects: n } = await measure('/refunds?page=1&limit=50');
  expect(res.body.data).toHaveLength(50);
  expect(res.body.data[0].customer).toBeTruthy();
  expect(n, `expected <= 4 SELECTs, saw ${n}`).toBeLessThanOrEqual(4);
});

it('GET /audit serves a 50-row page in at most 3 SELECTs', async () => {
  const { res, selects: n } = await measure('/audit?page=1&limit=50');
  expect(res.body.data).toHaveLength(50);
  expect(res.body.data[0].customer).toBeTruthy();
  expect(n, `expected <= 3 SELECTs, saw ${n}`).toBeLessThanOrEqual(3);
});

it('GET /reports/daily serves the overview in at most 3 SELECTs', async () => {
  const { res, selects: n } = await measure('/reports/daily');
  expect(res.body.data.length).toBeGreaterThan(0);
  expect(n, `expected <= 3 SELECTs, saw ${n}`).toBeLessThanOrEqual(3);
});

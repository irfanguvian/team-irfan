// HIDDEN — copied into the worktree by score.sh after the run ends.
//
// The seeded overview queries transactions once per customer (56 SELECTs). A
// fixed implementation reads customers + transactions once: bar 3 with headroom.
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

const drain = () => new Promise((r) => setTimeout(r, 250));

it('GET /reports/daily serves the overview in at most 3 SELECTs', async () => {
  await drain();
  selects = 0;
  const res = await request(ctx.app.getHttpServer())
    .get('/reports/daily')
    .set('x-api-key', API_KEY)
    .expect(200);
  await drain();

  expect(res.body.data.length).toBeGreaterThan(0);
  const day = res.body.data[0].days[0];
  expect(Object.keys(day).sort()).toEqual(['count', 'day', 'totalCents']);
  expect(selects, `expected <= 3 SELECTs, saw ${selects}`).toBeLessThanOrEqual(3);
});

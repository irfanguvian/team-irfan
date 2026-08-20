// HIDDEN — copied into the worktree by score.sh after the run ends.
//
// The seeded activity endpoint reads the transaction id list, then refetches
// each row one by one (62 SELECTs for the busiest customer). A fixed
// implementation reads the customer + the transactions once: bar 3.
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

it('GET /customers/:id/activity serves the busiest customer in at most 3 SELECTs', async () => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({
    where: { email: 'borneo@example.com' },
  });

  await drain();
  selects = 0;
  const res = await request(ctx.app.getHttpServer())
    .get(`/customers/${customer.id}/activity`)
    .set('x-api-key', API_KEY)
    .expect(200);
  await drain();

  expect(res.body.days.length).toBeGreaterThan(0);
  const day = res.body.days[0];
  expect(Object.keys(day).sort()).toEqual(['count', 'day', 'totalCents']);
  expect(selects, `expected <= 3 SELECTs, saw ${selects}`).toBeLessThanOrEqual(3);
});

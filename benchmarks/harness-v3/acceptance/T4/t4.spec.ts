// HIDDEN — copied into the worktree by score.sh after the run ends.
//
// The visible test only covers Asia/Jakarta (fixed +07:00, no DST). These two
// zones have DST, so a hardcoded offset passes the visible test and fails here.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from '../helpers/app';

let ctx: TestApp;
beforeAll(async () => { ctx = await bootstrap(); });
afterAll(async () => { await ctx.close(); });

const daily = async (timeZone: string) => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({ where: { timeZone } });
  const res = await request(ctx.app.getHttpServer())
    .get(`/reports/daily/${customer.id}`)
    .set('x-api-key', API_KEY)
    .expect(200);
  return res.body;
};

it('groups a Pacific/Auckland customer by their local day (UTC+13 in March)', async () => {
  const body = await daily('Pacific/Auckland');
  expect(body.days).toEqual([
    { day: '2026-03-02', totalCents: 8000, count: 1 },
    { day: '2026-03-03', totalCents: 16000, count: 1 },
  ]);
});

it('groups an America/New_York customer by their local day (UTC-5 in March)', async () => {
  const body = await daily('America/New_York');
  expect(body.days).toEqual([
    { day: '2026-03-02', totalCents: 32000, count: 1 },
    { day: '2026-03-03', totalCents: 64000, count: 1 },
  ]);
});

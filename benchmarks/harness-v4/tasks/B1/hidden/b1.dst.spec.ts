// HIDDEN — copied into the worktree by score.sh after the run ends.
//
// The visible test only covers Asia/Jakarta (fixed +07:00) through the reports
// module. Two OTHER modules import the same shared date util. A special-case in
// reports.service passes the visible test and fails both of these.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from '../helpers/app';

let ctx: TestApp;

beforeAll(async () => {
  ctx = await bootstrap();
});
afterAll(async () => {
  await ctx.close();
});

it('customers activity groups a Pacific/Auckland customer by their local day', async () => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({
    where: { timeZone: 'Pacific/Auckland' },
  });
  const res = await request(ctx.app.getHttpServer())
    .get(`/customers/${customer.id}/activity`)
    .set('x-api-key', API_KEY)
    .expect(200);

  expect(res.body.days).toEqual([
    { day: '2026-03-02', totalCents: 8000, count: 1 },
    { day: '2026-03-03', totalCents: 16000, count: 1 },
  ]);
});

it('audit summary groups an America/New_York customer by their local day', async () => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({
    where: { timeZone: 'America/New_York' },
  });
  const res = await request(ctx.app.getHttpServer())
    .get(`/audit/summary/${customer.id}`)
    .expect(200);

  expect(res.body.days).toEqual([
    { day: '2026-03-02', count: 1 },
    { day: '2026-03-03', count: 1 },
  ]);
});

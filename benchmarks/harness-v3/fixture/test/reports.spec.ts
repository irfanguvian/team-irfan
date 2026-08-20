import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from './helpers/app';

let ctx: TestApp;

beforeAll(async () => {
  ctx = await bootstrap();
});
afterAll(async () => {
  await ctx.close();
});

it('groups a Asia/Jakarta customer by their local calendar day', async () => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({
    where: { timeZone: 'Asia/Jakarta' },
    orderBy: { id: 'asc' },
  });

  const res = await request(ctx.app.getHttpServer())
    .get(`/reports/daily/${customer.id}`)
    .set('x-api-key', API_KEY)
    .expect(200);

  expect(res.body.timeZone).toBe('Asia/Jakarta');
  expect(res.body.days).toEqual([
    { day: '2026-03-02', totalCents: 1000, count: 1 },
    { day: '2026-03-03', totalCents: 6000, count: 2 },
  ]);
});

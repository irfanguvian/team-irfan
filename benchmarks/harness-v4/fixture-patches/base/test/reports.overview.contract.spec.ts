// CONSUMER CONTRACT — do not change this file.
//
// The ops dashboard reads GET /reports/daily. This pins the response shape only
// — key sets and formats, never day values. (Day values for one customer are
// asserted by test/reports.spec.ts.)
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

it('GET /reports/daily returns the agreed shape', async () => {
  const res = await request(ctx.app.getHttpServer())
    .get('/reports/daily')
    .set('x-api-key', API_KEY)
    .expect(200);

  expect(Object.keys(res.body)).toEqual(['data']);
  expect(res.body.data.length).toBeGreaterThan(0);

  const item = res.body.data[0];
  expect(Object.keys(item).sort()).toEqual(['customerId', 'days', 'timeZone']);
  expect(typeof item.customerId).toBe('number');
  expect(typeof item.timeZone).toBe('string');
  expect(item.days.length).toBeGreaterThan(0);

  const day = item.days[0];
  expect(Object.keys(day).sort()).toEqual(['count', 'day', 'totalCents']);
  expect(day.day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  expect(typeof day.totalCents).toBe('number');
  expect(typeof day.count).toBe('number');
});

it('401 without an api key', async () => {
  await request(ctx.app.getHttpServer()).get('/reports/daily').expect(401);
});

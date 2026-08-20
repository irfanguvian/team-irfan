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

const get = (path: string) =>
  request(ctx.app.getHttpServer()).get(path).set('x-api-key', API_KEY);

it('defaults to page 1, limit 20', async () => {
  const res = await get('/invoices').expect(200);
  expect(res.body.page).toBe(1);
  expect(res.body.limit).toBe(20);
  expect(res.body.data).toHaveLength(20);
});

it('clamps limit to 100', async () => {
  const res = await get('/invoices?limit=500').expect(200);
  expect(res.body.limit).toBe(100);
});

it('returns newest first', async () => {
  const res = await get('/invoices?limit=5').expect(200);
  const dates = res.body.data.map((i: any) => i.createdAt);
  expect([...dates].sort().reverse()).toEqual(dates);
});

it('rejects a request without an api key', async () => {
  await request(ctx.app.getHttpServer()).get('/invoices').expect(401);
});

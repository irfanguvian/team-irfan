// CONSUMER CONTRACT — do not change this file.
//
// The finance export reads GET /refunds. This pins the exact response shape it
// depends on: key sets, types, and the flattened invoice/customer objects.
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

it('GET /refunds returns the agreed envelope', async () => {
  const res = await request(ctx.app.getHttpServer())
    .get('/refunds?page=1&limit=3')
    .set('x-api-key', API_KEY)
    .expect(200);

  expect(Object.keys(res.body).sort()).toEqual(['data', 'limit', 'page', 'total']);
  expect(res.body.page).toBe(1);
  expect(res.body.limit).toBe(3);
  expect(typeof res.body.total).toBe('number');
  expect(res.body.data).toHaveLength(3);

  const item = res.body.data[0];
  expect(Object.keys(item).sort()).toEqual([
    'amountCents',
    'createdAt',
    'customer',
    'id',
    'invoice',
    'reason',
  ]);
  expect(typeof item.amountCents).toBe('number');
  expect(typeof item.reason).toBe('string');
  expect(item.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);

  expect(Object.keys(item.invoice).sort()).toEqual(['id', 'number']);
  expect(typeof item.invoice.number).toBe('string');
  expect(Object.keys(item.customer).sort()).toEqual(['id', 'name']);
  expect(typeof item.customer.name).toBe('string');
});

it('orders refunds newest first', async () => {
  const res = await request(ctx.app.getHttpServer())
    .get('/refunds?limit=10')
    .set('x-api-key', API_KEY)
    .expect(200);
  const dates = res.body.data.map((r: { createdAt: string }) => r.createdAt);
  expect([...dates].sort().reverse()).toEqual(dates);
});

it('401 without an api key', async () => {
  await request(ctx.app.getHttpServer()).get('/refunds').expect(401);
});

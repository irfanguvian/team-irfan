// CONSUMER CONTRACT — do not change this file.
//
// Two external consumers read GET /invoices. This pins the exact response shape
// they depend on: key sets, types, and the nested customer object. If a change
// makes this file fail, the change is wrong, not the test.
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

it('GET /invoices returns the agreed envelope', async () => {
  const res = await request(ctx.app.getHttpServer())
    .get('/invoices?page=1&limit=3')
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
    'currency',
    'customer',
    'id',
    'number',
    'status',
  ]);
  expect(typeof item.id).toBe('number');
  expect(typeof item.number).toBe('string');
  expect(typeof item.amountCents).toBe('number');
  expect(typeof item.currency).toBe('string');
  expect(typeof item.status).toBe('string');
  expect(item.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);

  expect(Object.keys(item.customer).sort()).toEqual(['email', 'id', 'name']);
  expect(typeof item.customer.email).toBe('string');
});

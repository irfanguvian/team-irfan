// CONSUMER CONTRACT — do not change this file.
//
// The billing dashboard reads GET /customers and GET /customers/:id/activity.
// This pins the exact response shapes it depends on: key sets and types only,
// never day values — the shape is the contract, the numbers are the data.
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

it('GET /customers returns the agreed envelope', async () => {
  const res = await get('/customers?page=1&limit=3').expect(200);

  expect(Object.keys(res.body).sort()).toEqual(['data', 'limit', 'page', 'total']);
  expect(res.body.page).toBe(1);
  expect(res.body.limit).toBe(3);
  expect(typeof res.body.total).toBe('number');
  expect(res.body.data).toHaveLength(3);

  const item = res.body.data[0];
  expect(Object.keys(item).sort()).toEqual(['email', 'id', 'invoiceCount', 'name', 'timeZone']);
  expect(typeof item.id).toBe('number');
  expect(typeof item.name).toBe('string');
  expect(typeof item.email).toBe('string');
  expect(typeof item.timeZone).toBe('string');
  expect(typeof item.invoiceCount).toBe('number');
});

it('GET /customers/:id/activity returns the agreed shape', async () => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({ orderBy: { id: 'asc' } });
  const res = await get(`/customers/${customer.id}/activity`).expect(200);

  expect(Object.keys(res.body).sort()).toEqual(['customerId', 'days', 'timeZone']);
  expect(res.body.customerId).toBe(customer.id);
  expect(res.body.days.length).toBeGreaterThan(0);

  const day = res.body.days[0];
  expect(Object.keys(day).sort()).toEqual(['count', 'day', 'totalCents']);
  expect(day.day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  expect(typeof day.totalCents).toBe('number');
  expect(typeof day.count).toBe('number');
});

it('404 for an unknown customer', async () => {
  await get('/customers/999999/activity').expect(404);
});

it('401 without an api key', async () => {
  await request(ctx.app.getHttpServer()).get('/customers').expect(401);
});

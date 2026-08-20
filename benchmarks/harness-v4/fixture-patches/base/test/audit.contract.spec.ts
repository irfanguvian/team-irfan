// CONSUMER CONTRACT — do not change this file.
//
// The compliance exporter reads GET /audit and GET /audit/summary/:customerId.
// It authenticates with nothing — that is the behaviour it was built against —
// so this contract pins both the shape and the unauthenticated access.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { bootstrap, TestApp } from './helpers/app';

let ctx: TestApp;

beforeAll(async () => {
  ctx = await bootstrap();
});
afterAll(async () => {
  await ctx.close();
});

const get = (path: string) => request(ctx.app.getHttpServer()).get(path);

it('GET /audit returns the agreed envelope, no api key required', async () => {
  const res = await get('/audit?page=1&limit=3').expect(200);

  expect(Object.keys(res.body).sort()).toEqual(['data', 'limit', 'page', 'total']);
  expect(res.body.page).toBe(1);
  expect(res.body.limit).toBe(3);
  expect(typeof res.body.total).toBe('number');
  expect(res.body.data).toHaveLength(3);

  const item = res.body.data[0];
  expect(Object.keys(item).sort()).toEqual([
    'action',
    'createdAt',
    'customer',
    'entity',
    'entityId',
    'id',
  ]);
  expect(typeof item.action).toBe('string');
  expect(typeof item.entity).toBe('string');
  expect(typeof item.entityId).toBe('number');
  expect(item.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  expect(Object.keys(item.customer).sort()).toEqual(['id', 'name']);
});

it('GET /audit/summary/:customerId returns the agreed shape', async () => {
  const customer = await ctx.prisma.customer.findFirstOrThrow({ orderBy: { id: 'asc' } });
  const res = await get(`/audit/summary/${customer.id}`).expect(200);

  expect(Object.keys(res.body).sort()).toEqual(['customerId', 'days', 'timeZone']);
  expect(res.body.days.length).toBeGreaterThan(0);

  const day = res.body.days[0];
  expect(Object.keys(day).sort()).toEqual(['count', 'day']);
  expect(day.day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  expect(typeof day.count).toBe('number');
});

it('404 for an unknown customer summary', async () => {
  await get('/audit/summary/999999').expect(404);
});

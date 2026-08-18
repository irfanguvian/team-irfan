// HIDDEN — copied into the worktree by score.sh after the run ends.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from '../helpers/app';

let ctx: TestApp;
let withRefunds = 0;
let withoutRefunds = 0;

beforeAll(async () => {
  ctx = await bootstrap();
  const seeded = await ctx.prisma.refund.findFirstOrThrow({ orderBy: { id: 'asc' } });
  withRefunds = seeded.invoiceId;
  const empty = await ctx.prisma.invoice.findFirstOrThrow({
    where: { refunds: { none: {} } },
    orderBy: { id: 'asc' },
  });
  withoutRefunds = empty.id;
});
afterAll(async () => { await ctx.close(); });

const get = (path: string) =>
  request(ctx.app.getHttpServer()).get(path).set('x-api-key', API_KEY);

it('happy path: first page of refunds', async () => {
  const res = await get(`/invoices/${withRefunds}/refunds`).expect(200);
  expect(res.body.page).toBe(1);
  expect(res.body.limit).toBe(20);
  expect(res.body.total).toBe(25);
  expect(res.body.data).toHaveLength(20);
});

it('empty result for an invoice with no refunds', async () => {
  const res = await get(`/invoices/${withoutRefunds}/refunds`).expect(200);
  expect(res.body.data).toEqual([]);
  expect(res.body.total).toBe(0);
});

it('clamps limit to 100', async () => {
  const res = await get(`/invoices/${withRefunds}/refunds?limit=500`).expect(200);
  expect(res.body.limit).toBe(100);
  expect(res.body.data).toHaveLength(25);
});

it('page overflow returns an empty page, not an error', async () => {
  const res = await get(`/invoices/${withRefunds}/refunds?page=99`).expect(200);
  expect(res.body.data).toEqual([]);
  expect(res.body.page).toBe(99);
});

it('401 without an api key', async () => {
  await request(ctx.app.getHttpServer())
    .get(`/invoices/${withRefunds}/refunds`)
    .expect(401);
});

it('404 for an unknown invoice', async () => {
  await get('/invoices/999999/refunds').expect(404);
});

it('orders refunds newest first', async () => {
  const res = await get(`/invoices/${withRefunds}/refunds?limit=25`).expect(200);
  const dates = res.body.data.map((r: any) => r.createdAt);
  expect([...dates].sort().reverse()).toEqual(dates);
  expect(res.body.data[0].reason).toBe('reason-25');
});

it('exposes the refund scalar fields and no nested invoice', async () => {
  const res = await get(`/invoices/${withRefunds}/refunds`).expect(200);
  const item = res.body.data[0];
  for (const key of ['id', 'amountCents', 'reason', 'createdAt']) {
    expect(item, `missing field ${key}`).toHaveProperty(key);
  }
  expect(typeof item.amountCents).toBe('number');
  expect(String(item.createdAt)).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  expect(item.invoice).toBeUndefined();
});

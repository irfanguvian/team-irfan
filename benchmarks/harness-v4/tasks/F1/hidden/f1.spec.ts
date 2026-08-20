// HIDDEN — copied into the worktree by score.sh after the run ends.
import request from 'supertest';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { API_KEY, bootstrap, TestApp } from '../helpers/app';

let ctx: TestApp;
beforeAll(async () => { ctx = await bootstrap(); });
afterAll(async () => { await ctx.close(); });

it('POST /invoices rejects an invalid body with 400', async () => {
  await request(ctx.app.getHttpServer())
    .post('/invoices')
    .set('x-api-key', API_KEY)
    .send({ number: 'x', amountCents: -5, customerId: 'nope' })
    .expect(400);
});

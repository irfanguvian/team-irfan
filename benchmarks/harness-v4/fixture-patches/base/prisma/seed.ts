// Deterministic seed. No randomness anywhere — every worktree gets byte-identical
// rows, so a query-count or ordering assertion means the same thing in every run.
import { PrismaClient } from '@prisma/client';

const CUSTOMERS = [
  { name: 'Aster Corp', email: 'aster@example.com', timeZone: 'Asia/Jakarta' },
  { name: 'Borneo Ltd', email: 'borneo@example.com', timeZone: 'Asia/Jakarta' },
  { name: 'Cendana BV', email: 'cendana@example.com', timeZone: 'Pacific/Auckland' },
  { name: 'Damar Inc', email: 'damar@example.com', timeZone: 'America/New_York' },
  { name: 'Elang GmbH', email: 'elang@example.com', timeZone: 'UTC' },
];

// 50 more customers so the customers list has real 50-row pages. Invoices and
// transactions stay on the first five — the bulk rows only pad the list.
const BULK_CUSTOMERS = Array.from({ length: 50 }, (_, i) => ({
  name: `Bulk ${String(i + 1).padStart(2, '0')} Pte`,
  email: `bulk-${String(i + 1).padStart(2, '0')}@example.com`,
  timeZone: 'UTC',
}));

// 2026-01-01T00:00:00Z, then one row per interval. Fixed epoch, no Date.now().
const EPOCH = Date.parse('2026-01-01T00:00:00.000Z');

const AUDIT_ACTIONS = ['invoice.created', 'invoice.paid', 'refund.issued'];

export async function seed(prisma: PrismaClient) {
  await prisma.auditEvent.deleteMany();
  await prisma.refund.deleteMany();
  await prisma.invoice.deleteMany();
  await prisma.transaction.deleteMany();
  await prisma.customer.deleteMany();

  await prisma.customer.createMany({ data: [...CUSTOMERS, ...BULK_CUSTOMERS] });
  const customers = await prisma.customer.findMany({ orderBy: { id: 'asc' } });
  const core = customers.slice(0, CUSTOMERS.length);

  await prisma.invoice.createMany({
    data: Array.from({ length: 60 }, (_, i) => ({
      number: `INV-${String(i + 1).padStart(4, '0')}`,
      amountCents: 100_000 + i * 1_000,
      currency: 'IDR',
      status: i % 5 === 0 ? 'paid' : 'open',
      createdAt: new Date(EPOCH + i * 3_600_000),
      customerId: core[i % core.length].id,
    })),
  });
  const invoices = await prisma.invoice.findMany({ orderBy: { id: 'asc' } });

  // 60 refunds spread over the first 12 invoices — enough rows for a 50-row page.
  await prisma.refund.createMany({
    data: Array.from({ length: 60 }, (_, i) => ({
      amountCents: 1_000 * (i + 1),
      reason: `reason-${i + 1}`,
      createdAt: new Date(EPOCH + i * 60_000),
      invoiceId: invoices[i % 12].id,
    })),
  });

  // Transactions straddling midnight in several zones — the reports and date
  // tasks live here. The first seven rows are load-bearing for the visible
  // reports test; the Borneo block only gives one customer a long activity feed.
  await prisma.transaction.createMany({
    data: [
      { amountCents: 1_000, occurredAt: new Date('2026-03-02T16:30:00.000Z'), customerId: core[0].id },
      { amountCents: 2_000, occurredAt: new Date('2026-03-02T17:30:00.000Z'), customerId: core[0].id },
      { amountCents: 4_000, occurredAt: new Date('2026-03-03T02:00:00.000Z'), customerId: core[0].id },
      { amountCents: 8_000, occurredAt: new Date('2026-03-02T10:30:00.000Z'), customerId: core[2].id },
      { amountCents: 16_000, occurredAt: new Date('2026-03-02T11:30:00.000Z'), customerId: core[2].id },
      { amountCents: 32_000, occurredAt: new Date('2026-03-03T03:30:00.000Z'), customerId: core[3].id },
      { amountCents: 64_000, occurredAt: new Date('2026-03-03T05:30:00.000Z'), customerId: core[3].id },
      ...Array.from({ length: 60 }, (_, i) => ({
        amountCents: 500 * (i + 1),
        occurredAt: new Date(Date.parse('2026-04-01T00:00:00.000Z') + i * 3 * 3_600_000),
        customerId: core[1].id,
      })),
    ],
  });

  // 58 generic events no test asserts on, then two Damar (New York) events
  // straddling their local midnight — those two carry the audit summary trap.
  await prisma.auditEvent.createMany({
    data: [
      ...Array.from({ length: 58 }, (_, i) => ({
        action: AUDIT_ACTIONS[i % 3],
        entity: 'invoice',
        entityId: (i % 60) + 1,
        createdAt: new Date(EPOCH + i * 7_200_000),
        customerId: [core[0].id, core[1].id, core[2].id, core[4].id][i % 4],
      })),
      { action: 'invoice.paid', entity: 'invoice', entityId: 1, createdAt: new Date('2026-03-03T03:30:00.000Z'), customerId: core[3].id },
      { action: 'refund.issued', entity: 'invoice', entityId: 1, createdAt: new Date('2026-03-03T05:30:00.000Z'), customerId: core[3].id },
    ],
  });
}

if (typeof require !== 'undefined' && require.main === module) {
  const prisma = new PrismaClient();
  seed(prisma)
    .then(() => prisma.$disconnect())
    .catch(async (e) => {
      console.error(e);
      await prisma.$disconnect();
      process.exit(1);
    });
}
